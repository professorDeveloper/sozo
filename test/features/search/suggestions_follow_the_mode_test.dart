// "Did you mean" has to suggest titles the selected source could actually have.
//
// These titles are not a passive strip: they are what the empty state and the
// weak-results banner offer, and tapping one re-runs the search on the SELECTED
// source. The service asked AniList's ANIME index and two hard-coded film
// providers whatever mode the app was in — so on a manga or novel source the
// one recovery affordance on an empty screen listed films and anime that source
// cannot carry, every one of which was guaranteed to come back empty. It also
// spent a round trip on a film provider to do it.
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/content/content_mode.dart';
import 'package:soplay/features/anilist/data/anilist_api.dart';
import 'package:soplay/features/anilist/domain/entities/anilist_entities.dart';
import 'package:soplay/features/search/data/datasources/search_data_source.dart';
import 'package:soplay/features/search/data/model/search_model.dart';
import 'package:soplay/features/search/data/title_suggestion_service.dart';

/// Records the `type` AniList was asked for, and answers with one title.
class _Anilist implements AnilistApi {
  final types = <String>[];

  @override
  Future<List<AnilistMedia>> searchMedia(
    String query, {
    int perPage = 20,
    String type = 'ANIME',
  }) async {
    types.add(type);
    return [AnilistMedia(id: 1, englishTitle: 'From $type')];
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Records every film-provider round trip.
class _Backend implements SearchDataSource {
  final asked = <String>[];

  @override
  Future<SearchModel> searchMovies(
    String query, {
    int page = 1,
    String? provider,
  }) async {
    asked.add(provider ?? '');
    return SearchModel(provider: provider ?? '', items: const [], page: 1, totalPages: 1);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  late _Anilist anilist;
  late _Backend backend;
  late TitleSuggestionService service;

  setUp(() {
    anilist = _Anilist();
    backend = _Backend();
    service = TitleSuggestionService(anilist: anilist, dataSource: backend);
  });

  test('video mode asks the anime index and the film providers', () async {
    await service.suggest('naruto', mode: ContentMode.video);

    expect(anilist.types, ['ANIME']);
    expect(backend.asked, isNotEmpty, reason: 'films belong in video mode');
  });

  test('manga mode asks the manga index and no film provider', () async {
    await service.suggest('berserk', mode: ContentMode.manga);

    expect(anilist.types, ['MANGA']);
    expect(
      backend.asked,
      isEmpty,
      reason:
          'a manga source cannot open a film, so the round trip was pure cost '
          'and the titles it brought back were pure noise',
    );
  });

  test('novel mode asks MANGA, because AniList has no NOVEL type', () async {
    // A light novel is MANGA with format NOVEL on AniList. Asking for a NOVEL
    // MediaType makes AniList reject the query outright, and the service
    // swallows that — so novel mode would have had no suggestions at all.
    await service.suggest('overlord', mode: ContentMode.novel);

    expect(anilist.types, ['MANGA']);
    expect(backend.asked, isEmpty);
  });

  test('the default is video, so existing callers are unchanged', () async {
    await service.suggest('naruto');
    expect(anilist.types, ['ANIME']);
  });

  group('the cache is keyed by mode', () {
    test('a manga lookup does not serve back the video answer', () async {
      // Same query, different mode. Keyed on the query alone, switching source
      // handed the manga screen the anime titles it had just been fixed not to
      // ask for.
      final video = await service.suggest('naruto', mode: ContentMode.video);
      final manga = await service.suggest('naruto', mode: ContentMode.manga);

      expect(video, isNot(manga));
      expect(anilist.types, ['ANIME', 'MANGA']);
    });

    test('but the same query in the same mode is only asked once', () async {
      // The cache still has to work: typing forwards and backspacing walks
      // back over prefixes that were just fetched.
      await service.suggest('naruto', mode: ContentMode.manga);
      await service.suggest('naruto', mode: ContentMode.manga);

      expect(anilist.types, ['MANGA']);
    });
  });
}
