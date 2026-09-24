// Trakt from the player: which film or show a source title is, which season
// and episode a source's episode number is, and what reaches Trakt — a
// scrobble when it lands, a history write from the outbox when it does not.
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/features/tracker/data/tracker_outbox.dart';
import 'package:soplay/features/trakt/data/trakt_api.dart';
import 'package:soplay/features/trakt/data/trakt_link_store.dart';
import 'package:soplay/features/trakt/data/trakt_service.dart';
import 'package:soplay/features/trakt/data/trakt_tracker.dart';

class _FakeApi extends TraktApi {
  List<TraktMedia> found = [];
  TraktMedia? tmdb;
  List<TraktSeason> seasonList = const [];
  bool failScrobble = false;
  int searches = 0;
  final List<(String, Map<String, dynamic>)> scrobbles = [];
  final List<Map<String, dynamic>> written = [];

  @override
  Future<TraktMedia?> byTmdb(
    int tmdbId,
    String kind, {
    required String clientId,
  }) async => tmdb;

  @override
  Future<List<TraktMedia>> search(
    String query, {
    required String clientId,
    String kind = 'movie,show',
    int? year,
  }) async {
    searches++;
    return found;
  }

  @override
  Future<List<TraktSeason>> seasons(
    int showId, {
    required String clientId,
  }) async => seasonList;

  @override
  Future<void> scrobble(
    String action,
    Map<String, dynamic> body, {
    required String clientId,
    required String token,
  }) async {
    if (failScrobble) throw const TraktException('offline');
    scrobbles.add((action, body));
  }

  @override
  Future<void> addHistory(
    Map<String, dynamic> body, {
    required String clientId,
    required String token,
  }) async => written.add(body);
}

TraktMedia _show(int id, String title, {int? year}) =>
    TraktMedia(kind: 'show', traktId: id, title: title, year: year);

