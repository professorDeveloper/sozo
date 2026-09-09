import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/detail/domain/entities/episode_entity.dart';
import 'package:soplay/features/detail/domain/playback/episode_window.dart';

List<EpisodeEntity> eps(int n, {int from = 1}) => [
      for (var i = 0; i < n; i++)
        EpisodeEntity(
          episode: from + i,
          label: 'Episode ${from + i}',
          mediaRef: 'ref-${from + i}',
        ),
    ];

EpisodeWindow window({
  int loaded = 20,
  int windowStart = 0,
  int index = 0,
  int total = 100,
  bool isSerial = true,
}) =>
    EpisodeWindow(
      episodes: eps(loaded, from: windowStart + 1),
      windowStart: windowStart,
      index: index,
      total: total,
      isSerial: isSerial,
    );

void main() {
  group('the two indices', () {
    test('absolute is the position in the series, not in the window', () {
      // The whole reason this type exists. A window loaded from episode 81
      // playing its first entry is at absolute 80, not 0.
      expect(window(windowStart: 80, index: 0).absoluteIndex, 80);
    });

    test('the current episode is read window-relative', () {
      final w = window(loaded: 20, windowStart: 80, index: 3);
      expect(w.current?.episode, 84);
    });

    test('an index outside the window names no episode rather than throwing',
        () {
      expect(window(loaded: 5, index: 9).current, isNull);
      expect(window(loaded: 5, index: -1).current, isNull);
    });

    test('a movie has no current episode', () {
      expect(const EpisodeWindow.movie().current, isNull);
    });
  });

  group('hasNext — the greyed-out Next bug', () {
    test('asks whether the episode EXISTS, not whether it is loaded', () {
      // A 100-episode series with a 20-episode window, sitting on the last
      // LOADED one. The old test compared against episodes.length and greyed
      // Next out here, ending a 1176-episode run at 100.
      final w = window(loaded: 20, windowStart: 80, index: 19, total: 1176);
      expect(w.contains(w.index + 1), isFalse, reason: 'not loaded');
      expect(w.hasNext, isTrue, reason: 'but it exists');
    });

    test('false only at the genuine end of the series', () {
      expect(window(loaded: 20, windowStart: 80, index: 19, total: 100).hasNext,
          isFalse);
    });

    test('a movie never has a next or a previous', () {
      const m = EpisodeWindow.movie();
      expect(m.hasNext, isFalse);
      expect(m.hasPrev, isFalse);
    });

    test('prev is false at the start of the series, not of the window', () {
      expect(window(windowStart: 0, index: 0).hasPrev, isFalse);
      expect(window(windowStart: 80, index: 0).hasPrev, isTrue);
    });
  });

  group('paging', () {
    test('finds the 1-based page holding an absolute index', () {
      final w = window(total: 500);
      expect(w.pageFor(0, 100), 1);
      expect(w.pageFor(99, 100), 1);
      expect(w.pageFor(100, 100), 2);
      expect(w.pageFor(455, 100), 5);
    });

    test('refuses to page for an index outside the series', () {
      // The caller treats null as "do not fetch" — which is what stops a
      // request for episode 501 of a 500-episode show.
      final w = window(total: 500);
      expect(w.pageFor(500, 100), isNull);
      expect(w.pageFor(-1, 100), isNull);
    });

    test('refuses when the provider gave no page size', () {
      expect(window(total: 500).pageFor(10, 0), isNull);
    });

    test('a fetched page replaces the window and rebases the index', () {
      final w = window(loaded: 100, windowStart: 0, index: 4, total: 500);
      final next = w.withPage(eps(100, from: 401), page: 5, pageSize: 100,
          absoluteIndex: 455);
      expect(next.windowStart, 400);
      expect(next.index, 55, reason: '455 - 400');
      expect(next.absoluteIndex, 455);
      expect(next.current?.episode, 456);
      expect(next.total, 500, reason: 'the series did not change size');
    });
  });

  group('immutability', () {
    test('at() moves the playhead and leaves the window alone', () {
      final w = window(loaded: 20, windowStart: 80, index: 3);
      final next = w.at(7);
      expect(next.index, 7);
      expect(next.windowStart, 80);
      expect(w.index, 3, reason: 'the original is untouched');
    });

    test('withEpisodes replaces the list and keeps the position', () {
      final w = window(loaded: 20, windowStart: 80, index: 3);
      final next = w.withEpisodes(eps(20, from: 81));
      expect(next.index, 3);
      expect(next.windowStart, 80);
    });

    test('equality treats a new list as a real change', () {
      // By identity on purpose: the session owns every allocation, so a fresh
      // list always means something happened. A deep compare would walk a
      // hundred episodes on every rebuild.
      final shared = eps(3);
      final a = EpisodeWindow(
          episodes: shared, windowStart: 0, index: 0, total: 3, isSerial: true);
      final b = EpisodeWindow(
          episodes: shared, windowStart: 0, index: 0, total: 3, isSerial: true);
      expect(a, equals(b));
      expect(a, isNot(equals(a.withEpisodes(eps(3)))));
      expect(a, isNot(equals(a.at(1))));
    });
  });

  test('the domain layer stays free of Flutter', () {
    final source = File(
      'lib/features/detail/domain/playback/episode_window.dart',
    ).readAsStringSync();
    expect(source.contains('package:flutter/'), isFalse);
    expect(source.contains('get_it'), isFalse);
  });
}
