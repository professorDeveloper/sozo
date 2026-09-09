import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/detail/domain/playback/watch_progress.dart';

void main() {
  group('when a title counts as watched', () {
    test('at 85%, not at the very end', () {
      // Somebody who stops during the credits has watched the episode. A
      // tracker that only fires at 100% never fires for them.
      const total = Duration(minutes: 100);
      expect(WatchProgress.isWatched(const Duration(minutes: 84), total),
          isFalse);
      expect(WatchProgress.isWatched(const Duration(minutes: 85), total),
          isTrue);
    });

    test('an unknown duration never counts', () {
      // A live channel reports zero. "85% of nothing" would mark it watched
      // the instant it opened.
      expect(WatchProgress.isWatched(const Duration(minutes: 5), Duration.zero),
          isFalse);
      expect(
        WatchProgress.isWatched(
            const Duration(minutes: 5), const Duration(seconds: -1)),
        isFalse,
      );
    });

    test('the threshold is the one the player shipped with', () {
      expect(WatchProgress.watchedThreshold, 0.85);
    });
  });

  group('a tracker hears once', () {
    test('the second crossing of 85% reports nothing', () {
      // Seeking back and forward over the mark is ordinary viewing, and it
      // used to be the way to write the same episode to AniList repeatedly.
      final p = WatchProgress();
      expect(p.episodeToReport(isSerial: true, episodeNumber: 4), 4);
      expect(p.episodeToReport(isSerial: true, episodeNumber: 4), isNull);
      expect(p.hasReported(4), isTrue);
    });

    test('a different episode still reports', () {
      final p = WatchProgress();
      p.episodeToReport(isSerial: true, episodeNumber: 4);
      expect(p.episodeToReport(isSerial: true, episodeNumber: 5), 5);
    });

    test('a movie is episode 1 as far as a tracker is concerned', () {
      final p = WatchProgress();
      expect(p.episodeToReport(isSerial: false, episodeNumber: null), 1);
      expect(p.episodeToReport(isSerial: false, episodeNumber: null), isNull);
    });

    test('an episode numbered zero or less is never reported', () {
      // Several anime sources number specials 0 or -1. Reporting those writes
      // "episode 0 watched" onto somebody's list.
      final p = WatchProgress();
      expect(p.episodeToReport(isSerial: true, episodeNumber: 0), isNull);
      expect(p.episodeToReport(isSerial: true, episodeNumber: -1), isNull);
    });

    test('a serial with no episode number reports nothing', () {
      final p = WatchProgress();
      expect(p.episodeToReport(isSerial: true, episodeNumber: null), isNull);
    });
  });

  group('banking time', () {
    test('credits only the stretch since the last tick', () {
      final p = WatchProgress();
      expect(p.bank(const Duration(seconds: 5)), 5);
      expect(p.bank(const Duration(seconds: 10)), 5);
      expect(p.bank(const Duration(seconds: 30)), 20);
      expect(p.bankedSeconds, 30);
    });

    test('a clock that has not moved credits nothing', () {
      // What a tick during a pause looks like.
      final p = WatchProgress();
      p.bank(const Duration(seconds: 10));
      expect(p.bank(const Duration(seconds: 10)), 0);
      expect(p.bank(const Duration(seconds: 9)), 0,
          reason: 'and a clock going backwards never credits negative time');
      expect(p.bankedSeconds, 10);
    });

    test('sub-second ticks do not leak credit', () {
      final p = WatchProgress();
      expect(p.bank(const Duration(milliseconds: 900)), 0);
      expect(p.bank(const Duration(milliseconds: 1900)), 1);
    });
  });

  group('a new episode starts clean', () {
    test('banked time does not follow it', () {
      // Otherwise episode 2 is credited with episode 1's hour.
      final p = WatchProgress();
      p.bank(const Duration(minutes: 20));
      p.reset();
      expect(p.bankedSeconds, 0);
      expect(p.bank(const Duration(seconds: 5)), 5);
    });

    test('and neither does the reported set', () {
      // A season's specials share numbers with its episodes; carrying the set
      // would stop the real episode 1 ever reaching a tracker.
      final p = WatchProgress();
      p.episodeToReport(isSerial: true, episodeNumber: 1);
      p.reset();
      expect(p.episodeToReport(isSerial: true, episodeNumber: 1), 1);
    });
  });

  test('the domain layer stays free of Flutter', () {
    final source = File(
      'lib/features/detail/domain/playback/watch_progress.dart',
    ).readAsStringSync();
    expect(source.contains('package:flutter/'), isFalse);
    expect(source.contains('get_it'), isFalse);
  });
}
