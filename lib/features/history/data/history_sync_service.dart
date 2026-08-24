import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/features/history/data/history_service.dart';
import 'package:soplay/features/history/data/history_sync_remote_data_source.dart';
import 'package:soplay/features/history/domain/entities/history_item.dart';

/// Keeps this phone's watch history in step with the signed-in account.
///
/// WHAT ACTUALLY SYNCS, and why it is not simply "everything":
///
/// A TV row is a Room record keyed by a provider `session` — a handle for one
/// episode stream on that box. Its `contentUrl` is a stream address, not
/// something this app can open. Materialising it here would fill History with
/// rows that lead nowhere.
///
/// So the split is deliberate and symmetric with the TV's:
///   * phone → phone  full rows.
///   * phone ↔ TV     resume position on content both can name. If the TV got
///                    further into an episode this phone already knows, the
///                    phone picks up there. A TV-only title stays on the server
///                    for the TV and is not faked into this list.
///
/// Deletes travel as tombstones. Hive deletes leave nothing behind to upload,
/// so without recording one the next sync would see the server's copy as new
/// and put the row straight back.
class HistorySyncService {
  HistorySyncService({
    required HistorySyncRemoteDataSource remote,
    required HistoryService local,
  }) : _remote = remote,
       _local = local;

  final HistorySyncRemoteDataSource _remote;
  final HistoryService _local;

  Box get _state => Hive.box(AppConstants.settingsBox);

  static const String _cursorKey = 'history_sync_cursor';
  static const String _pushedAtKey = 'history_sync_pushed_at';
  static const String _tombstonesKey = 'history_sync_tombstones';
  static const String _ownerKey = 'history_sync_owner';

  bool _running = false;

  /// True once this account has ever synced here.
  bool get hasSynced => _state.get(_cursorKey) != null;

  /// Canonical identity, mirroring the server's `buildHistoryKey` EXACTLY.
  ///
  /// Drifting from it splits one episode into two rows that never reconcile,
  /// so this and the server's copy must change together.
  static String? keyOf(HistoryItem item) {
    final base = item.contentUrl.trim();
    if (base.isEmpty) return null;
    final head = '${item.provider.trim()}|$base';
    if (!item.isSerial) return head;
    final episode = item.episodeNumber ?? item.episodeIndex;
    return episode == null ? head : '$head|e$episode';
  }

  /// Push local changes, pull everyone else's, write the result to Hive.
  ///
  /// Guarded by [_running] because playback-end and screen-open can both land
  /// here at once; two interleaved runs would push the same rows twice and race
  /// over the cursor.
  ///
  /// Returns false when nothing could be done — signed out, or offline. That is
  /// "try again later", never an error worth showing.
  Future<bool> sync() async {
    if (_running) return false;
    _running = true;
    try {
      final since = _state.get(_cursorKey) as String?;
      final pushedAt = (_state.get(_pushedAtKey) as num?)?.toInt() ?? 0;
      final tombstones = _readTombstones();

      final outgoing = <HistorySyncItem>[
        // Only rows touched since the last successful push. Uploading
        // everything each time would rewrite the whole server list and wake
        // every other device for nothing.
        for (final item in _local.getAll())
          if (item.watchedAt > pushedAt) _toSyncItem(item),
        for (final entry in tombstones.entries)
          HistorySyncItem(
            provider: '',
            key: entry.key,
            deletedAt: entry.value,
            watchedAt: entry.value,
          ),
      ];

      final result = await _remote.sync(items: outgoing, since: since);
      await _applyRemote(result.items);

      await _state.put(_cursorKey, result.serverTime ?? since);
      // Stamped from the rows just sent, not from "now": a row written while
      // the request was in flight must still be picked up next time.
      final highest = outgoing
          .map((e) => DateTime.tryParse(e.watchedAt ?? '')?.millisecondsSinceEpoch ?? 0)
          .fold<int>(pushedAt, (a, b) => b > a ? b : a);
      await _state.put(_pushedAtKey, highest);
      await _state.delete(_tombstonesKey);
      return true;
    } catch (_) {
      // Offline or signed out. Tombstones are deliberately kept: they must
      // survive until a sync actually accepts them.
      return false;
    } finally {
      _running = false;
    }
  }

  /// Records a delete so it can travel. Call BEFORE removing the local row.
  Future<void> rememberDeleted(HistoryItem item) async {
    final key = keyOf(item);
    if (key == null) return;
    final all = _readTombstones()
      ..[key] = DateTime.now().toUtc().toIso8601String();
    await _state.put(_tombstonesKey, jsonEncode(all));
  }

