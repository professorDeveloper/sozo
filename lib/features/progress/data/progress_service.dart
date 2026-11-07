import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/storage/profile_scope.dart';
import 'package:soplay/features/progress/data/progress_remote_data_source.dart';
import 'package:soplay/features/progress/domain/progress.dart';

/// A level reached since the viewer last saw their level, and what it opened.
class LevelUp {
  const LevelUp({required this.from, required this.to, this.unlocked = const []});

  final int from;
  final int to;
  final List<CosmeticItem> unlocked;

  /// What reaching [level] means against the [seen] level, if anything. The
  /// first level ever seen is a baseline, not a celebration.
  static LevelUp? between(int? seen, ProgressView view) {
    final level = view.level;
    if (seen == null || level <= seen) return null;
    return LevelUp(
      from: seen,
      to: level,
      unlocked: [
        for (final c in view.catalog)
          if (c.level != null && c.level! > seen && c.level! <= level) c,
      ],
    );
  }
}

/// The active profile's XP, level and cosmetics.
///
/// Null [state] means nothing is known — signed out, or a server without
/// `/progress` yet — and every decoration hides.
class ProgressService {
  ProgressService({
    required ProgressRemoteDataSource remote,
    required HiveService hive,
  }) : _remote = remote,
       _hive = hive {
    state.value = _readCache();
  }

  final ProgressRemoteDataSource _remote;
  final HiveService _hive;

  final ValueNotifier<ProgressView?> state = ValueNotifier(null);
  final ValueNotifier<LevelUp?> pendingLevelUp = ValueNotifier(null);

  static const String viewKey = 'progress_view';
  static const String seenLevelKey = 'progress_seen_level';

  Box? get _box {
    try {
      return Hive.box(AppConstants.settingsBox);
    } catch (_) {
      return null;
    }
  }

  ProgressView? _readCache() {
    try {
      final raw = _box?.get(ProfileScope.key(viewKey));
      if (raw is String && raw.isNotEmpty) {
        return ProgressView.fromJson(
          (jsonDecode(raw) as Map).cast<String, dynamic>(),
        );
      }
    } catch (_) {}
    return null;
  }

  /// Takes a progress body from any `/progress` answer.
  Future<void> apply(Map<String, dynamic> raw) async {
    if (raw['xp'] is! num) return;
    final view = ProgressView.fromJson(raw);
    state.value = view;
    final box = _box;
    try {
      await box?.put(ProfileScope.key(viewKey), jsonEncode(raw));
      final seen = box?.get(ProfileScope.key(seenLevelKey));
      final up = LevelUp.between(seen is int ? seen : null, view);
      if (up != null) {
        final had = pendingLevelUp.value;
        pendingLevelUp.value = had == null
            ? up
            : LevelUp(
                from: had.from,
                to: up.to,
                unlocked: [...had.unlocked, ...up.unlocked],
              );
      }
      if (seen is! int || view.level > seen) {
        await box?.put(ProfileScope.key(seenLevelKey), view.level);
      }
    } catch (_) {}
  }

  bool _inFlight = false;

  Future<void> refresh() async {
    if (!_hive.isLoggedIn || _inFlight) return;
    _inFlight = true;
    try {
      await apply(await _remote.me());
    } catch (e) {
      debugPrint('[progress] refresh failed: $e');
    } finally {
      _inFlight = false;
    }
  }

  /// Puts [id] on [slot], or takes the slot off with null. Throws on failure
  /// so the locker can say so.
  Future<void> equip(CosmeticSlot slot, String? id) async {
    await apply(await _remote.equip({slot.name: id}));
  }

  LevelUp? takeLevelUp() {
    final out = pendingLevelUp.value;
    pendingLevelUp.value = null;
    return out;
  }

  /// A profile switch: what is on screen belonged to someone else.
  void reload() {
    pendingLevelUp.value = null;
    state.value = _readCache();
    unawaited(refresh());
  }

  /// Sign-out: nothing of the account stays on the device.
  Future<void> reset() async {
    pendingLevelUp.value = null;
    state.value = null;
    try {
      await _box?.delete(ProfileScope.key(viewKey));
      await _box?.delete(ProfileScope.key(seenLevelKey));
    } catch (_) {}
  }
}
