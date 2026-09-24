// The Trakt screen's data: Trakt's rows read into one shape with their art,
// the profile numbers, "up next" built from the shows in progress, and the
// actions that change them.
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/features/trakt/data/trakt_api.dart';
import 'package:soplay/features/trakt/data/trakt_hub_models.dart';
import 'package:soplay/features/trakt/data/trakt_link_store.dart';
import 'package:soplay/features/trakt/data/trakt_service.dart';
import 'package:soplay/features/trakt/presentation/trakt_hub_controller.dart';

TraktEntry _show(int id, String title) => TraktEntry(
  media: TraktMedia(kind: 'show', traktId: id, title: title),
);

class _FakeApi extends TraktApi {
  List<TraktEntry> watched = const [];
  final Map<int, ({int aired, int completed, TraktEpisodeRef? next})> progress =
      {};
  final List<Map<String, dynamic>> written = [];

  @override
  Future<List<TraktEntry>> watchedShows({
    required String clientId,
    required String token,
  }) async => watched;

  @override
  Future<({int aired, int completed, TraktEpisodeRef? next})> showProgress(
    int showId, {
    required String clientId,
    required String token,
  }) async => progress[showId]!;

  @override
  Future<List<TraktEntry>> playback({
    required String clientId,
    required String token,
  }) async => const [];

  @override
  Future<void> addHistory(
    Map<String, dynamic> body, {
    required String clientId,
    required String token,
  }) async => written.add(body);
}

void main() {
  group('reading Trakt', () {
    test('a row carries its art, with the scheme Trakt leaves off', () {
      final e = TraktEntry.fromRow({
        'type': 'episode',
        'watched_at': '2026-09-20T18:30:00.000Z',
        'id': 991,
        'episode': {
          'season': 2,
          'number': 5,
          'title': 'The Door',
          'ids': {'trakt': 77},
          'images': {
            'screenshot': ['media.trakt.tv/images/episodes/1/shot.jpg.webp'],
          },
        },
        'show': {
          'title': 'Dark',
          'year': 2017,
          'ids': {'trakt': 5, 'tmdb': 70523},
          'images': {
            'poster': ['media.trakt.tv/images/shows/5/poster.jpg.webp'],
          },
        },
      }, atKey: 'watched_at')!;
      expect(e.media.isMovie, isFalse);
      expect(
        e.media.poster,
        'https://media.trakt.tv/images/shows/5/poster.jpg.webp',
      );
      expect(e.media.tmdbUrl, 'https://www.themoviedb.org/tv/70523');
      expect(e.episode!.code, 'S2 · E5');
      expect(e.episode!.screenshot, startsWith('https://'));
      expect(e.id, 991);
      expect(e.at, isNotNull);
    });

    test('a season row is not a title', () {
      expect(
        TraktEntry.fromRow({
          'type': 'season',
          'show': {
            'title': 'Dark',
            'ids': {'trakt': 5},
          },
        }),
        isNull,
      );
    });

    test('profile numbers add up to hours', () {
      final s = TraktStats.fromJson({
        'movies': {'watched': 10, 'minutes': 1200},
        'episodes': {'watched': 50, 'minutes': 2400},
        'ratings': {
          'total': 7,
          'distribution': {'8': 3, '10': 4},
        },
      });
      expect(s.hours, 60);
      expect(s.distribution[10], 4);
    });
  });

  group('the hub', () {
    late Box auth;
    late Box settings;
    late _FakeApi api;
    late TraktHubController hub;

    setUpAll(() async {
      Hive.init('${Directory.systemTemp.path}/sozo_trakt_hub_test');
      auth = await Hive.openBox('trakt_hub_auth');
      settings = await Hive.openBox('trakt_hub_settings');
    });
    tearDownAll(() async => Hive.close());

    setUp(() async {
      await auth.clear();
      await auth.put(
        AppConstants.traktLinkKey,
        jsonEncode({
          'accessToken': 't',
          'clientId': 'c',
          'userId': 'me',
          'name': 'Me',
        }),
      );
      api = _FakeApi();
      final service = TraktService(
        backendDio: Dio(),
        links: TraktLinkStore(box: settings),
        api: api,
        box: auth,
      );
      await service.restore();
      hub = TraktHubController(service: service);
    });

    tearDown(() => hub.dispose());

    test('up next keeps the order watched and drops shows caught up', () async {
      api.watched = [_show(1, 'A'), _show(2, 'B'), _show(3, 'C')];
      api.progress[1] = (
        aired: 10,
        completed: 4,
        next: const TraktEpisodeRef(season: 1, number: 5),
      );
      api.progress[2] = (aired: 8, completed: 8, next: null);
      api.progress[3] = (
        aired: 20,
        completed: 1,
        next: const TraktEpisodeRef(season: 1, number: 2),
      );
      await hub.loadUpNext();
      expect(hub.upNext.items.map((e) => e.media.title), ['A', 'C']);
      expect(hub.upNext.items.first.fraction, closeTo(0.4, 0.001));
    });

    test('marking a show with no episode named marks its next one', () async {
      api.progress[1] = (
        aired: 10,
        completed: 4,
        next: const TraktEpisodeRef(season: 2, number: 3),
      );
      final error = await hub.markWatched(_show(1, 'A'));
      expect(error, isNull);
      final show = (api.written.single['shows'] as List).single as Map;
      final season = (show['seasons'] as List).single as Map;
      expect(season['number'], 2);
      expect(((season['episodes'] as List).single as Map)['number'], 3);
      expect(api.written.single.containsKey('movies'), isFalse);
    });
  });
}
