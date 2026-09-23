// A title opened with no provider means "the current source". When that is a
// catalogue, the link itself has to say which one — otherwise the detail page
// asks the provider route for a source called `cat:anilist`, which does not
// exist, and shows "Unknown provider".
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/content/catalogue.dart';

void main() {
  test('an AniList anime link is the anime catalogue', () {
    expect(
      Catalogue.forUrl('https://anilist.co/anime/5114'),
      Catalogue.anilist,
    );
  });

  test('a manga link is manga, or novels when novels are current', () {
    expect(
      Catalogue.forUrl('https://anilist.co/manga/30013'),
      Catalogue.anilistManga,
    );
    expect(
      Catalogue.forUrl(
        'https://anilist.co/manga/30013',
        current: Catalogue.anilistNovel.id,
      ),
      Catalogue.anilistNovel,
    );
  });

  test('a TMDB link is TMDB', () {
    expect(
      Catalogue.forUrl('https://www.themoviedb.org/movie/603'),
      Catalogue.tmdb,
    );
  });

  test("a source's own link is left to the source", () {
    expect(Catalogue.forUrl('https://animeav1.com/media/one-piece'), isNull);
    expect(Catalogue.forUrl('not a url'), isNull);
    expect(Catalogue.forUrl('https://anilist.co/'), isNull);
  });
}