  /// Records a full clear. Call BEFORE clearing local history.
  Future<void> rememberClearedAll() async {
    final now = DateTime.now().toUtc().toIso8601String();
    final all = _readTombstones();
    for (final item in _local.getAll()) {
      final key = keyOf(item);
      if (key != null) all[key] = now;
    }
    if (all.isEmpty) return;
    await _state.put(_tombstonesKey, jsonEncode(all));
  }

  /// Sign-out must not leave one account's cursor pointing at another's history.
  ///
  /// The Hive rows are deliberately LEFT ALONE here — someone who signs out and
  /// keeps watching still has their Continue Watching list. What makes that safe
  /// is [adoptFor], which refuses to hand those rows to a different account.
  Future<void> clear() async {
    await _state.delete(_cursorKey);
    await _state.delete(_pushedAtKey);
    await _state.delete(_tombstonesKey);
  }

  /// Decides whether the rows already on this phone belong to [userId].
  ///
  /// Sign-out clears the cursor, which resets the push watermark to zero — so
  /// the first sync after ANY sign-in uploads every local row. That is right
  /// when the same person signs back in, or when someone who had been watching
  /// signed out finally makes an account: their viewing follows them.
  ///
  /// It is badly wrong when the next sign-in is somebody else. Handing one
  /// person's watch history to another account is not a sync bug, it is a leak,
  /// and nothing was stopping it. So the rows are stamped with the account they
  /// belong to, and a different owner wipes them before the first sync can push
  /// them anywhere.
  ///
  /// Unstamped rows have no owner yet (signed-out viewing, or an install from
  /// before this existed) and are adopted rather than destroyed.
  Future<void> adoptFor(String userId) async {
    final id = userId.trim();
    if (id.isEmpty) return;

    final owner = _state.get(_ownerKey) as String?;
    if (owner == id) return;

    if (owner != null && owner != id) {
      await _local.clearLocalOnly();
      // The cursor and the outgoing tombstones described the previous account.
      await clear();
    }
    await _state.put(_ownerKey, id);
  }

  // ─── applying the server's answer ──────────────────────────────────────────

  Future<void> _applyRemote(List<HistorySyncItem> items) async {
    if (items.isEmpty) return;
    final byKey = {
      for (final item in _local.getAll())
        if (keyOf(item) != null) keyOf(item)!: item,
    };

    for (final remote in items) {
      final key = remote.key;
      if (key == null) continue;
      final local = byKey[key];

      if (remote.isDeleted) {
        if (local != null) await _local.remove(local.storageKey);
        continue;
      }

      final watchedAt =
          DateTime.tryParse(remote.watchedAt ?? '')?.millisecondsSinceEpoch ?? 0;

      if (local != null) {
        // A row this phone already has: take the newer position only.
        if (watchedAt > local.watchedAt) {
          await _local.save(
            local.copyWith(
              positionMs: remote.positionMs,
              durationMs: remote.durationMs > 0
                  ? remote.durationMs
                  : local.durationMs,
              watchedAt: watchedAt,
            ),
          );
        }
        continue;
      }

      // No local row. Only a phone-origin row can be rebuilt here — a TV row's
      // contentUrl is a stream address this app cannot open, and a History
      // entry that leads nowhere is worse than a missing one.
      final contentUrl = remote.contentUrl;
      if (remote.extra != null || contentUrl == null || contentUrl.isEmpty) {
        continue;
      }
      await _local.save(
        HistoryItem(
          contentUrl: contentUrl,
          provider: remote.provider,
          title: remote.title ?? '',
          thumbnail: remote.thumbnail,
          isSerial: remote.isSerial,
          episodeIndex: remote.episodeIndex,
          episodeNumber: remote.episodeNumber,
          episodeLabel: remote.episodeLabel,
          positionMs: remote.positionMs,
          durationMs: remote.durationMs,
          watchedAt: watchedAt == 0
              ? DateTime.now().millisecondsSinceEpoch
              : watchedAt,
        ),
      );
    }
  }

  HistorySyncItem _toSyncItem(HistoryItem item) => HistorySyncItem(
    provider: item.provider,
    contentUrl: item.contentUrl,
    title: item.title,
    thumbnail: item.thumbnail,
    isSerial: item.isSerial,
    episodeIndex: item.episodeIndex,
    episodeNumber: item.episodeNumber,
    episodeLabel: item.episodeLabel,
    positionMs: item.positionMs,
    durationMs: item.durationMs,
    watchedAt: DateTime.fromMillisecondsSinceEpoch(
      item.watchedAt,
    ).toUtc().toIso8601String(),
  );

  Map<String, String> _readTombstones() {
    final raw = _state.get(_tombstonesKey);
    if (raw is! String) return <String, String>{};
    try {
      return (jsonDecode(raw) as Map).cast<String, String>();
    } catch (_) {
      return <String, String>{};
    }
  }
}