void main() {
  late Box settings;
  late Box auth;
  late _FakeApi api;
  late TraktTracker tracker;
  late TrackerOutbox outbox;

  setUpAll(() async {
    Hive.init('${Directory.systemTemp.path}/sozo_trakt_tracker_test');
    settings = await Hive.openBox('trakt_tracker_settings');
    auth = await Hive.openBox('trakt_tracker_auth');
  });
  tearDownAll(() async => Hive.close());

  Future<void> connect() async {
    await auth.put(
      AppConstants.traktLinkKey,
      jsonEncode({
        'accessToken': 'tok',
        'clientId': 'cid',
        'userId': 'viewer',
        'name': 'Viewer',
      }),
    );
  }

  setUp(() async {
    await settings.clear();
    await auth.clear();
    await connect();
    api = _FakeApi();
    final service = TraktService(
      backendDio: Dio(),
      links: TraktLinkStore(box: settings),
      api: api,
      box: auth,
    );
    await service.restore();
    outbox = TrackerOutbox(box: settings);
    tracker = TraktTracker(service: service, outbox: outbox);
  });

  group('reading a source title', () {
    test('finds the season however the source spells it', () {
      expect(TraktTracker.seasonIn('Attack on Titan Season 3'), 3);
      expect(TraktTracker.seasonIn('Vikings S2'), 2);
      expect(TraktTracker.seasonIn('Qashqirlar makoni 4-fasl'), 4);
      expect(TraktTracker.seasonIn('Игра престолов 5 сезон'), 5);
      expect(TraktTracker.seasonIn('Breaking Bad'), isNull);
      // A year is not a season.
      expect(TraktTracker.seasonIn('Dune (2021)'), isNull);
    });

    test('strips the season, the year and the dub tags for a search', () {
      expect(TraktTracker.baseTitle('Vikings S2 [720p] (2014)'), 'Vikings');
      expect(TraktTracker.baseTitle('Naruto 2-fasl uzbek tarjima'), 'Naruto');
    });
  });

  group('matching a title', () {
    test(
      'one exact match is linked, as a guess, with the source season',
      () async {
        api.found = [_show(7, 'Vikings'), _show(8, 'Vikings: Valhalla')];
        final link = await tracker.resolve(
          provider: 'p',
          contentUrl: 'u',
          title: 'Vikings 2-fasl',
          isSerial: true,
        );
        expect(link?.traktId, 7);
        expect(link?.auto, isTrue);
        expect(link?.season, 2);
      },
    );

    test(
      'several exact matches (remakes) are no answer, and not re-asked',
      () async {
        api.found = [
          _show(1, 'Shogun', year: 1980),
          _show(2, 'Shogun', year: 2024),
        ];
        for (var i = 0; i < 3; i++) {
          expect(
            await tracker.resolve(
              provider: 'p',
              contentUrl: 'u',
              title: 'Shogun',
              isSerial: true,
            ),
            isNull,
          );
        }
        expect(api.searches, 1);
      },
    );

    test('a TMDB id beats a title search', () async {
      api.tmdb = _show(42, 'Dark');
      final link = await tracker.resolve(
        provider: 'p',
        contentUrl: 'u',
        title: 'Qorong‘ulik',
        isSerial: true,
        tmdbId: 70523,
      );
      expect(link?.traktId, 42);
      expect(api.searches, 0);
    });
  });

  group('episode numbers', () {
    const absolute = TraktLink(
      provider: 'p',
      contentUrl: 'u',
      traktId: 5,
      kind: 'show',
      title: 'Anime',
    );

    test('an absolute number walks the aired seasons', () async {
      api.seasonList = const [TraktSeason(1, 24), TraktSeason(2, 12)];
      expect(await tracker.episodeFor(absolute, 30), (season: 2, episode: 6));
      expect(await tracker.episodeFor(absolute, 24), (season: 1, episode: 24));
    });

    test('a number past everything aired stays in season 1', () async {
      api.seasonList = const [TraktSeason(1, 12)];
      expect(await tracker.episodeFor(absolute, 40), (season: 1, episode: 40));
    });

    test('a link with a season counts within it', () async {
      const s3 = TraktLink(
        provider: 'p',
        contentUrl: 'u',
        traktId: 5,
        kind: 'show',
        title: 'Anime',
        season: 3,
      );
      expect(await tracker.episodeFor(s3, 4), (season: 3, episode: 4));
      expect(await tracker.episodeFor(s3, 0), isNull);
    });
  });

  group('reporting', () {
    setUp(() {
      api.found = [_show(7, 'Vikings')];
      api.seasonList = const [TraktSeason(1, 9), TraktSeason(2, 20)];
    });

    test('a watched episode is a stop of at least 80%', () async {
      final ok = await tracker.reportWatched(
        provider: 'p',
        contentUrl: 'u',
        title: 'Vikings',
        isSerial: true,
        episode: 11,
        progress: 60,
      );
      expect(ok, isTrue);
      final (action, body) = api.scrobbles.single;
      expect(action, 'stop');
      expect(body['episode'], {'season': 2, 'number': 2});
      expect(body['progress'], greaterThanOrEqualTo(80));
    });

    test('a stop that does not land is sent later as history', () async {
      api.failScrobble = true;
      final ok = await tracker.reportWatched(
        provider: 'p',
        contentUrl: 'u',
        title: 'Vikings',
        isSerial: true,
        episode: 3,
      );
      expect(ok, isFalse);
      expect(outbox.pending(TraktTracker.outboxName), hasLength(1));

      await outbox.flush(force: true);
      final show = (api.written.single['shows'] as List).single as Map;
      expect(show['ids'], {'trakt': 7});
      final season = (show['seasons'] as List).single as Map;
      expect(season['number'], 1);
      expect(((season['episodes'] as List).single as Map)['number'], 3);
      expect(outbox.pending(TraktTracker.outboxName), isEmpty);
    });

    test('an unmatched title sends nothing', () async {
      api.found = [];
      await tracker.scrobble(
        'start',
        provider: 'p',
        contentUrl: 'other',
        title: 'Nothing like it',
        isSerial: true,
        episode: 1,
        progress: 3,
      );
      expect(api.scrobbles, isEmpty);
    });
  });
}
