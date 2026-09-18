import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/streak/data/streak_remote_data_source.dart';
import 'package:soplay/features/streak/domain/entities/streak_state.dart';

class StreakService {
  StreakService({
    required StreakRemoteDataSource remote,
    required HiveService hive,
  })  : _remote = remote,
        _hive = hive {
    state.value = _readCache();
  }

  final StreakRemoteDataSource _remote;
  final HiveService _hive;

  final ValueNotifier<StreakState> state =
      ValueNotifier<StreakState>(StreakState.empty);
  final StreamController<int> milestones = StreamController<int>.broadcast();

  /// True while the first fetch of this session is in flight with nothing
  /// cached to show.
  ///
  /// Without it the screen renders [StreakState.empty] — "0 days" — which is
  /// not a blank slate but a claim, and the wrong one for anyone who has a
  /// streak running. A skeleton says "not known yet"; a zero says "you lost it".
  final ValueNotifier<bool> loading = ValueNotifier<bool>(false);

  String? _lastPingDay;
  bool _refreshInFlight = false;

  Box get _box => Hive.box(AppConstants.streakBox);

  StreakState _readCache() {
    try {
      final raw = _box.get(AppConstants.streakStateKey);
      if (raw is String && raw.isNotEmpty) {
        return StreakState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {}
    return StreakState.empty;
  }

  Future<void> _writeCache(StreakState s) async {
    try {
      await _box.put(AppConstants.streakStateKey, jsonEncode(s.toJson()));
    } catch (_) {}
  }

  int _tzOffset() => DateTime.now().timeZoneOffset.inMinutes;

  String _todayLocal() {
    final n = DateTime.now();
    final m = n.month.toString().padLeft(2, '0');
    final d = n.day.toString().padLeft(2, '0');
    return '${n.year}-$m-$d';
  }

  Future<void> refresh() async {
    if (!_hive.isLoggedIn || _refreshInFlight) return;
    _refreshInFlight = true;
    // Only claim to be loading when there is nothing to show. A refresh over
    // cached data should update in place, not blank the screen the user is
    // already reading.
    final blind = state.value.totalDays == 0 && state.value.current == 0;
    if (blind) loading.value = true;
    try {
      final fresh = await _remote.getMe(_tzOffset());
      state.value = fresh;
      await _writeCache(fresh);
    } catch (_) {
    } finally {
      _refreshInFlight = false;
      loading.value = false;
    }
  }

  Future<StreakPingResult?> ping() async {
    if (!_hive.isLoggedIn) return null;
    // Incognito reaches the server too, and here more than anywhere. A ping
    // writes "watched today" onto the account — the one record of a private
    // session the viewer cannot go and clear afterwards. Suppressing local
    // history while still telling the backend they were here would make the
    // promise false in exactly the place it matters.
    if (_hive.isIncognito) return null;
    final today = _todayLocal();
    if (_lastPingDay == today) return null;
    try {
      final result = await _remote.ping(_tzOffset());
      _lastPingDay = today;
      state.value = result.state;
      await _writeCache(result.state);
      if (result.newMilestone != null && !milestones.isClosed) {
        milestones.add(result.newMilestone!);
      }
      return result;
    } catch (_) {
      return null;
    }
  }

  void reset() {
    _lastPingDay = null;
    state.value = StreakState.empty;
    _box.delete(AppConstants.streakStateKey).catchError((_) {});
  }

  void dispose() {
    state.dispose();
    loading.dispose();
    milestones.close();
  }
}
