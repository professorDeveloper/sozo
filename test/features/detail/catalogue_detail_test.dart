import 'package:flutter_test/flutter_test.dart';

import 'package:soplay/features/anilist/domain/entities/anilist_entities.dart';
import 'package:soplay/features/detail/domain/services/catalogue_detail.dart';
import 'package:soplay/features/detail/domain/services/catalogue_resolver.dart';
import 'package:soplay/features/detail/presentation/widgets/tracking_row.dart';

void main() {
  group('detailFromAnilist', () {
    final detail = AnilistMediaDetail(
      media: const AnilistMedia(
        id: 154587,
        idMal: 52991,
        romajiTitle: 'Sousou no Frieren',
        englishTitle: 'Frieren: Beyond Journey\'s End',
        description: 'The demon king is dead.<br><i>What now?</i>',
        episodes: 28,
        seasonYear: 2023,
        format: 'TV',
        status: 'FINISHED',
        siteUrl: 'https://anilist.co/anime/154587',
        nextAiring: AnilistAiring(episode: 29, airingAt: 1800000000),
      ),
      meanScore: 91,
      rankText: '#1 of all time',
      studio: 'Madhouse',
      source: 'MANGA',
      durationMinutes: 24,
      countryOfOrigin: 'JP',
      genres: const ['Adventure', 'Fantasy'],
      tags: const ['Elf', 'Magic'],
      characters: const [
        AnilistCharacter(
          name: 'Frieren',
          image: 'f.png',
          voiceActor: 'Tanezaki Atsumi',
        ),
        AnilistCharacter(name: '', image: ''),
      ],
      recommendations: const [
        AnilistMedia(
          id: 1,
          romajiTitle: 'Mushishi',
          averageScore: 87,
          seasonYear: 2005,
        ),
      ],
    );

    test('reads as an AniList page with the record in facts', () {
      final d = detailFromAnilist(detail);
      expect(d.provider, 'cat:anilist');
      expect(d.contentUrl, 'https://anilist.co/anime/154587');
      expect(d.title, 'Frieren: Beyond Journey\'s End');
      expect(d.description, 'The demon king is dead.\nWhat now?');
      expect(d.duration, '24 min');
      expect(d.country, 'Japan');
      expect(d.isSerial, isTrue);
      expect(d.cast.single.name, 'Frieren · Tanezaki Atsumi');
      expect(d.related.single.provider, 'cat:anilist');
      expect(d.related.single.rating, 9);

      final r = d.record!;
      expect(r.anilistId, 154587);
      expect(r.malId, 52991);
      expect(r.score, 9.1);
      expect(r.nextEpisode, 29);
      expect(r.tags, ['Elf', 'Magic']);
      expect(
        {for (final f in r.facts) f.labelKey: f.value},
        {
          'detail.about_studio': 'Madhouse',
          'detail.about_source': 'Manga',
          'detail.about_episodes': '28',
          'detail.about_rank': '#1 of all time',
          'detail.about_status': 'Finished',
          'detail.about_format': 'TV',
        },
      );
    });

    test('plays from the resolved source when there is one', () {
      const via = CatalogueLink(
        providerId: 'an:allanime',
        providerName: 'AllAnime',
        contentUrl: 'https://allanime.to/frieren',
      );
      final d = detailFromAnilist(detail, via: via);
      expect(d.provider, 'an:allanime');
      expect(d.contentUrl, 'https://allanime.to/frieren');
      // The record still says where the page came from.
      expect(d.record!.anilistId, 154587);
    });
  });

  group('detailFromTmdb', () {
    final json = <String, dynamic>{
      'provider': 'tmdb',
      'contentId': '1399',
      'contentUrl': '/tv/1399',
      'title': 'Game of Thrones',
      'description': 'Seven noble families fight.',
      'year': 2011,
      'isSerial': true,
      'genres': ['Drama'],
      'related': [
        {'title': 'Rome', 'contentUrl': '/tv/3', 'provider': 'tmdb'},
      ],
      'extra': {
        'voteAverage': 8.45,
        'status': 'Ended',
        'tagline': 'Winter Is Coming',
        'about': {
          'studio': 'Revolution Sun Studios',
          'network': 'HBO',
          'budget': 0,
          'revenue': null,
          'collection': null,
          'seasons': 8,
          'episodes': 73,
          'nextEpisode': {'number': 1, 'season': 9, 'airDate': '2030-01-05'},
        },
      },
    };

    test('keeps the provider page and adds the record on top', () {
      final d = detailFromTmdb(json);
      expect(d.provider, 'cat:tmdb');
      expect(d.contentUrl, '/tv/1399');
      expect(d.description, 'Winter Is Coming\n\nSeven noble families fight.');
      expect(d.related.single.provider, 'cat:tmdb');

      final r = d.record!;
      expect(r.tmdbId, 1399);
      expect(r.score, 8.45);
      expect(r.nextEpisode, 1);
      expect(r.nextAiringAt, DateTime(2030, 1, 5));
      expect(
        {for (final f in r.facts) f.labelKey: f.value},
        {
          'detail.about_studio': 'Revolution Sun Studios',
          'detail.about_network': 'HBO',
          'detail.about_seasons': '8',
          'detail.about_episodes': '73',
          'detail.about_status': 'Ended',
        },
      );
    });

    test('money is shortened and only shown when it is known', () {
      final film = Map<String, dynamic>.from(json)
        ..['isSerial'] = false
        ..['extra'] = {
          'about': {
            'budget': 165000000,
            'revenue': 1046000000,
            'collection': 'The Dark Knight Collection',
          },
        };
      final facts = {
        for (final f in detailFromTmdb(film).record!.facts) f.labelKey: f.value,
      };
      expect(facts['detail.about_budget'], r'$165M');
      expect(facts['detail.about_box_office'], r'$1.0B');
      expect(facts['detail.about_collection'], 'The Dark Knight Collection');
      expect(facts.containsKey('detail.about_status'), isFalse);
    });

    test('a page without a record section still builds', () {
      final bare = Map<String, dynamic>.from(json)..remove('extra');
      final d = detailFromTmdb(bare);
      expect(d.title, 'Game of Thrones');
      expect(d.record!.facts, isEmpty);
      expect(d.record!.score, isNull);
    });
  });

  test('AniList words are readable, initialisms stay initialisms', () {
    String format(String raw) => detailFromAnilist(
      AnilistMediaDetail(media: AnilistMedia(id: 1, format: raw)),
    ).record!.facts.single.value;
    expect(format('TV'), 'TV');
    expect(format('TV_SHORT'), 'TV short');
    expect(format('OVA'), 'OVA');
    expect(format('MOVIE'), 'Movie');
    expect(format('NOT_YET_RELEASED'), 'Not yet released');
  });

  group('TrackingRow.applies', () {
    final tmdb = <String, dynamic>{
      'contentId': '1',
      'contentUrl': '/tv/1',
      'title': 'T',
      'genres': ['Drama'],
      'extra': {'about': {}},
    };

    test('anime trackers stay off a live-action TMDB page', () {
      expect(TrackingRow.applies(detailFromTmdb(tmdb)), isFalse);
    });

    test('but stay on for animation, and for every AniList page', () {
      final animated = Map<String, dynamic>.from(tmdb)
        ..['genres'] = ['Animation'];
      expect(TrackingRow.applies(detailFromTmdb(animated)), isTrue);
      expect(
        TrackingRow.applies(
          detailFromAnilist(
            const AnilistMediaDetail(media: AnilistMedia(id: 1)),
          ),
        ),
        isTrue,
      );
    });
  });

  group('anilistIdFrom', () {
    test('prefers the card id, falls back to the url', () {
      expect(anilistIdFrom('https://anilist.co/anime/1', externalId: '7'), 7);
      expect(anilistIdFrom('https://anilist.co/anime/154587'), 154587);
      expect(anilistIdFrom('/tv/1399'), isNull);
    });
  });
}
