import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/detail/domain/entities/episode_entity.dart';
import 'package:soplay/features/detail/domain/entities/player_args.dart';

/// The episodes screen loads one page at a time. The player used to be handed
/// that page and treat it as the series, so a 1176-episode run ended at 100
/// with Next greyed out and no way forward from inside the player.
void main() {
  List<EpisodeEntity> page(int from, int count) => List.generate(
    count,
    (i) => EpisodeEntity(episode: from + i, label: '', mediaRef: 'u${from + i}'),
  );

  PlayerArgs args({
    int windowStart = 0,
    int total = 0,
    int loaded = 100,
  }) => PlayerArgs(
    title: 'One Piece',
    provider: 'x',
    headers: const {},
    episodes: page(windowStart + 1, loaded),
    windowStart: windowStart,
    totalEpisodes: total,
    pageSize: 100,
  );

  group('effectiveTotal', () {
    test('is the series when the caller knows it', () {
      expect(args(total: 1176).effectiveTotal, 1176);
    });

    test('falls back to the loaded list', () {
      // A caller that does not page must behave exactly as before.
      expect(args().effectiveTotal, 100);
    });

    test('a nonsense total does not shrink the run below what is loaded', () {
      expect(args(total: 0, loaded: 12).effectiveTotal, 12);
    });
  });

  group('isWindowed', () {
    test('true when the page is part of a longer run', () {
      expect(args(total: 1176).isWindowed, isTrue);
    });

    test('false when the whole series is loaded', () {
      expect(args(total: 100, loaded: 100).isWindowed, isFalse);
      expect(args(loaded: 12).isWindowed, isFalse);
    });

    test('false for a film', () {
      final movie = PlayerArgs(
        title: 'Dune',
        provider: 'x',
        headers: const {},
      );
      expect(movie.isWindowed, isFalse);
      expect(movie.effectiveTotal, 0);
    });
  });

  group('the position that decides Next', () {
    // The player computes windowStart + episodeIndex. These pin the arithmetic
    // that used to be `episodeIndex + 1 < episodes.length`.
    int absolute(PlayerArgs a, int episodeIndex) =>
        a.windowStart + episodeIndex;

    test('the last row of a middle page is not the end of the series', () {
      final a = args(windowStart: 100, total: 1176);
      expect(absolute(a, 99), 199);
      expect(absolute(a, 99) + 1 < a.effectiveTotal, isTrue);
    });

    test('the last row of the last page IS the end', () {
      final a = args(windowStart: 1100, total: 1176, loaded: 76);
      expect(absolute(a, 75), 1175);
      expect(absolute(a, 75) + 1 < a.effectiveTotal, isFalse);
    });

    test('the first row of a middle page has something before it', () {
      final a = args(windowStart: 100, total: 1176);
      expect(absolute(a, 0) > 0, isTrue);
    });

    test('the very first episode has nothing before it', () {
      final a = args(total: 1176);
      expect(absolute(a, 0) > 0, isFalse);
    });
  });
}
