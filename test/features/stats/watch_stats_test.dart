import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/features/stats/data/watch_stats_store.dart';

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('sozo_stats_');
    Hive.init(dir.path);
    await Hive.openBox(AppConstants.settingsBox);
  });

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  setUp(() async => WatchStatsStore().clear());

  String today() {
    final d = DateTime.now();
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  test('a fresh install has watched nothing', () {
    final s = WatchStatsStore();
    expect(s.totalSeconds, 0);
    expect(s.completed, 0);
    expect(s.byDay, isEmpty);
    expect(s.since, isNull, reason: 'counting has not started');
    expect(s.streakDays, 0);
  });

  test('time accumulates across ticks', () async {
    final s = WatchStatsStore();
    await s.record(seconds: 30, provider: 'hianimes');
    await s.record(seconds: 45, provider: 'hianimes');
    expect(s.totalSeconds, 75);
  });

  test('the start date is stamped once and then left alone', () async {
    // The screen has to be able to say what the total is the total OF. A date
    // that moved with every tick would say "since a moment ago", always.
    final s = WatchStatsStore();
    await s.record(seconds: 10, provider: 'p');
    final first = s.since;
    expect(first, isNotNull);
    await s.record(seconds: 10, provider: 'p');
    expect(s.since, first);
  });

  test('an implausible jump is refused', () async {
    // The player ticks every few seconds. Hours between two ticks is a clock
    // change or a resumed process, and counting it puts a number on the
    // screen nobody can explain.
    final s = WatchStatsStore();
    await s.record(seconds: 99999, provider: 'p');
    expect(s.totalSeconds, 0);
  });

  test('nothing and negative time are refused', () async {
    final s = WatchStatsStore();
    await s.record(seconds: 0, provider: 'p');
    await s.record(seconds: -60, provider: 'p');
    expect(s.totalSeconds, 0);
  });

  test('time is split by day and by provider', () async {
    final s = WatchStatsStore();
    await s.record(seconds: 60, provider: 'hianimes');
    await s.record(seconds: 90, provider: 'uzmovi');
    expect(s.byDay[today()], 150);
    expect(s.byProvider['hianimes'], 60);
    expect(s.byProvider['uzmovi'], 90);
  });

  test('a provider with no name does not create a blank row', () async {
    final s = WatchStatsStore();
    await s.record(seconds: 30, provider: '');
    expect(s.byProvider, isEmpty);
    expect(s.totalSeconds, 30, reason: 'the time still counts');
  });

  test('completions count one at a time', () async {
    final s = WatchStatsStore();
    await s.recordCompleted();
    await s.recordCompleted();
    expect(s.completed, 2);
  });

  group('streak', () {
    test('watching today is a streak of one', () async {
      final s = WatchStatsStore();
      await s.record(seconds: 60, provider: 'p');
      expect(s.streakDays, 1);
    });

    test('consecutive days add up', () async {
      final box = Hive.box(AppConstants.settingsBox);
      final now = DateTime.now();
      String key(int back) {
        final d = now.subtract(Duration(days: back));
        return '${d.year.toString().padLeft(4, '0')}-'
            '${d.month.toString().padLeft(2, '0')}-'
            '${d.day.toString().padLeft(2, '0')}';
      }

      await box.put(AppConstants.watchStatsKey, {
        'byDay': {key(0): 60, key(1): 60, key(2): 60},
      });
      expect(WatchStatsStore().streakDays, 3);
    });

    test('a gap ends the streak', () async {
      final box = Hive.box(AppConstants.settingsBox);
      final now = DateTime.now();
      String key(int back) {
        final d = now.subtract(Duration(days: back));
        return '${d.year.toString().padLeft(4, '0')}-'
            '${d.month.toString().padLeft(2, '0')}-'
            '${d.day.toString().padLeft(2, '0')}';
      }

      await box.put(AppConstants.watchStatsKey, {
        'byDay': {key(0): 60, key(2): 60, key(3): 60},
      });
      expect(WatchStatsStore().streakDays, 1);
    });

    test('yesterday still counts as alive', () async {
      // A streak that breaks at midnight punishes an evening watcher for not
      // having watched yet today.
      final box = Hive.box(AppConstants.settingsBox);
      final y = DateTime.now().subtract(const Duration(days: 1));
      final key = '${y.year.toString().padLeft(4, '0')}-'
          '${y.month.toString().padLeft(2, '0')}-'
          '${y.day.toString().padLeft(2, '0')}';
      await box.put(AppConstants.watchStatsKey, {'byDay': {key: 60}});
      expect(WatchStatsStore().streakDays, 1);
    });
  });

  test('a corrupt store reads as empty rather than throwing', () async {
    await Hive.box(AppConstants.settingsBox)
        .put(AppConstants.watchStatsKey, 'not a map');
    final s = WatchStatsStore();
    expect(s.totalSeconds, 0);
    expect(s.byDay, isEmpty);
    expect(s.streakDays, 0);
  });
}
