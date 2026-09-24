import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/content/content_mode.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/home/domain/entities/movie.dart';
import 'package:soplay/features/home/domain/entities/view_all_paging_entity.dart';
import 'package:soplay/features/onboarding/data/picked_for_you.dart';
import 'package:soplay/features/onboarding/domain/taste_profile.dart';

MovieEntity _movie(String id) => MovieEntity(
  externalId: id,
  title: id,
  description: '',
  slug: id,
  url: 'https://anilist.co/anime/$id',
  provider: 'cat:anilist',
  thumbnail: null,
  year: null,
  rating: null,
  qualities: null,
  category: 'anime',
);

void main() {
  const taste = TasteProfile(
    kinds: [TasteKind.anime, TasteKind.movies],
    genres: [
      TasteGenre(slug: 'action', label: 'Action', catalogues: {'anilist'}),
      TasteGenre(slug: 'war', label: 'War', catalogues: {'tmdb'}),
      TasteGenre(slug: 'mecha', label: 'Mecha', catalogues: {'anilist'}),
    ],
  );

  test('rotates through every target, one step a day', () {
    final day = DateTime(2026, 9, 24);
    final today = rotateForDay([1, 2, 3], day);
    final tomorrow = rotateForDay([1, 2, 3], day.add(const Duration(days: 1)));
    expect(today.toSet(), {1, 2, 3});
    expect(tomorrow.first, today[1]);
  });

  test('moves on past an empty genre and caches what it found', () async {
    final asked = <String>[];
    final source = PickedForYouSource(
      clock: () => DateTime(2026, 9, 24),
      load: (slug) async {
        asked.add(slug);
        final items = slug == 'anilist:mecha' ? [_movie('1')] : <MovieEntity>[];
        return Success(
          ViewAllPagingEntity(
            page: 1,
            totalPages: 1,
            provider: '',
            items: items,
          ),
        );
      },
    );
    expect(source.peek(taste, ContentMode.video), isNull);
    final got = await source.fetch(taste, ContentMode.video);
    expect(got?.slug, 'anilist:mecha');
    expect(got?.items.single.externalId, '1');

    final calls = asked.length;
    expect(source.peek(taste, ContentMode.video)?.slug, 'anilist:mecha');
    await source.fetch(taste, ContentMode.video);
    expect(asked.length, calls);
  });

  test('draws nothing for a mode with no picks', () async {
    final source = PickedForYouSource(
      load: (_) async => Failure(Exception('not asked')),
    );
    expect(await source.fetch(taste, ContentMode.novel), isNull);
  });

  test('on a catalogue home only that catalogue is browsed', () async {
    final asked = <String>[];
    final source = PickedForYouSource(
      clock: () => DateTime(2026, 9, 24),
      load: (slug) async {
        asked.add(slug);
        return Success(
          ViewAllPagingEntity(
            page: 1,
            totalPages: 1,
            provider: '',
            items: [_movie(slug)],
          ),
        );
      },
    );
    final got = await source.fetch(taste, ContentMode.video, catalogue: 'tmdb');
    expect(got?.slug, 'tmdb:war');
    expect(asked, ['tmdb:war']);
    expect(
      source
          .targetsFor(taste, ContentMode.video, catalogue: 'anilist')
          .map((t) => t.genre.slug),
      unorderedEquals(['action', 'mecha']),
    );
  });
}
