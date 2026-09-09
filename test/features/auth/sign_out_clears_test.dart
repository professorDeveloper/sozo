import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/features/stats/data/watch_stats_store.dart';

/// Signing out has to take the account's data off the device with it.
///
/// The failure this guards is not a stale screen: somebody signs out, hands
/// the phone over, and the next person opens the app to another person's
/// watch history, saved titles, streak and viewing totals.
void main() {
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('sozo_signout_');
    Hive.init(dir.path);
    await Hive.openBox(AppConstants.settingsBox);
  });

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('watch statistics do not survive a sign-out', () async {
    // Statistics are the one part with no server copy, so nothing else would
    // ever remove them — and a watch-time total is as personal as the history
    // it was counted from.
    final stats = WatchStatsStore();
    await stats.record(seconds: 600, provider: 'hianimes');
    await stats.recordCompleted();
    expect(stats.totalSeconds, 600);
    expect(stats.completed, 1);

    await stats.clear();

    expect(stats.totalSeconds, 0);
    expect(stats.completed, 0);
    expect(stats.byDay, isEmpty);
    expect(stats.byProvider, isEmpty);
    expect(stats.since, isNull, reason: 'counting starts over, honestly');
  });

  test('clearing twice is not an error', () async {
    // Sign-out can be retried after a failed network call, and the second pass
    // must not throw on state the first one already removed.
    final stats = WatchStatsStore();
    await stats.clear();
    await expectLater(stats.clear(), completes);
  });

  test('a cleared store still records afterwards', () async {
    // Signing back in and watching something has to start counting again
    // rather than silently doing nothing.
    final stats = WatchStatsStore();
    await stats.clear();
    await stats.record(seconds: 30, provider: 'p');
    expect(stats.totalSeconds, 30);
    expect(stats.since, isNotNull);
  });
}
