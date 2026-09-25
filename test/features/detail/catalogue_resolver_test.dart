import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/content/catalogue.dart';
import 'package:soplay/core/content/content_mode.dart';
import 'package:soplay/core/matching/title_match.dart';
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

MovieEntity _movie(
  String title, {
  int? year,
  String category = 'anime',
  List<String> altTitles = const [],
}) => MovieEntity(
  externalId: title,
  title: title,
  altTitles: altTitles,
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
  // The band, not a second opinion about it: every decision the resolver makes
  // is now made on the band, so a fixture that set one by hand would be
  // testing the fixture.
  match: TitleMatch(score: score, confidence: TitleMatch.confidenceOf(score)),
);

/// What kind of source each installed id is.
///
/// Handed to the resolver rather than left to the real lookup because that one
/// asks the installed-repo store through the service locator: with no locator
/// up, every reader id reads as manga and a novel source cannot be installed in
/// a unit test at all. Only the one `my:` id is declared here; every other id is
/// still asked the real question, so the anime and manga rows below are ranked
/// by exactly what production would say about them.
ContentMode _kind(String id) =>
    id == 'my:novelsite' ? ContentMode.novel : id.contentMode;

void main() {
  group('CatalogueResolver', () {
    test('takes the closest answer and remembers it', () async {
      final hive = _Hive();
      final resolver = CatalogueResolver(
        hive: hive,
        providers: () async => [_provider('an:x')],
        finder: ({required title, required candidates, onOutcome}) =>
            Stream.fromIterable([
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
        finder: ({required title, required candidates, onOutcome}) {
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
        finder: ({required title, required candidates, onOutcome}) =>
            Stream.fromIterable([
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
        finder: ({required title, required candidates, onOutcome}) =>
            Stream.fromIterable([
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
        finder: ({required title, required candidates, onOutcome}) =>
            Stream.fromIterable([
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
        finder: ({required title, required candidates, onOutcome}) =>
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
          finder: ({required title, required candidates, onOutcome}) =>
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
        finder: ({required title, required candidates, onOutcome}) {
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
        finder: ({required title, required candidates, onOutcome}) {
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

  group('CatalogueResolver.locate says which kind of nothing it found', () {
    CatalogueResolver build({
      required List<ProviderEntity> installed,
      AlternateSearchOutcome? outcome,
    }) => CatalogueResolver(
      hive: _Hive(),
      providers: () async => installed,
      finder: ({required title, required candidates, onOutcome}) {
        if (outcome != null) onOutcome?.call(outcome);
        return const Stream.empty();
      },
    );

    test('no reader installed is not "no source has this manga"', () async {
      // The reported symptom: opening a manga from the AniList shelf on an
      // install with only video sources said the sources did not carry it.
      // Nothing was asked — there was nothing of that kind to ask.
      final out = await build(installed: [_provider('an:anime')]).locate(
        catalogueId: 'cat:anilist-manga',
        contentUrl: 'u',
        hint: _movie('Berserk', category: 'manga'),
      );
      expect(out.found, isFalse);
      expect(out.miss, CatalogueMiss.noSourcesOfKind);
      expect(out.catalogue, Catalogue.anilistManga);
    });

    test('sources asked and answered, none carries it', () async {
      final out =
          await build(
            installed: [_provider('mn:manga')],
            outcome: const AlternateSearchOutcome(asked: 1),
          ).locate(
            catalogueId: 'cat:anilist-manga',
            contentUrl: 'u',
            hint: _movie('Berserk', category: 'manga'),
          );
      expect(out.miss, CatalogueMiss.notCarried);
    });

    test('every source failing is not an answer about the title', () async {
      final out =
          await build(
            installed: [_provider('mn:manga')],
            outcome: const AlternateSearchOutcome(asked: 1, failed: 1),
          ).locate(
            catalogueId: 'cat:anilist-manga',
            contentUrl: 'u',
            hint: _movie('Berserk', category: 'manga'),
          );
      expect(out.miss, CatalogueMiss.sourcesUnreachable);
    });

    test(
      'a card with no title is a bug upstream, not a missing source',
      () async {
        final out = await build(
          installed: [_provider('an:anime')],
        ).locate(catalogueId: 'cat:anilist', contentUrl: 'u', hint: null);
        expect(out.miss, CatalogueMiss.nothingToSearch);
      },
    );

    test('a found link reports no miss at all', () async {
      final resolver = CatalogueResolver(
        hive: _Hive(),
        providers: () async => [_provider('an:x')],
        finder: ({required title, required candidates, onOutcome}) =>
            Stream.fromIterable([_found('an:x', 'Frieren', 1.0)]),
      );
      final out = await resolver.locate(
        catalogueId: 'cat:anilist',
        contentUrl: 'u',
        hint: _movie('Frieren'),
      );
      expect(out.found, isTrue);
      expect(out.miss, isNull);
    });
  });

  group('a light novel can find a source', () {
    CatalogueResolver build({
      required List<ProviderEntity> installed,
      List<AlternateSource> answers = const [],
      HiveService? hive,
      void Function(List<ProviderEntity> asked)? onAsk,
    }) => CatalogueResolver(
      hive: hive ?? _Hive(),
      providers: () async => installed,
      providerKind: _kind,
      finder: ({required title, required candidates, onOutcome}) {
        onAsk?.call(candidates);
        return Stream.fromIterable(answers);
      },
    );

    test('the novel shelf asks only the novel sources', () async {
      List<ProviderEntity>? asked;
      await build(
        installed: [
          _provider('my:novelsite'),
          _provider('mn:comics'),
          _provider('an:anime'),
          _provider('cs:cloud'),
        ],
        onAsk: (c) => asked = c,
      ).resolve(
        catalogueId: 'cat:anilist-novel',
        contentUrl: 'https://anilist.co/manga/39115',
        hint: _movie('Spice and Wolf', category: 'novel'),
      );
      expect(asked?.map((p) => p.id), ['my:novelsite']);
    });

    test('a novel source answers the novel shelf', () async {
      final hive = _Hive();
      final out =
          await build(
            hive: hive,
            installed: [_provider('my:novelsite'), _provider('mn:comics')],
            answers: [
              _found('my:novelsite', 'Spice and Wolf Light Novel', 0.72),
            ],
          ).locate(
            catalogueId: 'cat:anilist-novel',
            contentUrl: 'u',
            hint: _movie('Spice and Wolf', category: 'novel'),
          );
      expect(out.link?.providerId, 'my:novelsite');
      expect(out.link?.approximate, isFalse);
      expect(hive.links.length, 1);
    });

    test('with only manga readers the novel shelf asks nobody', () async {
      List<ProviderEntity>? asked;
      final out = await build(
        installed: [_provider('mn:comics')],
        answers: [_found('mn:comics', 'Spice and Wolf', 1.0)],
        onAsk: (c) => asked = c,
      ).locate(
        catalogueId: 'cat:anilist-novel',
        contentUrl: 'u',
        hint: _movie('Spice and Wolf', category: 'novel'),
      );
      expect(asked, isNull);
      expect(out.found, isFalse);
      expect(out.miss, CatalogueMiss.noSourcesOfKind);
    });

    test('no reader of any kind is still "nothing was asked"', () async {
      // Widening the candidates must not turn an honest "install a reader"
      // into a search that finds nothing and blames the title.
      final out = await build(installed: [_provider('an:anime')]).locate(
        catalogueId: 'cat:anilist-novel',
        contentUrl: 'u',
        hint: _movie('Spice and Wolf', category: 'novel'),
      );
      expect(out.found, isFalse);
      expect(out.miss, CatalogueMiss.noSourcesOfKind);
      expect(out.catalogue, Catalogue.anilistNovel);
    });

    test('the manga shelf is not widened, and its pick is no guess', () async {
      List<ProviderEntity>? asked;
      final hive = _Hive();
      final out =
          await build(
            hive: hive,
            installed: [_provider('my:novelsite'), _provider('mn:comics')],
            answers: [_found('mn:comics', 'Berserk', 1.0)],
            onAsk: (c) => asked = c,
          ).locate(
            catalogueId: 'cat:anilist-manga',
            contentUrl: 'u',
            hint: _movie('Berserk', category: 'manga'),
          );
      expect(asked?.map((p) => p.id), ['mn:comics']);
      expect(out.link?.approximate, isFalse);
      expect(hive.links.length, 1);
    });

    test('an anime pick is never marked a guess', () async {
      // No provider kind handed in: this is the production lookup, and the
      // path every other test in this file rides.
      final out =
          await CatalogueResolver(
            hive: _Hive(),
            providers: () async => [_provider('an:x')],
            finder: ({required title, required candidates, onOutcome}) =>
                Stream.fromIterable([_found('an:x', 'Frieren', 1.0)]),
          ).locate(
            catalogueId: 'cat:anilist',
            contentUrl: 'u',
            hint: _movie('Frieren'),
          );
      expect(out.link?.approximate, isFalse);
    });

    test('a guess survives storage as a guess', () async {
      const guess = CatalogueLink(
        providerId: 'mn:comics',
        providerName: 'Comics',
        contentUrl: 'https://c/spice',
        approximate: true,
      );
      expect(CatalogueLink.decode(guess.encode())?.approximate, isTrue);
      expect(
        CatalogueLink.decode(
          const CatalogueLink(
            providerId: 'mn:comics',
            providerName: 'Comics',
            contentUrl: 'https://c/berserk',
          ).encode(),
        )?.approximate,
        isFalse,
      );
      expect(guess.withCatalogue('cat:anilist-novel').approximate, isTrue);
    });
  });

  // How long a catalogue title is looked for before the app declares nothing
  // carries it.
  //
  // Eight seconds was the whole of it, which made this the least patient search
  // in the app while asking the most of it: a backend leg is allowed ten seconds
  // on its own and an extension host forty-five, because the first search
  // against a freshly-installed source has to download and dex-load its APK
  // first. So a title came back "none of your sources has this" before a single
  // on-device leg could have finished — and then opened first try when the
  // viewer searched for it by hand. Same source, same title, different patience.
  group('how long it waits', () {
    ProviderEntity anime(String id) => _provider(id);

    /// A finder that answers once, [after] the run starts.
    AlternateFinder answersAt(Duration after, AlternateSource result) =>
        ({required title, required candidates, onOutcome}) {
          final controller = StreamController<AlternateSource>();
          Timer(after, () {
            if (controller.isClosed) return;
            controller.add(result);
            onOutcome?.call(const AlternateSearchOutcome(asked: 1));
            controller.close();
          });
          return controller.stream;
        };

    test('a source that answers at 15s is still used', () {
      fakeAsync((async) {
        final hive = _Hive();
        final resolver = CatalogueResolver(
          hive: hive,
          providers: () async => [anime('an:slow')],
          providerKind: _kind,
          finder: answersAt(
            const Duration(seconds: 15),
            _found('an:slow', 'Frieren', 0.97),
          ),
        );
        CatalogueResolution? out;
        resolver
            .locate(
              catalogueId: 'cat:anilist',
              contentUrl: 'https://anilist.co/anime/1',
              hint: _movie('Frieren', year: 2023),
            )
            .then((r) => out = r);

        async.elapse(const Duration(seconds: 10));
        async.flushMicrotasks();
        expect(out, isNull, reason: 'gave up while a leg was still out');
        async.elapse(const Duration(seconds: 10));
        async.flushMicrotasks();
        expect(out?.link?.providerId, 'an:slow');
      });
    });

    test('but an answer in hand is taken at eight, not held to twenty-five', () {
      fakeAsync((async) {
        final hive = _Hive();
        final resolver = CatalogueResolver(
          hive: hive,
          providers: () async => [anime('an:fast'), anime('an:never')],
          providerKind: _kind,
          // A plausible answer early, and a leg that never reports — a source
          // whose own timeout outlasts this search.
          finder: ({required title, required candidates, onOutcome}) {
            final controller = StreamController<AlternateSource>();
            Timer(const Duration(seconds: 2), () {
              // Weak on purpose: an exact match completes early on its own, so
              // that path would not exercise the deadline at all.
              controller.add(_found('an:fast', 'Frieren Season 9', 0.62));
            });
            return controller.stream;
          },
        );
        CatalogueResolution? out;
        resolver
            .locate(
              catalogueId: 'cat:anilist',
              contentUrl: 'https://anilist.co/anime/2',
              hint: _movie('Frieren', year: 2023),
            )
            .then((r) => out = r);

        async.elapse(const Duration(seconds: 9));
        async.flushMicrotasks();
        expect(out?.link?.providerId, 'an:fast');
      });
    });

    test('and nothing at all still ends, as not carried', () {
      fakeAsync((async) {
        final hive = _Hive();
        final resolver = CatalogueResolver(
          hive: hive,
          providers: () async => [anime('an:empty')],
          providerKind: _kind,
          finder: ({required title, required candidates, onOutcome}) {
            onOutcome?.call(const AlternateSearchOutcome(asked: 1));
            return const Stream.empty();
          },
        );
        CatalogueResolution? out;
        resolver
            .locate(
              catalogueId: 'cat:anilist',
              contentUrl: 'https://anilist.co/anime/3',
              hint: _movie('Frieren', year: 2023),
            )
            .then((r) => out = r);

        async.elapse(const Duration(seconds: 30));
        async.flushMicrotasks();
        expect(out, isNotNull, reason: 'the search never ended');
        expect(out?.link, isNull);
        expect(out?.miss, CatalogueMiss.notCarried);
      });
    });
  });

  // A source indexes a show under whichever name its own site uses, and a
  // catalogue knows several. Measured: animecube lists "Kaiju Girl Caramelise"
  // and answers a search for "Otome Kaijuu Caramelise" with nothing at all, so a
  // title it carries came back carried by nothing and the page offered no Play.
  group('the other name', () {
    /// A source that only answers to [knownAs].
    AlternateFinder onlyAnswersTo(String knownAs, String provider) =>
        ({required title, required candidates, onOutcome}) {
          onOutcome?.call(const AlternateSearchOutcome(asked: 1));
          if (title != knownAs) return const Stream.empty();
          return Stream.fromIterable([_found(provider, knownAs, 0.98)]);
        };

    test('is asked when the first name found nothing', () async {
      final hive = _Hive();
      final asked = <String>[];
      final resolver = CatalogueResolver(
        hive: hive,
        providers: () async => [_provider('an:cube')],
        providerKind: _kind,
        finder: ({required title, required candidates, onOutcome}) {
          asked.add(title);
          return onlyAnswersTo('Kaiju Girl Caramelise', 'an:cube')(
            title: title,
            candidates: candidates,
            onOutcome: onOutcome,
          );
        },
      );

      final found = await resolver.locate(
        catalogueId: 'cat:anilist',
        contentUrl: 'https://anilist.co/anime/11',
        hint: _movie(
          'Otome Kaijuu Caraméliser',
          year: 2022,
          altTitles: const ['Kaiju Girl Caramelise'],
        ),
      );

      expect(asked, ['Otome Kaijuu Caraméliser', 'Kaiju Girl Caramelise']);
      expect(found.link?.providerId, 'an:cube');
    });

    test('is not asked when the first name already resolved', () async {
      // A title that works costs exactly what it did before this existed.
      final hive = _Hive();
      final asked = <String>[];
      final resolver = CatalogueResolver(
        hive: hive,
        providers: () async => [_provider('an:x')],
        providerKind: _kind,
        finder: ({required title, required candidates, onOutcome}) {
          asked.add(title);
          return Stream.fromIterable([_found('an:x', 'Frieren', 0.99)]);
        },
      );

      await resolver.locate(
        catalogueId: 'cat:anilist',
        contentUrl: 'https://anilist.co/anime/12',
        hint: _movie(
          'Frieren',
          year: 2023,
          altTitles: const ['Sousou no Frieren'],
        ),
      );

      expect(asked, ['Frieren']);
    });

    test('and a weak first answer is not thrown away by a second miss', () async {
      // The retry is for turning a guess into the right title, never for losing
      // the guess.
      final hive = _Hive();
      final resolver = CatalogueResolver(
        hive: hive,
        providers: () async => [_provider('an:x')],
        providerKind: _kind,
        finder: ({required title, required candidates, onOutcome}) {
          onOutcome?.call(const AlternateSearchOutcome(asked: 1));
          if (title != 'Frieren') return const Stream.empty();
          // Weak, so the second name is asked at all: [TitleMatch.strongAt] is
          // 0.60 and anything at or above it is already an answer to act on.
          return Stream.fromIterable([
            _found('an:x', 'Frieren and the Nine Others', 0.5),
          ]);
        },
      );

      final found = await resolver.locate(
        catalogueId: 'cat:anilist',
        contentUrl: 'https://anilist.co/anime/13',
        hint: _movie(
          'Frieren',
          year: 2023,
          altTitles: const ['Sousou no Frieren'],
        ),
      );

      expect(found.link?.providerId, 'an:x');
      expect(
        hive.links,
        isEmpty,
        reason: 'a weak match is still not remembered',
      );
    });

    test('a name that is the same bar punctuation is asked once', () async {
      final hive = _Hive();
      final asked = <String>[];
      final resolver = CatalogueResolver(
        hive: hive,
        providers: () async => [_provider('an:x')],
        providerKind: _kind,
        finder: ({required title, required candidates, onOutcome}) {
          asked.add(title);
          onOutcome?.call(const AlternateSearchOutcome(asked: 1));
          return const Stream.empty();
        },
      );

      await resolver.locate(
        catalogueId: 'cat:anilist',
        contentUrl: 'https://anilist.co/anime/14',
        hint: _movie(
          'Re:ZERO -Starting Life in Another World-',
          altTitles: const ['Re:Zero Starting Life in Another World'],
        ),
      );

      expect(asked, hasLength(1));
    });

    test('with no other name there is no second pass', () async {
      final hive = _Hive();
      final asked = <String>[];
      final resolver = CatalogueResolver(
        hive: hive,
        providers: () async => [_provider('an:x')],
        providerKind: _kind,
        finder: ({required title, required candidates, onOutcome}) {
          asked.add(title);
          onOutcome?.call(const AlternateSearchOutcome(asked: 1));
          return const Stream.empty();
        },
      );

      final found = await resolver.locate(
        catalogueId: 'cat:anilist',
        contentUrl: 'https://anilist.co/anime/15',
        hint: _movie('Nothing Has This'),
      );

      expect(asked, hasLength(1));
      expect(found.miss, CatalogueMiss.notCarried);
    });
  });
}
