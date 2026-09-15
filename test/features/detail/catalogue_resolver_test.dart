import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/detail/domain/services/alternate_source_service.dart';
import 'package:soplay/features/detail/domain/services/catalogue_resolver.dart';
import 'package:soplay/features/home/domain/entities/movie.dart';
import 'package:soplay/features/profile/domain/entities/provider_entity.dart';
import 'package:soplay/features/search/domain/entities/cross_search_result.dart';

class _Hive implements HiveService {
  final Map<String, String> links = {};
  @override
  String? getCatalogueLink(String key) => links[key];
  @override
  Future<void> setCatalogueLink(String key, String? value) async {
    if (value == null) {
      links.remove(key);
    } else {
      links[key] = value;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MovieEntity _movie(String title, {int? year, String category = 'anime'}) =>
    MovieEntity(
      externalId: title,
      title: title,
      description: '',
      slug: title,
      url: 'https://src/$title',
      provider: 'an:x',
      thumbnail: null,
      year: year,
      rating: null,
      qualities: null,
      category: category,
    );

ProviderEntity _provider(String id, {String category = 'anime'}) =>
    ProviderEntity(
      id: id,
      name: id,
      image: '',
      url: '',
      description: '',
      domains: const [],
      category: category,
    );

AlternateSource _found(
  String provider,
  String title,
  double score, {
  int? year,
}) => AlternateSource(
  provider: ProviderRef(
    id: provider,
    name: provider,
    kind: ProviderKind.channel,
  ),
  item: _movie(title, year: year),
  score: score,
);

void main() {
  group('CatalogueResolver', () {
    test('takes the closest answer and remembers it', () async {
      final hive = _Hive();
      final resolver = CatalogueResolver(
        hive: hive,
        providers: () async => [_provider('an:x')],
        finder: ({required title, required candidates}) => Stream.fromIterable([
          _found('an:weak', 'Frieren Season 9', 0.62),
          _found('an:best', 'Frieren', 0.97),
        ]),
      );
      final link = await resolver.resolve(
        catalogueId: 'cat:anilist',
        contentUrl: 'https://anilist.co/anime/1',
        hint: _movie('Frieren', year: 2023),
      );
      expect(link?.providerId, 'an:best');
      expect(hive.links.length, 1, reason: 'a confident match is kept');
      expect(
        resolver
            .remembered('cat:anilist', 'https://anilist.co/anime/1')
            ?.providerId,
        'an:best',
      );
    });

    test('a remembered link is used without searching', () async {
      final hive = _Hive();
      var searched = false;
      final resolver = CatalogueResolver(
        hive: hive,
        providers: () async => [_provider('an:x')],
        finder: ({required title, required candidates}) {
          searched = true;
          return const Stream.empty();
        },
      );
      await hive.setCatalogueLink(
        'cat:anilist|u',
        const CatalogueLink(
          providerId: 'an:kept',
          providerName: 'Kept',
          contentUrl: 'x',
        ).encode(),
      );
      final link = await resolver.resolve(
        catalogueId: 'cat:anilist',
        contentUrl: 'u',
        hint: _movie('Anything'),
      );
      expect(link?.providerId, 'an:kept');
      expect(searched, isFalse);
    });

    test('the year breaks a tie between a title and its remake', () async {
      final resolver = CatalogueResolver(
        hive: _Hive(),
        providers: () async => [_provider('an:x')],
        finder: ({required title, required candidates}) => Stream.fromIterable([
          _found('an:remake', 'Hunter x Hunter', 0.9, year: 2011),
          _found('an:original', 'Hunter x Hunter', 0.9, year: 1999),
        ]),
      );
      final link = await resolver.resolve(
        catalogueId: 'cat:anilist',
        contentUrl: 'u',
        hint: _movie('Hunter x Hunter', year: 1999),
      );
      expect(link?.providerId, 'an:original');
    });

    test('the 2023 live-action does not beat the 1999 anime', () async {
      final resolver = CatalogueResolver(
        hive: _Hive(),
        providers: () async => [
          _provider('vidapi', category: 'tmdb'),
          _provider('an:anime'),
        ],
        finder: ({required title, required candidates}) => Stream.fromIterable([
          _found('vidapi', 'One Piece', 1.0, year: 2023),
          _found('an:anime', 'One Piece', 0.95, year: 1999),
        ]),
      );
      final link = await resolver.resolve(
        catalogueId: 'cat:anilist',
        contentUrl: 'u',
        hint: _movie('One Piece', year: 1999),
      );
      expect(link?.providerId, 'an:anime');
    });

    test('a film catalogue prefers a film source over an anime one', () async {
      final resolver = CatalogueResolver(
        hive: _Hive(),
        providers: () async => [
          _provider('an:anime'),
          _provider('asilmedia', category: 'movies'),
        ],
        finder: ({required title, required candidates}) => Stream.fromIterable([
          _found('an:anime', 'Dune', 0.9),
          _found('asilmedia', 'Dune', 0.9),
        ]),
      );
      final link = await resolver.resolve(
        catalogueId: 'cat:tmdb',
        contentUrl: 'u',
        hint: _movie('Dune', category: 'movie'),
      );
      expect(link?.providerId, 'asilmedia');
    });

    test('a weak match opens once but is not remembered', () async {
      final hive = _Hive();
      final resolver = CatalogueResolver(
        hive: hive,
        providers: () async => [_provider('an:x')],
        finder: ({required title, required candidates}) =>
            Stream.fromIterable([_found('an:meh', 'Something Else', 0.4)]),
      );
      final link = await resolver.resolve(
        catalogueId: 'cat:anilist',
        contentUrl: 'u',
        hint: _movie('Frieren'),
      );
      expect(link?.providerId, 'an:meh');
      expect(hive.links, isEmpty);
    });

    test(
      'nothing found is null, and a failing search is not an exception',
      () async {
        final resolver = CatalogueResolver(
          hive: _Hive(),
          providers: () async => [_provider('an:x')],
          finder: ({required title, required candidates}) =>
              Stream<AlternateSource>.error(StateError('boom')),
        );
        expect(
          await resolver.resolve(
            catalogueId: 'cat:anilist',
            contentUrl: 'u',
            hint: _movie('X'),
          ),
          isNull,
        );
      },
    );

    test('only video sources are asked, never readers', () async {
      List<ProviderEntity>? asked;
      final resolver = CatalogueResolver(
        hive: _Hive(),
        providers: () async => [
          _provider('an:anime'),
          _provider('mn:manga'),
          _provider('cs:cloud'),
        ],
        finder: ({required title, required candidates}) {
          asked = candidates;
          return const Stream.empty();
        },
      );
      await resolver.resolve(
        catalogueId: 'cat:tmdb',
        contentUrl: 'u',
        hint: _movie('Dune', category: 'movie'),
      );
      expect(asked?.map((p) => p.id), ['an:anime', 'cs:cloud']);
    });

    test('a manga title is asked of the readers, never the players', () async {
      List<ProviderEntity>? asked;
      final resolver = CatalogueResolver(
        hive: _Hive(),
        providers: () async => [
          _provider('an:anime'),
          _provider('mn:manga'),
          _provider('cs:cloud'),
        ],
        finder: ({required title, required candidates}) {
          asked = candidates;
          return const Stream.empty();
        },
      );
      await resolver.resolve(
        catalogueId: 'cat:anilist-manga',
        contentUrl: 'https://anilist.co/manga/30002',
        hint: _movie('Berserk', category: 'manga'),
      );
      expect(asked?.map((p) => p.id), ['mn:manga']);
    });

    test('a link survives a round trip through storage', () {
      const link = CatalogueLink(
        providerId: 'cs:Anikage',
        providerName: 'Anikage (Uzbek tilida)',
        contentUrl: 'https://a/b?c=d&e=f',
        providerImage: 'https://a/logo.png',
      );
      final back = CatalogueLink.decode(link.encode());
      expect(back?.providerId, link.providerId);
      expect(back?.providerName, link.providerName);
      expect(back?.contentUrl, link.contentUrl);
      // The mark next to the catalogue's is drawn from this on the second
      // open, when there is no search to take it from.
      expect(back?.providerImage, link.providerImage);
      expect(CatalogueLink.decode('not json'), isNull);
    });
  });
}
