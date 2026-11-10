import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/storage/profile_scope.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/history/data/history_sync_service.dart';
import 'package:soplay/features/history/domain/entities/history_item.dart';
import 'package:soplay/features/history/domain/history_trim.dart';
import 'package:soplay/features/my_list/data/private_list_service.dart';

class HistoryService {
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Decoded rows, keyed by box key and reused while the stored string is the
  /// same instance. Hive keeps values in memory, so an unchanged row hands back
  /// the identical string and its decode can be skipped.
  final Map<dynamic, (String, HistoryItem)> _decoded = {};

  /// The last [getAll] result, dropped on any change to the box.
  List<HistoryItem>? _sorted;
  Box? _watched;
  StreamSubscription<BoxEvent>? _watch;

  Box get _box {
    final box = Hive.box(ProfileScope.box(AppConstants.historyBox));
    if (!identical(box, _watched)) {
      // A profile switch or a reopened box: nothing cached describes it.
      _watch?.cancel();
      _watched = box;
      _invalidate();
      _watch = box.watch().listen((event) {
        _decoded.remove(event.key);
        _sorted = null;
      });
    }
    return box;
  }

  void _invalidate([Object? key]) {
    if (key == null) {
      _decoded.clear();
    } else {
      _decoded.remove(key);
    }
    _sorted = null;
  }

  /// Decode count, for tests.
  @visibleForTesting
  int decodes = 0;

  HistoryItem? _decode(Object? key, Object? raw) {
    if (raw is! String) return null;
    final hit = _decoded[key];
    if (hit != null && identical(hit.$1, raw)) return hit.$2;
    try {
      decodes++;
      final item = HistoryItem.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      _decoded[key] = (raw, item);
      return item;
    } catch (_) {
      return null;
    }
  }

  /// How many rows are stored, without decoding any of them. The box also
  /// holds the manga reader's chapter marks, which are not rows.
  int get count {
    final box = _box;
    final cached = _sorted;
    if (cached != null) return cached.length;
    var n = 0;
    for (final key in box.keys) {
      if (key is String && key.startsWith(_chapterMarkPrefix)) continue;
      n++;
    }
    return n;
  }

  static const _chapterMarkPrefix = 'chapters_read:';

  List<HistoryItem> getAll() {
    final box = _box;
    final cached = _sorted;
    if (cached != null) return List.of(cached);
    final items = <HistoryItem>[];
    for (final key in box.keys) {
      final item = _decode(key, box.get(key));
      if (item != null) items.add(item);
    }
    items.sort((a, b) => b.watchedAt.compareTo(a.watchedAt));
    _sorted = List.unmodifiable(items);
    return items;
  }

  HistoryItem? get(String contentUrl, {int? episodeIndex, int? episodeNumber}) {
    final key = HistoryItem.buildStorageKey(
      contentUrl: contentUrl,
      isSerial: episodeIndex != null || episodeNumber != null,
      episodeIndex: episodeIndex,
      episodeNumber: episodeNumber,
    );
    final box = _box;
    final direct =
        _decode(key, box.get(key)) ?? _decode(contentUrl, box.get(contentUrl));
    if (direct != null) return direct;
    if (episodeIndex == null && episodeNumber == null) {
      return _getLatestForContent(contentUrl);
    }
    return null;
  }

  HistoryItem? _getLatestForContent(String contentUrl) {
    final prefix = '$contentUrl::episode::';
    HistoryItem? latest;
    final box = _box;
    for (final key in box.keys) {
      if (key is! String || !key.startsWith(prefix)) continue;
      final item = _decode(key, box.get(key));
      if (item == null) continue;
      if (latest == null || item.watchedAt > latest.watchedAt) {
        latest = item;
      }
    }
    return latest;
  }

  Future<void> save(HistoryItem item) => _write(item, notify: true);

  /// [save] without telling listeners. For the player's five-second progress
  /// tick: every listener — Home's Continue rail, the episode list, the detail
  /// header, the home-screen widget — re-reads and re-decodes the box and
  /// rebuilds, under a player that covers all of them. They catch up from the
  /// save on pause and on exit.
  Future<void> saveQuietly(HistoryItem item) => _write(item, notify: false);

