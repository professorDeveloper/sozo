import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/content/content_mode.dart';
import 'package:soplay/features/home/domain/home_content_kind.dart';

void main() {
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
        ).catalogueKind,
        'anilist-manga',
      );
      expect(
        HomeContentKind.resolve(
          providerId: 'my:reader',
          mode: ContentMode.novel,
          category: 'movies',
        ).catalogueKind,
        'anilist-novel',
      );
    },
  );
}
