import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/content/content_mode.dart';
import 'package:soplay/features/home/domain/home_content_kind.dart';

void main() {
  test('AniList discovery requires an anime source or explicit catalogue', () {
    expect(
      HomeContentKind.resolve(
        providerId: 'anikai',
        mode: ContentMode.video,
        category: 'anime',
      ),
      HomeContentKind.anime,
    );
    expect(
      HomeContentKind.resolve(providerId: 'unknown', mode: ContentMode.video),
      isNull,
    );
    expect(
      HomeContentKind.resolve(
        providerId: 'vidapi',
        mode: ContentMode.video,
        category: 'anime',
      ),
      HomeContentKind.movie,
    );
  });
  test('VidAPI and backend TMDB categories show movie services', () {
    for (final category in ['', 'tmdb']) {
      expect(
        HomeContentKind.resolve(
          providerId: 'vidapi',
          mode: ContentMode.video,
          category: category,
        ),
        HomeContentKind.movie,
      );
    }
    expect(
      HomeContentKind.resolve(
        providerId: 'other-provider',
        mode: ContentMode.video,
        category: ' TMDB ',
      ),
      HomeContentKind.movie,
    );
    expect(
      HomeContentKind.resolve(
        providerId: 'vidapi',
        mode: ContentMode.manga,
        category: 'tmdb',
      ),
      HomeContentKind.manga,
    );
    expect(
      HomeContentKind.resolve(
        providerId: 'vidapi',
        mode: ContentMode.novel,
        category: 'tmdb',
      ),
      HomeContentKind.novel,
    );
  });
  test('streaming services belong to movie catalogues and movie providers', () {
    expect(
      HomeContentKind.resolve(providerId: 'cat:tmdb', mode: ContentMode.video),
      HomeContentKind.movie,
    );
    expect(
      HomeContentKind.resolve(
        providerId: 'cs:films',
        mode: ContentMode.video,
        category: 'movies',
      ),
      HomeContentKind.movie,
    );
    expect(
      HomeContentKind.resolve(
        providerId: 'cat:anilist',
        mode: ContentMode.video,
        category: 'movies',
      ),
      HomeContentKind.anime,
    );
    expect(
      HomeContentKind.resolve(
        providerId: 'cs:anime',
        mode: ContentMode.video,
        category: 'anime',
      ),
      HomeContentKind.anime,
    );
  });
  test(
    'reader discovery targets its own AniList shelf even with stale video metadata',
    () {
      expect(
        HomeContentKind.resolve(
          providerId: 'my:reader',
          mode: ContentMode.manga,
          category: 'movies',
        )?.catalogueKind,
        'anilist-manga',
      );
      expect(
        HomeContentKind.resolve(
          providerId: 'my:reader',
          mode: ContentMode.novel,
          category: 'movies',
        )?.catalogueKind,
        'anilist-novel',
      );
    },
  );
}
