import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/features/history/data/history_sync_service.dart';
import 'package:soplay/features/history/domain/entities/history_item.dart';
import 'package:soplay/features/my_list/data/private_list_service.dart';

class HistoryService {
  static const int _maxItems = 50;

  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  Box get _box => Hive.box(AppConstants.historyBox);

  List<HistoryItem> getAll() {
    final items = <HistoryItem>[];
    for (final key in _box.keys) {
      try {
        final raw = _box.get(key);
        if (raw is String) {
          items.add(
            HistoryItem.fromJson(jsonDecode(raw) as Map<String, dynamic>),
          );
        }
      } catch (_) {}
    }
    items.sort((a, b) => b.watchedAt.compareTo(a.watchedAt));
    return items;
  }

  HistoryItem? get(String contentUrl, {int? episodeIndex, int? episodeNumber}) {
    final key = HistoryItem.buildStorageKey(
      contentUrl: contentUrl,
      isSerial: episodeIndex != null || episodeNumber != null,
      episodeIndex: episodeIndex,
      episodeNumber: episodeNumber,
    );
    final raw = _box.get(key) ?? _box.get(contentUrl);
    if (raw is String) {
      try {
        return HistoryItem.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {}
    }
    if (episodeIndex == null && episodeNumber == null) {
      return _getLatestForContent(contentUrl);
    }
    return null;
  }

  HistoryItem? _getLatestForContent(String contentUrl) {
    final prefix = '$contentUrl::episode::';
    HistoryItem? latest;
    for (final key in _box.keys) {
      if (key is! String || !key.startsWith(prefix)) continue;
      try {
        final raw = _box.get(key);
        if (raw is! String) continue;
        final item =
            HistoryItem.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        if (latest == null || item.watchedAt > latest.watchedAt) {
          latest = item;
        }
      } catch (_) {}
    }
    return latest;
  }

  Future<void> save(HistoryItem item) async {
    if (getIt.isRegistered<PrivateListService>() &&
        getIt<PrivateListService>().contains(item.contentUrl)) {
      return;
    }
    await _box.put(item.storageKey, jsonEncode(item.toJson()));
    await _trimIfNeeded();
    revision.value++;
  }

  /// Reads a row back so a delete can be described to the server before the
  /// local copy is gone.
  HistoryItem? _read(String key) {
    final raw = _box.get(key);
    if (raw is! String) return null;
    try {
      return HistoryItem.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

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
    revision.value++;
  }

  Future<void> clearAll() async {
    if (getIt.isRegistered<HistorySyncService>()) {
      final sync = getIt<HistorySyncService>();
      await sync.rememberClearedAll();
      unawaited(sync.sync());
    }
    await _box.clear();
    revision.value++;
  }

  Future<void> _trimIfNeeded() async {
    if (_box.length <= _maxItems) return;
    final items = getAll();
    if (items.length <= _maxItems) return;
    final toRemove = items.sublist(_maxItems);
    for (final item in toRemove) {
      await _box.delete(item.storageKey);
    }
  }
}
