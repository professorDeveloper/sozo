// XP and levels: the curve the server uses, what a progress answer parses
// to, and how watch time is batched up to the server.
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/progress/data/progress_remote_data_source.dart';
import 'package:soplay/features/progress/data/progress_service.dart';
import 'package:soplay/features/progress/data/watch_time_uploader.dart';
import 'package:soplay/features/progress/domain/progress.dart';
import 'package:soplay/features/stats/data/watch_stats_store.dart';

class _Hive implements HiveService {
  @override
  bool get isLoggedIn => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Remote extends ProgressRemoteDataSource {
  _Remote() : super(dio: Dio());

  final List<Map<String, Object>> sent = [];
  bool offline = false;
  int xp = 0;

  @override
  Future<Map<String, dynamic>> me() async => {'xp': xp};

  @override
  Future<Map<String, dynamic>> watchTime({
    required String day,
    required int seconds,
    required String deviceId,
  }) async {
    if (offline) throw DioException(requestOptions: RequestOptions());
    sent.add({'day': day, 'seconds': seconds, 'deviceId': deviceId});
    xp += seconds ~/ 60;
    return {
      'progress': {'xp': xp},
    };
  }
}

void main() {
  group('the level curve', () {
    test('level n needs 100·n^1.5 XP, as on the server', () {
      expect(xpForLevel(0), 0);
      expect(xpForLevel(1), 100);
      expect(xpForLevel(2), 282);
      expect(xpForLevel(3), 519);
      expect(xpForLevel(10), 3162);
      expect(levelFor(0), 0);
      expect(levelFor(99), 0);
      expect(levelFor(100), 1);
      expect(levelFor(281), 1);
      expect(levelFor(282), 2);
      for (var n = 1; n < 200; n++) {
        expect(levelFor(xpForLevel(n)), n, reason: 'at level $n');
        expect(levelFor(xpForLevel(n) - 1), n - 1, reason: 'short of $n');
      }
    });

    test('the ring shows the way through the current level', () {
      final p = LevelProgress.of(400);
      expect(p.level, 2);
      expect(p.floor, 282);
      expect(p.next, 519);
      expect(p.intoLevel, 118);
      expect(p.toNext, 119);
      expect(p.fraction, closeTo(118 / 237, 1e-9));
      expect(LevelProgress.of(0).fraction, 0);
      expect(LevelProgress.of(-5).level, 0);
    });
  });

  group('parsing', () {
    test('no level means no decoration', () {
      expect(UserDecoration.fromJson({'username': 'a'}), isNull);
      expect(UserDecoration.fromJson({'level': null}), isNull);
      final d = UserDecoration.fromJson({
        'level': 7,
        'frame': 'gold',
        'title': '',
        'nameColor': 'mint',
      })!;
      expect(d.level, 7);
      expect(d.frame, 'gold');
      expect(d.title, isNull);
      expect(d.nameColor, 'mint');
    });

    test('a progress answer parses its catalogue and gains', () {
      final v = ProgressView.fromJson({
        'xp': 300,
        'equipped': {'frame': 'bronze', 'title': null, 'nameColor': null},
        'today': {'watchXp': 40, 'watchCap': 300},
        'recent': [
          {'reason': 'watch', 'xp': 40, 'at': '2026-11-07T10:00:00Z'},
        ],
        'catalog': {
          'frame': [
            {
              'id': 'bronze',
              'unlock': {'level': 2},
              'unlocked': true,
            },
            {
              'id': 'flame',
              'unlock': {'badge': 'streak', 'tier': 2},
              'unlocked': false,
            },
          ],
          'title': [
            {
              'id': 'newcomer',
              'unlock': {'level': 0},
              'unlocked': true,
            },
          ],
          'future_slot': [
            {'id': 'x'},
          ],
        },
      });
      expect(v.level, 2);
      expect(v.decoration.frame, 'bronze');
      expect(v.slot(CosmeticSlot.frame).map((c) => c.id), ['bronze', 'flame']);
      final flame = v.slot(CosmeticSlot.frame).last;
      expect(flame.level, isNull);
      expect(flame.badge, 'streak');
      expect(flame.tier, 2);
      expect(v.catalog.length, 3);
      expect(v.recent.single.xp, 40);
      expect(v.watchXpToday, 40);
    });

    test('a level-up is only what rose past the level last seen', () {
      final v = ProgressView.fromJson({
        'xp': 600,
        'catalog': {
          'frame': [
            {
              'id': 'bronze',
              'unlock': {'level': 2},
            },
            {
              'id': 'silver',
              'unlock': {'level': 5},
            },
          ],
        },
      });
      expect(LevelUp.between(null, v), isNull, reason: 'first sight');
      expect(LevelUp.between(3, v), isNull);
      final up = LevelUp.between(1, v)!;
      expect(up.from, 1);
      expect(up.to, 3);
      expect(up.unlocked.map((c) => c.id), ['bronze']);
    });
  });

  group('batching', () {
    final now = DateTime(2026, 11, 7, 21);

    test('only days that grew are due, today and yesterday only', () {
      final due = WatchTimeBatch.due(
        byDay: {'2026-11-05': 900, '2026-11-06': 600, '2026-11-07': 300},
        sent: {'2026-11-06': 600, '2026-11-07': 120},
        now: now,
      );
      expect(due.map((e) => '${e.key}=${e.value}'), ['2026-11-07=300']);
    });

    test('nothing is due once everything was sent', () {
      expect(
        WatchTimeBatch.due(
          byDay: {'2026-11-07': 300},
          sent: {'2026-11-07': 300},
          now: now,
        ),
        isEmpty,
      );
    });

    test('old days are forgotten', () {
      final kept = WatchTimeBatch.pruned({
        '2026-10-01': 1,
        '2026-10-31': 2,
        '2026-11-06': 3,
      }, now);
      expect(kept.keys, ['2026-10-31', '2026-11-06']);
    });

    test('a tick sends at most every ten minutes', () {
      expect(WatchTimeBatch.shouldFlush(null, now), isTrue);
      expect(
        WatchTimeBatch.shouldFlush(
          now.subtract(const Duration(minutes: 9)),
          now,
        ),
        isFalse,
      );
      expect(
        WatchTimeBatch.shouldFlush(
          now.subtract(const Duration(minutes: 10)),
          now,
        ),
        isTrue,
      );
    });
  });

  group('the uploader', () {
    late Directory dir;

    setUpAll(() async {
      dir = await Directory.systemTemp.createTemp('sozo_progress_');
      Hive.init(dir.path);
      await Hive.openBox(AppConstants.settingsBox);
    });

    tearDownAll(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });

    setUp(() async {
      await WatchStatsStore().clear();
      await Hive.box(AppConstants.settingsBox).clear();
    });

    test('sends the day total, survives being offline, and never twice', () async {
      final remote = _Remote();
      final progress = ProgressService(remote: remote, hive: _Hive());
      final uploader = WatchTimeUploader(
        remote: remote,
        hive: _Hive(),
        progress: progress,
      );
      final stats = WatchStatsStore();
      final today = WatchTimeBatch.dayKey(DateTime.now());

      await stats.record(seconds: 300, provider: 'p');
      remote.offline = true;
      await uploader.flush();
      expect(remote.sent, isEmpty);

      await stats.record(seconds: 120, provider: 'p');
      remote.offline = false;
      await uploader.flush();
      expect(remote.sent.single['day'], today);
      expect(remote.sent.single['seconds'], 420);
      expect(progress.state.value?.xp, 7);

      await uploader.flush();
      expect(remote.sent.length, 1, reason: 'nothing new to send');

      await stats.record(seconds: 60, provider: 'p');
      await uploader.flush();
      expect(remote.sent.last['seconds'], 480);
      expect(remote.sent.last['deviceId'], remote.sent.first['deviceId']);
    });

    test('a level gained is waiting for the celebration', () async {
      final remote = _Remote();
      final progress = ProgressService(remote: remote, hive: _Hive());
      remote.xp = 50;
      await progress.refresh();
      expect(progress.pendingLevelUp.value, isNull);
      remote.xp = 300;
      await progress.refresh();
      expect(progress.pendingLevelUp.value?.to, 2);
      expect(progress.takeLevelUp()?.from, 0);
      expect(progress.pendingLevelUp.value, isNull);
    });
  });
}
