import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/storage/profile_scope.dart';
import 'package:soplay/features/tracker/data/follow_service.dart';
import 'package:soplay/features/tracker/data/follow_sync_remote_data_source.dart';
import 'package:soplay/features/tracker/domain/entities/followed_title.dart';

/// Keeps the profile's follows on the account, so the server can announce new
/// episodes with the app closed and a second phone follows the same titles.
///
/// Each change is queued first and sent second: a follow made on a train is
/// kept in [_outboxKey] and goes up when the network is back — on the next
/// change, the next resume, or a retry timer. A full `/follows/sync` runs on
/// sign-in, on a profile switch and (throttled) at startup, and settles
/// anything the queue missed.
///
/// Guests never reach the network: without an account there is nothing to
/// sync to, and their follows are checked on the device instead.
///
/// A 404 from `/follows` means the route is not deployed on this server. That
/// is remembered as [serverLive] = false and everything carries on locally —
/// FollowCoverage then keeps the device announcing every title.
class FollowSyncService implements FollowChangeSink {
  FollowSyncService({
    required FollowSyncRemoteDataSource remote,
    required FollowService follows,
    required bool Function() isSignedIn,
    Box? box,
    DateTime Function()? now,
  }) : _remote = remote,
       _follows = follows,
       _isSignedIn = isSignedIn,
       _override = box,
       _now = now ?? DateTime.now;

  final FollowSyncRemoteDataSource _remote;
  final FollowService _follows;
  final bool Function() _isSignedIn;
  final Box? _override;
  final DateTime Function() _now;

  Box get _box => _override ?? Hive.box(AppConstants.settingsBox);

  static const String _outboxKey = 'follow_sync_outbox';
  static const String _tombstonesKey = 'follow_sync_tombstones';
  static const String _syncedAtKey = 'follow_sync_at';
  static const String _liveKey = 'follow_server_live';

  /// A startup sync is skipped when the last one is younger than this.
  static const Duration startupThrottle = Duration(hours: 6);

  /// More queued changes than this go up as one sync instead of one by one.
  static const int batchThreshold = 12;

  static const List<Duration> _retryDelays = [
    Duration(seconds: 30),
    Duration(minutes: 2),
    Duration(minutes: 10),
    Duration(minutes: 30),
  ];

  /// Bumped when follows change because of the account, and when
  /// [serverLive] flips.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  bool _flushing = false;
  bool _syncing = false;
  Timer? _retry;
  int _attempt = 0;

  /// Whether `/follows` has ever answered. Until it has, the server cannot be
  /// covering anything.
  bool get serverLive => _box.get(_liveKey) == true;

  Future<void> _setLive(bool live) async {
    if (serverLive == live) return;
    await _box.put(_liveKey, live);
    revision.value++;
  }

  // ─── the queue ────────────────────────────────────────────────────────────

  Map<String, Map<String, dynamic>> _readOutbox() => _readMap(_outboxKey);

