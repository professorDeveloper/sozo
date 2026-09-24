import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/storage/profile_scope.dart';
import 'package:soplay/features/achievements/data/achievements_remote_data_source.dart';
import 'package:soplay/features/achievements/domain/achievements.dart';

/// The active profile's achievements, and the ones waiting to be celebrated.
///
/// Badges are earned on the server — by a history sync or a streak ping —
/// and those answers say what they earned. They land in [pending], and the
/// celebration host shows them when nothing is playing.
class AchievementsService {
  AchievementsService({
    required AchievementsRemoteDataSource remote,
    required HiveService hive,
  }) : _remote = remote,
       _hive = hive {
    state.value = _readCache();
  }

  final AchievementsRemoteDataSource _remote;
  final HiveService _hive;

  /// Null until something is known; the cache fills it at once on launch.
  final ValueNotifier<AchievementsView?> state = ValueNotifier(null);

  /// Earned and not yet shown.
  final ValueNotifier<List<AchievementUnlock>> pending = ValueNotifier(
    const [],
  );

  static const String _cacheKey = 'achievements_view';

  Box? get _box {
    try {
      return Hive.box(AppConstants.settingsBox);
    } catch (_) {
      return null;
    }
  }

  AchievementsView? _readCache() {
    try {
      final raw = _box?.get(ProfileScope.key(_cacheKey));
      if (raw is String && raw.isNotEmpty) {
        return AchievementsView.fromJson(
          (jsonDecode(raw) as Map).cast<String, dynamic>(),
        );
      }
    } catch (_) {}
    return null;
  }

  Future<void> _write(Map<String, dynamic> raw) async {
    state.value = AchievementsView.fromJson(raw);
    try {
      await _box?.put(ProfileScope.key(_cacheKey), jsonEncode(raw));
    } catch (_) {}
  }

  bool _inFlight = false;

  Future<void> refresh() async {
    if (!_hive.isLoggedIn || _inFlight) return;
    _inFlight = true;
    try {
      await _write(await _remote.me());
    } catch (e) {
      debugPrint('[achievements] refresh failed: $e');
    } finally {
      _inFlight = false;
    }
  }

  /// Picks the badges shown beside the profile's name. Throws on failure so
  /// the picker can say so.
  Future<void> setShowcase(List<String> ids) async {
    await _write(await _remote.setShowcase(ids));
  }

  /// Queues what a sync or ping earned and brings the numbers up to date.
  void celebrate(List<AchievementUnlock> unlocks) {
    final known = unlocks.where((u) => u.id.isNotEmpty && u.tier > 0).toList();
    if (known.isEmpty) return;
    final seen = {for (final u in pending.value) '${u.id}:${u.tier}'};
    pending.value = [
      ...pending.value,
      for (final u in known)
        if (seen.add('${u.id}:${u.tier}')) u,
    ];
    unawaited(refresh());
  }

  /// Everything waiting, cleared — for the host that is about to show it.
  List<AchievementUnlock> takePending() {
    final out = pending.value;
    pending.value = const [];
    return out;
  }

  /// A profile switch or sign-out: what is on screen belonged to someone else.
  void reload() {
    pending.value = const [];
    state.value = _readCache();
    unawaited(refresh());
  }
}
