import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/detail/domain/entities/episode_entity.dart';
import 'package:soplay/features/detail/domain/episode_seasons.dart';
import 'package:soplay/features/detail/domain/services/alternate_source_service.dart';

EpisodeEntity ep(int n, {int? season, String? label}) => EpisodeEntity(
  episode: n,
  label: label ?? 'Episode $n',
  mediaRef: 's${season}e$n',
  season: season,
);

void main() {
  test('Lupin: seasons that each start at 1 become one run, in order', () {
    // As the source lists it, and as the episode list used to sort it.
    final out = EpisodeSeasons.number([
      ep(1, season: 1, label: 'Chapter 1'),
      ep(2, season: 1, label: 'Chapter 2'),
      ep(1, season: 2, label: 'Chapter 6'),
      ep(2, season: 2, label: 'Chapter 7'),
      ep(1, season: 3, label: 'Chapter 1'),
    ]);
    expect([for (final e in out) e.episode], [1, 2, 3, 4, 5]);
    expect([for (final e in out) e.label], [
      'Chapter 1',
      'Chapter 2',
      'Chapter 6',
      'Chapter 7',
      'Chapter 1',
    ]);
    expect(out[2].season, 2);
    expect(out[2].numberInSeason, 1);
    expect(out[2].numberLabel, 'S2 E1');
    expect(out[2].mediaRef, 's2e1');
  });

  test('season 1 keeps its numbers, so old downloads and history line up', () {
    final out = EpisodeSeasons.number([
      ep(1, season: 2),
      ep(3, season: 1),
      ep(1, season: 1),
      ep(2, season: 1),
    ]);
    expect(out.take(3).map((e) => (e.season, e.episode)), [
      (1, 1),
      (1, 2),
      (1, 3),
    ]);
    expect(out.last.episode, 4);
  });

  test('specials go after the last season', () {
    final out = EpisodeSeasons.number([
      ep(1, season: 0),
      ep(1, season: 1),
      ep(1, season: 2),
    ]);
    expect([for (final e in out) e.season], [1, 2, 0]);
    expect(EpisodeSeasons.of(out).map((s) => s.$1), [1, 2, 0]);
  });

  test('seasons that already number on keep their numbers', () {
    final out = EpisodeSeasons.number([
      ep(13, season: 2),
      ep(1, season: 1),
      ep(12, season: 1),
    ]);
    expect([for (final e in out) e.episode], [1, 12, 13]);
    expect(out.last.numberLabel, 'S2 E13');
  });

  test('a single season is left as it was, its season dropped', () {
    final out = EpisodeSeasons.number([ep(1, season: 1), ep(2, season: 1)]);
    expect([for (final e in out) e.episode], [1, 2]);
    expect(out.every((e) => e.season == null), isTrue);
    expect(out.first.numberLabel, '1');
    final plain = [ep(1), ep(2)];
    expect(identical(EpisodeSeasons.number(plain), plain), isTrue);
  });

  group('switching source keeps the season', () {
    final seasoned = EpisodeSeasons.number([
      for (var s = 1; s <= 2; s++)
        for (var n = 1; n <= 10; n++) ep(n, season: s),
    ]);

    test('S2E1 is S2E1 on a source that lists seasons', () {
      final i = indexOfSeasonEpisode(seasoned, (season: 2, number: 1));
      expect(seasoned[i].mediaRef, 's2e1');
    });

    test('a source with no seasons is matched on a first season only', () {
      final flat = [for (var n = 1; n <= 10; n++) ep(n)];
      expect(indexOfSeasonEpisode(flat, (season: 1, number: 4)), 3);
      expect(indexOfSeasonEpisode(flat, (season: 2, number: 4)), -1);
    });
  });
}
