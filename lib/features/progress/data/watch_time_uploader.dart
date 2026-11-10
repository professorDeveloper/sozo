import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/storage/profile_scope.dart';
import 'package:soplay/features/progress/data/progress_remote_data_source.dart';
import 'package:soplay/features/progress/data/progress_service.dart';
import 'package:soplay/features/stats/data/watch_stats_store.dart';

/// Which days' watch time still has to reach the server.
///
/// The server is sent each day's running total, and it credits the rise since
/// the last total it saw. So what is pending is just the gap between
/// [WatchStatsStore.byDay] and what was last sent — it survives being offline
/// with nothing extra to keep, and a retry after a lost answer adds nothing.
class WatchTimeBatch {
  WatchTimeBatch._();

  static const Duration interval = Duration(minutes: 10);

  /// Today and yesterday: the server takes nothing older.
  static List<MapEntry<String, int>> due({
    required Map<String, int> byDay,
    required Map<String, int> sent,
    required DateTime now,
  }) {
    final days = [dayKey(now.subtract(const Duration(days: 1))), dayKey(now)];
    return [
      for (final d in days)
        if ((byDay[d] ?? 0) > (sent[d] ?? 0)) MapEntry(d, byDay[d]!),
    ];
  }

  /// [sent] without the days that can no longer be sent.
  static Map<String, int> pruned(Map<String, int> sent, DateTime now) {
    final oldest = dayKey(now.subtract(const Duration(days: 7)));
    return {
      for (final e in sent.entries)
        if (e.key.compareTo(oldest) >= 0) e.key: e.value,
    };
  }

  /// Whether a tick while watching should send now.
  static bool shouldFlush(DateTime? last, DateTime now) =>
      last == null || now.difference(last) >= interval;

  static String dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// Sends watch time for XP: every ten minutes while something plays, and when
/// the app goes to the background.
class WatchTimeUploader with WidgetsBindingObserver {
  WatchTimeUploader({
    required ProgressRemoteDataSource remote,
    required HiveService hive,
    required ProgressService progress,
    WatchStatsStore? stats,
    DateTime Function()? clock,
  }) : _remote = remote,
       _hive = hive,
       _progress = progress,
       _stats = stats ?? WatchStatsStore(),
       _clock = clock ?? DateTime.now;

  final ProgressRemoteDataSource _remote;
  final HiveService _hive;
  final ProgressService _progress;
  final WatchStatsStore _stats;
  final DateTime Function() _clock;

  static const String sentKey = 'progress_watch_sent';
  static const String _deviceKey = 'progress_device_id';

  DateTime? _lastFlush;
  Future<void>? _running;

  Box? get _box {
    try {
      return Hive.box(AppConstants.settingsBox);
    } catch (_) {
      return null;
    }
  }

  String get _deviceId {
    final box = _box;
    final had = box?.get(_deviceKey);
    if (had is String && had.isNotEmpty) return had;
    final rnd = math.Random.secure();
    final id = List.generate(
      16,
      (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    unawaited(box?.put(_deviceKey, id));
    return id;
  }

  Map<String, int> _readSent() {
    final raw = _box?.get(ProfileScope.key(sentKey));
    if (raw is! Map) return {};
    return {
      for (final e in raw.entries)
        if (e.value is num) e.key.toString(): (e.value as num).toInt(),
    };
  }

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _lastFlush = _clock();
    unawaited(flush());
    unawaited(_progress.refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        unawaited(flush());
      case AppLifecycleState.resumed:
        unawaited(_progress.refresh());
      default:
        break;
    }
  }

  /// A tick of watching was just recorded.
  void onWatched() {
    if (WatchTimeBatch.shouldFlush(_lastFlush, _clock())) unawaited(flush());
  }

  /// Sends whatever is pending. A failure leaves it pending for next time.
  Future<void> flush() => _running ??= _flush().whenComplete(() {
    _running = null;
  });

  Future<void> _flush() async {
    _lastFlush = _clock();
    if (!_hive.isLoggedIn) return;
    final now = _clock();
    var sent = WatchTimeBatch.pruned(_readSent(), now);
    final due = WatchTimeBatch.due(
      byDay: _stats.byDay,
      sent: sent,
      now: now,
    );
    if (due.isEmpty) return;
    final device = _deviceId;
    final key = ProfileScope.key(sentKey);
    for (final entry in due) {
      try {
        final res = await _remote.watchTime(
          day: entry.key,
          seconds: entry.value,
          deviceId: device,
        );
        sent = {...sent, entry.key: entry.value};
        await _box?.put(key, sent);
        final progress = res['progress'];
        if (progress is Map) {
          await _progress.apply(progress.cast<String, dynamic>());
        }
      } on DioException catch (e) {
        // A day the server will never take would block every day after it.
        if (e.response?.statusCode == 400) {
          sent = {...sent, entry.key: entry.value};
          await _box?.put(key, sent);
          continue;
        }
        debugPrint('[progress] watch-time upload failed: $e');
        return;
      } catch (e) {
        debugPrint('[progress] watch-time upload failed: $e');
        return;
      }
    }
  }

  /// Sign-out: the totals this was measured against are gone too.
  Future<void> reset() async {
    try {
      await _box?.delete(ProfileScope.key(sentKey));
    } catch (_) {}
  }
}
