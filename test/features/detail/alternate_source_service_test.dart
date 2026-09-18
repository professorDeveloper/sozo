import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/matching/title_match.dart';
import 'package:soplay/features/detail/domain/services/alternate_source_service.dart';
import 'package:soplay/features/detail/domain/repositories/detail_repository.dart';
import 'package:soplay/features/detail/domain/usecases/get_episodes_usecase.dart';
import 'package:soplay/features/home/domain/entities/movie.dart';
import 'package:soplay/features/profile/domain/entities/provider_entity.dart';
import 'package:soplay/features/profile/domain/repositories/provider_repository.dart';
import 'package:soplay/features/profile/domain/usecases/get_providers_usecase.dart';
import 'package:soplay/features/search/domain/entities/cross_search_result.dart';
import 'package:soplay/features/search/domain/services/cross_search_engine.dart';

/// Records what the engine was asked, and answers with a fixed set of rows.
///
/// The real engine reaches WebViews, a Dio client and the Mangayomi bridge, so
/// the service takes [SearchFanOut] rather than the engine itself — this is the
/// whole reason it can be tested at all.
class _FanOut implements SearchFanOut {
  _FanOut({this.rows = const []});

  final List<MovieEntity> rows;
  final List<(String, String, int)> legs = [];

  @override
  List<ProviderRef> planLegs(List<ProviderRef> set, {int limit = 60}) => set;

  @override
  Stream<ProviderSearchResult> search({
    required List<ProviderRef> set,
    required String query,
    int page = 1,
    int concurrency = 5,
    Duration perProviderTimeout = const Duration(seconds: 10),
  }) => Stream.fromIterable([
    for (final ref in set)
      ProviderSearchResult(
        provider: ref,
        items: rows,
        status: ProviderSearchStatus.ok,
      ),
  ]);

  @override
  Future<ProviderSearchResult> searchProvider(
    ProviderRef ref,
    String query, {
    int page = 1,
    Duration timeout = const Duration(seconds: 10),
    bool deliberate = false,
  }) async {
    legs.add((ref.id, query, page));
    return ProviderSearchResult(
      provider: ref,
      items: rows,
      status: ProviderSearchStatus.ok,
      page: page,
    );
  }
}

MovieEntity _movie(String title) => MovieEntity(
  externalId: title,
  title: title,
  description: '',
  slug: title,
  url: 'https://src/$title',
  provider: 'an:x',
  thumbnail: null,
  year: null,
  rating: null,
  qualities: null,
  category: 'anime',
);

ProviderEntity _provider(String id) => ProviderEntity(
  id: id,
  name: id,
  image: '',
  url: '',
  description: '',
  domains: const [],
  category: 'anime',
);

/// Stands in for the two repositories the service never reaches in these
/// tests: every test passes its own candidate list, which is what the sheet and
/// the resolver both do in production, and none of them resolves an episode.
class _Unused implements ProviderRepository, DetailRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'the service reached ${invocation.memberName} unexpectedly',
  );
}

AlternateSourceService _service(_FanOut engine) {
  final unused = _Unused();
  return AlternateSourceService(
    engine: engine,
    providers: GetProvidersUseCase(unused),
    episodes: GetEpisodesUseCase(unused),
  );
}

void main() {
  group('rank', () {
    test('the screenshot: four wrong shows are no longer offered', () {
      final service = _service(_FanOut());
      const query = 'Return of the Blossoming Blade';
      for (final wrong in const [
        'Return',
        'Blade of the Immortal',
        'K: Return of Kings',
        'Aladdin The Return of Jafar (1994) Movie Hindi Dubbed Download',
        'The Lord of the Rings: The Return of the King',
      ]) {
        expect(
          service.rank([_movie(wrong)], query),
          isNull,
          reason: '"$wrong" was offered as "$query"',
        );
      }
    });

    test('the right answer is picked out of a field of wrong ones', () {
      final service = _service(_FanOut());
      final best = service.rank(const [
        'K: Return of Kings',
        'Return of the Blossoming Blade',
        'Return',
      ].map(_movie).toList(), 'Return of the Blossoming Blade');
      expect(best?.$1.title, 'Return of the Blossoming Blade');
      expect(best?.$2.confidence, TitleConfidence.exact);
    });

    test('an Uzbek listing still answers an English query', () {
      // The noise list is why this service was worth having; it moved into
      // TitleMatch with the rest of the scoring and must not have been lost.
      final service = _service(_FanOut());
      final best = service.rank([
        _movie('Naruto Shippuden (Uzbek tilida) barcha qismlar'),
      ], 'Naruto Shippuden');
      expect(best?.$2.confidence, TitleConfidence.exact);
    });

    test('a source answering with its front page yields nothing', () {
      final service = _service(_FanOut());
      expect(
        service.rank(const [
          'Solo Leveling',
          'Frieren',
          'Bleach',
        ].map(_movie).toList(), 'Return of the Blossoming Blade'),
        isNull,
      );
    });
  });

  group('find', () {
    test('a wrong-show row is dropped, a right one carries its band', () async {
      final engine = _FanOut(
        rows: [_movie('Return'), _movie('Return of the Blossoming Blade')],
      );
      final found = await _service(engine)
          .find(
            title: 'Return of the Blossoming Blade',
            excludeProvider: 'vidapi',
            category: 'anime',
            candidates: [_provider('an:one'), _provider('vidapi')],
          )
          .toList();
      expect(found.map((f) => f.provider.id), ['an:one']);
      expect(found.single.item.title, 'Return of the Blossoming Blade');
      expect(found.single.confidence, TitleConfidence.exact);
      expect(found.single.isTrustworthy, isTrue);
      expect(found.single.score, 1);
    });
  });

  group('searchOne', () {
    test('asks that one source and ranks nothing', () async {
      final engine = _FanOut(
        rows: [_movie('Bleach'), _movie('Frieren'), _movie('Return')],
      );
      final result = await _service(engine).searchOne(
        providerId: 'an:one',
        query: 'blossoming',
        candidates: [_provider('an:one'), _provider('an:two')],
      );
      // Every row the source gave, in the source's own order: the viewer typed
      // the query, so the app has no standing to tell them it missed.
      expect(result?.items.map((i) => i.title), [
        'Bleach',
        'Frieren',
        'Return',
      ]);
      expect(result?.status, ProviderSearchStatus.ok);
      expect(engine.legs, [('an:one', 'blossoming', 1)]);
    });

    test('a source that is not installed is null, not an empty result', () async {
      final engine = _FanOut();
      final result = await _service(engine).searchOne(
        providerId: 'an:gone',
        query: 'anything',
        candidates: [_provider('an:one')],
      );
      expect(result, isNull);
      expect(engine.legs, isEmpty);
    });

    test('an empty query is not a request', () async {
      final engine = _FanOut();
      expect(
        await _service(engine).searchOne(
          providerId: 'an:one',
          query: '   ',
          candidates: [_provider('an:one')],
        ),
        isNull,
      );
      expect(engine.legs, isEmpty);
    });
  });
}