  Map<String, Map<String, dynamic>> _readMap(String key) {
    final raw = _box.get(ProfileScope.key(key));
    if (raw is! String || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return {
        for (final e in decoded.entries)
          if (e.value is Map)
            e.key.toString(): (e.value as Map).cast<String, dynamic>(),
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeMap(String key, Map<String, Map<String, dynamic>> map) =>
      map.isEmpty
      ? _box.delete(ProfileScope.key(key))
      : _box.put(ProfileScope.key(key), jsonEncode(map));

  /// Whether [key] is waiting to go up — the server cannot know about it yet.
  bool isPending(String key) => _readOutbox().containsKey(key);

  int get pendingCount => _readOutbox().length;

  /// Folds [op] into whatever is already queued for the same title.
  @visibleForTesting
  static Map<String, dynamic> collapse(
    Map<String, dynamic>? queued,
    Map<String, dynamic> op,
  ) {
    if (queued == null) return op;
    final was = queued['op'];
    final next = op['op'];
    if (next == 'delete' || next == 'upsert') return op;
    // A patch on top of an upsert is already in the upsert: it sends the
    // title as it stands when the queue is flushed.
    if (was == 'upsert') return queued;
    if (was == 'delete') return queued;
    return {
      ...queued,
      for (final e in op.entries)
        if (e.value != null) e.key: e.value,
    };
  }

  Future<void> _enqueue(FollowedTitle t, Map<String, dynamic> op) async {
    if (!_isSignedIn()) return;
    final outbox = _readOutbox();
    outbox[t.key] = collapse(outbox[t.key], {
      ...op,
      'provider': t.provider,
      'contentUrl': t.contentUrl,
    });
    await _writeMap(_outboxKey, outbox);
    if (op['op'] == 'delete') {
      final tombs = _readMap(_tombstonesKey);
      tombs[t.key] = {
        'provider': t.provider,
        'contentUrl': t.contentUrl,
        'at': _now().millisecondsSinceEpoch,
      };
      await _writeMap(_tombstonesKey, tombs);
    } else if (op['op'] == 'upsert') {
      final tombs = _readMap(_tombstonesKey)..remove(t.key);
      await _writeMap(_tombstonesKey, tombs);
    }
    unawaited(flush());
  }

  @override
  void followed(FollowedTitle title) =>
      unawaited(_enqueue(title, {'op': 'upsert'}));

  @override
  void unfollowed(FollowedTitle title) =>
      unawaited(_enqueue(title, {'op': 'delete'}));

  @override
  void patched(FollowedTitle title, {bool? notify, int? lastEpisodeCount}) =>
      unawaited(
        _enqueue(title, {
          'op': 'patch',
          'notify': ?notify,
          'lastEpisodeCount': ?lastEpisodeCount,
        }),
      );

  /// Sends what is queued. Returns true when the queue is empty afterwards.
  Future<bool> flush() async {
    if (!_isSignedIn() || _flushing || _syncing) return false;
    var outbox = _readOutbox();
    if (outbox.isEmpty) return true;
    if (outbox.length > batchThreshold) return fullSync(force: true);
    _flushing = true;
    try {
      final local = {for (final t in _follows.list()) t.key: t};
      for (final entry in outbox.entries.toList()) {
        final op = entry.value;
        final provider = '${op['provider'] ?? ''}';
        final url = '${op['contentUrl'] ?? ''}';
        try {
          switch (op['op']) {
            case 'upsert':
              final t = local[entry.key];
              if (t != null) await _remote.add(t);
            case 'delete':
              await _remote.remove(provider, url);
            default:
              try {
                await _remote.patch(
                  provider,
                  url,
                  notify: op['notify'] as bool?,
                  lastEpisodeCount: (op['lastEpisodeCount'] as num?)?.toInt(),
                );
              } on FollowNotFound {
                final t = local[entry.key];
                if (t != null) await _remote.add(t);
              }
          }
          await _setLive(true);
        } on FollowsNotDeployed {
          await _setLive(false);
          return false;
        } on FollowRejected {
          // Past the follow limit, or a shape the server will never take.
        } on DioException {
          _scheduleRetry();
          return false;
        }
        outbox = _readOutbox()..remove(entry.key);
        await _writeMap(_outboxKey, outbox);
        if (op['op'] == 'delete') {
          final tombs = _readMap(_tombstonesKey)..remove(entry.key);
          await _writeMap(_tombstonesKey, tombs);
        }
      }
      _attempt = 0;
      return _readOutbox().isEmpty;
    } catch (e) {
      if (kDebugMode) debugPrint('[follow-sync] flush failed: $e');
      _scheduleRetry();
      return false;
    } finally {
      _flushing = false;
    }
  }

  void _scheduleRetry() {
    if (_retry?.isActive == true) return;
    final delay = _retryDelays[_attempt.clamp(0, _retryDelays.length - 1)];
    _attempt++;
    _retry = Timer(delay, () => unawaited(flush()));
  }

  /// Pushes every follow and tombstone and takes the account's merged list.
  ///
  /// [force] is for sign-in and profile switches; startup passes false and is
  /// throttled to [startupThrottle].
  Future<bool> fullSync({bool force = false}) async {
    if (!_isSignedIn() || _syncing) return false;
    final last = _box.get(ProfileScope.key(_syncedAtKey));
    if (!force &&
        last is int &&
        _now().difference(DateTime.fromMillisecondsSinceEpoch(last)) <
            startupThrottle) {
      return flush();
    }
    _syncing = true;
    final started = _now().millisecondsSinceEpoch;
    final sentKeys = _readOutbox().keys.toSet();
    final tombs = _readMap(_tombstonesKey);
    try {
      final merged = await _remote.sync(
        items: _follows.list(),
        deleted: [
          for (final t in tombs.values)
            (
              provider: '${t['provider'] ?? ''}',
              contentUrl: '${t['contentUrl'] ?? ''}',
              at: (t['at'] as num?)?.toInt() ?? started,
            ),
        ],
      );
      await _setLive(true);
      await _follows.adoptRemote(merged, keepAddedAfter: started);
      final outbox = _readOutbox()
        ..removeWhere((k, _) => sentKeys.contains(k));
      await _writeMap(_outboxKey, outbox);
      final remaining = _readMap(_tombstonesKey)
        ..removeWhere((k, _) => tombs.containsKey(k));
      await _writeMap(_tombstonesKey, remaining);
      await _box.put(ProfileScope.key(_syncedAtKey), started);
      _attempt = 0;
      revision.value++;
      return true;
    } on FollowsNotDeployed {
      await _setLive(false);
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('[follow-sync] sync failed: $e');
      _scheduleRetry();
      return false;
    } finally {
      _syncing = false;
    }
  }

  /// Signing out leaves the follows on the device for whoever keeps using it,
  /// but not the queue: it was addressed to the account that just left.
  Future<void> forgetQueue() async {
    _retry?.cancel();
    await _box.delete(ProfileScope.key(_outboxKey));
    await _box.delete(ProfileScope.key(_tombstonesKey));
    await _box.delete(ProfileScope.key(_syncedAtKey));
  }
}
