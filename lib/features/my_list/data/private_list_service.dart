import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/storage/profile_scope.dart';
import 'package:soplay/features/my_list/data/models/favorite_model.dart';
import 'package:soplay/features/my_list/domain/entities/favorite_entity.dart';

class PrivateListService {
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  bool _unlocked = false;

  bool get isUnlockedForSession => _unlocked;

  void markUnlocked() => _unlocked = true;

  void lock() => _unlocked = false;

  Box get _box => Hive.box(ProfileScope.box(AppConstants.privateFavoritesBox));

  List<FavoriteEntity> getAll() {
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

  bool contains(String contentUrl) => _box.containsKey(contentUrl);

  Future<void> add(FavoriteEntity e) async {
    final model = FavoriteModel(
      provider: e.provider,
      contentUrl: e.contentUrl,
      title: e.title,
      thumbnail: e.thumbnail,
      description: e.description,
      addedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _box.put(e.contentUrl, jsonEncode(model.toJson()));
    revision.value++;
  }

  Future<void> remove(String contentUrl) async {
    await _box.delete(contentUrl);
    revision.value++;
  }

  Future<void> clearAll() async {
    await _box.clear();
    revision.value++;
  }
}