  /// Whether a quiet write has landed that listeners have not been told of.
  bool _quietPending = false;

  /// Tells listeners about quiet writes, if there were any since the last
  /// notification. For the moments the player hands the screen back — pause,
  /// exit — when its own final save may write nothing (an episode played to
  /// its end), and the rows the quiet ticks wrote would otherwise never show.
  void flushQuiet() {
    if (!_quietPending) return;
    _quietPending = false;
    revision.value++;
  }

  Future<void> _write(HistoryItem item, {required bool notify}) async {
    // Incognito is enforced here rather than at the call sites. History is
    // written from the player, the detail page, shorts and the sync service's
    // own merge, and a mode whose guarantee depends on every one of those
    // remembering to ask is not a guarantee. One chokepoint, same as the
    // private-list check below it.
    if (getIt.isRegistered<HiveService>() && getIt<HiveService>().isIncognito) {
      return;
    }
    if (getIt.isRegistered<PrivateListService>() &&
        getIt<PrivateListService>().contains(item.contentUrl)) {
      return;
    }
    _invalidate(item.storageKey);
    await _box.put(item.storageKey, jsonEncode(item.toJson()));
    _invalidate(item.storageKey);
    await _trimIfNeeded();
    if (notify) {
      _quietPending = false;
      revision.value++;
    } else {
      _quietPending = true;
    }
  }

  /// Reads a row back so a delete can be described to the server before the
  /// local copy is gone.
  HistoryItem? _read(String key) => _decode(key, _box.get(key));

  /// Deleting locally is only half of it: the row also exists on the account,
  /// and until the server is told, signing out and back in simply downloads it
  /// again. [HistorySyncService] already knows how to carry a delete — nothing
  /// was calling it. Recorded BEFORE the row is removed, because the tombstone
  /// is built from the row itself.
  Future<void> _rememberDeleted(Iterable<HistoryItem> items) async {
    if (items.isEmpty) return;
    if (!getIt.isRegistered<HistorySyncService>()) return;
    final sync = getIt<HistorySyncService>();
    for (final item in items) {
      await sync.rememberDeleted(item);
    }
    unawaited(sync.sync());
  }

  Future<void> remove(String key) async {
    final item = _read(key);
    if (item != null) await _rememberDeleted([item]);
    await _box.delete(key);
    _invalidate(key);
    revision.value++;
  }

  Future<void> removeByContentUrl(String contentUrl) async {
    final keys = _box.keys
        .whereType<String>()
        .where((k) => k == contentUrl || k.startsWith('$contentUrl::'))
        .toList();
    await _rememberDeleted(
      keys.map(_read).whereType<HistoryItem>().toList(growable: false),
    );
    for (final k in keys) {
      await _box.delete(k);
      _invalidate(k);
    }
    if (keys.isNotEmpty) revision.value++;
  }

  /// Drops every local row WITHOUT recording tombstones.
  ///
  /// The distinction from [clearAll] matters: this is not a user deleting their
  /// history, it is these rows turning out to belong to a different account
  /// (see HistorySyncService.adoptFor). Tombstoning them would push a delete
  /// for each one into whichever account signs in next.
  Future<void> clearLocalOnly() async {
    await _box.clear();
    _invalidate();
    revision.value++;
  }

  Future<void> clearAll() async {
    if (getIt.isRegistered<HistorySyncService>()) {
      final sync = getIt<HistorySyncService>();
      await sync.rememberClearedAll();
      unawaited(sync.sync());
    }
    await _box.clear();
    _invalidate();
    revision.value++;
  }

  /// Drops what the store no longer has room for — see [HistoryTrim] for which
  /// rows those are and why the rule is not a single number any more.
  ///
  /// Deliberately not tombstoned: a trim is this device running out of room,
  /// not the viewer deleting something. Telling the server would erase the row
  /// from the account and from every other device too.
  Future<void> _trimIfNeeded() async {
    if (_box.length <= HistoryTrim.maxRows) return;
    final doomed = HistoryTrim.keysToDrop([
      for (final item in getAll())
        (
          key: item.storageKey,
          contentUrl: item.contentUrl,
          watchedAt: item.watchedAt,
        ),
    ]);
    for (final key in doomed) {
      await _box.delete(key);
      _invalidate(key);
    }
  }
}
