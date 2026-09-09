import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/features/my_list/data/models/favorite_model.dart';
import 'package:soplay/features/my_list/domain/entities/favorite_entity.dart';

class MyListLocalDataSource {
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  Box get _box => Hive.box(AppConstants.favoritesBox);

  String _key(String provider, String contentUrl) => '$provider::$contentUrl';

  List<FavoriteModel> getAll() {
    final items = <FavoriteModel>[];
    for (final key in _box.keys) {
      try {
        final raw = _box.get(key);
        if (raw is String) {
          items.add(
            FavoriteModel.fromJson(jsonDecode(raw) as Map<String, dynamic>),
          );
        }
      } catch (_) {}
    }
    items.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return items;
  }

  bool isFavorite(String provider, String contentUrl) =>
      _box.containsKey(_key(provider, contentUrl));

  bool isFavoriteByUrl(String contentUrl) {
    for (final key in _box.keys) {
      try {
        final raw = _box.get(key);
        if (raw is! String) continue;
        final model = FavoriteModel.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
        if (model.contentUrl == contentUrl) return true;
      } catch (_) {}
    }
    return false;
  }

  Future<void> add(FavoriteEntity e, {bool synced = false}) async {
    final model = FavoriteModel(
      provider: e.provider,
      contentUrl: e.contentUrl,
      title: e.title,
      thumbnail: e.thumbnail,
      description: e.description,
      addedAt: DateTime.now().millisecondsSinceEpoch,
      synced: synced,
    );
    await _box.put(_key(e.provider, e.contentUrl), jsonEncode(model.toJson()));
    revision.value++;
  }

  Future<void> markSynced(String contentUrl) async {
    final updates = <dynamic, String>{};
    for (final key in _box.keys) {
      try {
        final raw = _box.get(key);
        if (raw is! String) continue;
        final model = FavoriteModel.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
        if (model.contentUrl != contentUrl || model.synced) continue;
        updates[key] = jsonEncode(_withSynced(model).toJson());
      } catch (_) {}
    }
    if (updates.isEmpty) return;
    for (final entry in updates.entries) {
      await _box.put(entry.key, entry.value);
    }
    revision.value++;
  }

  FavoriteModel _withSynced(FavoriteModel m) => FavoriteModel(
    provider: m.provider,
    contentUrl: m.contentUrl,
    title: m.title,
    thumbnail: m.thumbnail,
    description: m.description,
    addedAt: m.addedAt,
    synced: true,
  );

  Future<void> removeByUrl(String contentUrl) async {
    final keysToDelete = <dynamic>[];
    for (final key in _box.keys) {
      try {
        final raw = _box.get(key);
        if (raw is! String) continue;
        final model = FavoriteModel.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
        if (model.contentUrl == contentUrl) keysToDelete.add(key);
      } catch (_) {}
    }
    for (final key in keysToDelete) {
      await _box.delete(key);
    }
    revision.value++;
  }

  /// Merges the server's list into the local cache.
  ///
  /// [revision] is bumped only when something actually changed. It was bumped
  /// unconditionally, and My List refreshes on every bump — so a refresh wrote
  /// the same rows back, bumped, and refreshed again. The loop ran as fast as
  /// the network allowed until the server answered 429.

  /// Drops the whole local cache without recording anything to sync.
  ///
  /// For sign-out. These rows came down from the account and go back up on the
  /// next sign-in (see MyListRepositoryImpl, which upserts the server list),
  /// so nothing is lost — but leaving them means the next person to open the
  /// app sees the previous account's saved titles.
  ///
  /// Deliberately not a delete-per-row: a row removed the ordinary way is
  /// queued as a change to push, and pushing a delete for every saved title
  /// would empty the account rather than the device.
  Future<void> clearLocalOnly() async {
    await _box.clear();
    revision.value++;
  }

  Future<void> upsertAll(Iterable<FavoriteEntity> items) async {
    var changed = false;
    for (final e in items) {
      final key = _key(e.provider, e.contentUrl);
      if (_box.containsKey(key)) {
        try {
          final raw = _box.get(key);
          if (raw is String) {
            final existing = FavoriteModel.fromJson(
              jsonDecode(raw) as Map<String, dynamic>,
            );
            if (!existing.synced) {
              await _box.put(key, jsonEncode(_withSynced(existing).toJson()));
              changed = true;
            }
          }
        } catch (_) {}
        continue;
      }
      final model = FavoriteModel(
        provider: e.provider,
        contentUrl: e.contentUrl,
        title: e.title,
        thumbnail: e.thumbnail,
        description: e.description,
        addedAt: e is FavoriteModel && e.addedAt > 0
            ? e.addedAt
            : DateTime.now().millisecondsSinceEpoch,
        synced: true,
      );
      await _box.put(key, jsonEncode(model.toJson()));
      changed = true;
    }
    if (changed) revision.value++;
  }
}
