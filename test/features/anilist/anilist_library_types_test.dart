import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/anilist/data/anilist_api.dart';
import 'package:soplay/features/anilist/domain/entities/anilist_entities.dart';

/// The library read as a reader sees it.
///
/// Every failure guarded here is silent by nature: a list query that keeps
/// asking for ANIME returns an empty collection rather than an error, and a
/// manga row whose total is looked for under `episodes` renders a progress bar
/// stuck at zero and a count with nothing to divide by. Both look like an
/// account with nothing on it rather than like a bug.
void main() {
  group('AnilistApi.mediaList', () {
    test('asks for ANIME unless told otherwise', () async {
      final adapter = _Adapter(body: _collection(const []));
      final api = AnilistApi(dio: _dio(adapter));

      await api.mediaList(token: 't', userId: 7);

      final sent = adapter.requests.single.data as Map;
      expect(
        sent['variables'],
        {'userId': 7, 'type': 'ANIME'},
        reason: 'every caller that existed before the split still gets anime',
      );
    });

    test('carries MANGA through to the collection argument', () async {
      final adapter = _Adapter(body: _collection(const []));
      final api = AnilistApi(dio: _dio(adapter));

      await api.mediaList(token: 't', userId: 7, type: 'MANGA');

      final sent = adapter.requests.single.data as Map;
      expect((sent['variables'] as Map)['type'], 'MANGA');
      // The point of the whole change: the document must take the type as a
      // variable, because a literal one ignores whatever was passed.
      expect(sent['query'], contains(r'$type: MediaType'));
      expect(sent['query'], isNot(contains('type: ANIME')));
    });

    test('maps a chapter-shaped entry into a usable row', () async {
      final adapter = _Adapter(
        body: _collection([
          {
            'id': 91,
            'status': 'CURRENT',
            'progress': 12,
            'media': {
              'id': 3001,
              'type': 'MANGA',
              'format': 'MANGA',
              'chapters': 48,
              'volumes': 9,
              'title': {'romaji': 'Yotsuba to!'},
            },
          },
        ]),
      );
      final api = AnilistApi(dio: _dio(adapter));

      final entries = await api.mediaList(
        token: 't',
        userId: 7,
        type: 'MANGA',
      );

      expect(entries, hasLength(1));
      final entry = entries.single;
      expect(entry.media.episodes, isNull);
      expect(entry.completion, closeTo(0.25, 1e-9));
      expect(entry.progressLabel, '12 / 48');
      // 9 volumes must not become the denominator: AniList counts a reader's
      // position in chapters, so volumes would read "12 / 9" and a bar pinned
      // full at chapter 10 of 48.
      expect(entry.media.totalUnits, 48);
    });
  });

  group('AnilistListEntry on a manga', () {
    AnilistListEntry entry({
      required int progress,
      int? chapters,
      int? volumes,
    }) => AnilistListEntry(
      id: 1,
      media: AnilistMedia(
        id: 1,
        type: 'MANGA',
        chapters: chapters,
        volumes: volumes,
      ),
      status: AnilistStatus.current.value,
      progress: progress,
    );

    test('a serialising title with no announced total shows no bar', () {
      // AniList publishes `chapters` only once it knows the total. A guessed
      // denominator here would be a bar that moves for reasons of its own.
      final e = entry(progress: 40, chapters: null, volumes: 4);
      expect(e.completion, isNull);
      expect(e.progressLabel, '40');
      expect(e.behindBy, 0);
      expect(e.nextEpisode, 41, reason: 'there is always another chapter');
    });

    test('a finished title counts to its last chapter', () {
      final e = entry(progress: 48, chapters: 48);
      expect(e.completion, 1.0);
      expect(e.progressLabel, '48 / 48');
      expect(e.nextEpisode, isNull);
      expect(e.behindBy, 0);
    });

    test('unread chapters count the same way unwatched episodes do', () {
      expect(entry(progress: 12, chapters: 48).behindBy, 36);
    });
  });

  group('AnilistListEntry on an anime is unchanged', () {
    AnilistListEntry entry({
      required int progress,
      int? episodes,
      AnilistAiring? airing,
    }) => AnilistListEntry(
      id: 1,
      media: AnilistMedia(
        id: 1,
        type: 'ANIME',
        episodes: episodes,
        nextAiring: airing,
      ),
      status: AnilistStatus.current.value,
      progress: progress,
    );

    test('completion and the count read off episodes', () {
      final e = entry(progress: 6, episodes: 12);
      expect(e.completion, 0.5);
      expect(e.progressLabel, '6 / 12');
      expect(e.nextEpisode, 7);
    });

    test('an airing show is still capped at what has aired', () {
      final e = entry(
        progress: 5,
        episodes: 24,
        airing: const AnilistAiring(episode: 6, airingAt: 4102444800),
      );
      expect(e.nextEpisode, isNull);
      expect(e.behindBy, 0);
      expect(
        e.completion,
        closeTo(5 / 24, 1e-9),
        reason: 'the bar measures the season, not what has aired',
      );
    });

    test('a total of none leaves a bare count', () {
      expect(entry(progress: 3).progressLabel, '3');
      expect(entry(progress: 3).completion, isNull);
    });
  });

  group('AnilistLibraryKind', () {
    AnilistMedia media(String type, String? format) =>
        AnilistMedia(id: 1, type: type, format: format);

    test('novels come out of the manga collection, not the manga shelf', () {
      final novel = media('MANGA', 'NOVEL');
      expect(AnilistLibraryKind.novel.matches(novel), isTrue);
      expect(
        AnilistLibraryKind.manga.matches(novel),
        isFalse,
        reason: 'a novel listed twice is the bug this split exists to avoid',
      );
      expect(AnilistLibraryKind.anime.matches(novel), isFalse);
    });

    test('a one-shot or a manga belongs to the manga shelf alone', () {
      for (final format in ['MANGA', 'ONE_SHOT', null]) {
        final m = media('MANGA', format);
        expect(AnilistLibraryKind.manga.matches(m), isTrue);
        expect(AnilistLibraryKind.novel.matches(m), isFalse);
        expect(
          AnilistLibraryKind.anime.matches(m),
          isFalse,
          reason: 'a manga on the anime shelf is the whole bug this splits',
        );
      }
    });

    test('every anime format stays on the anime shelf', () {
      for (final format in ['TV', 'MOVIE', 'OVA', null]) {
        final m = media('ANIME', format);
        expect(AnilistLibraryKind.anime.matches(m), isTrue);
        expect(AnilistLibraryKind.manga.matches(m), isFalse);
        expect(AnilistLibraryKind.novel.matches(m), isFalse);
      }
    });

    test('each shelf knows which media type to ask AniList for', () {
      expect(AnilistLibraryKind.anime.mediaType, 'ANIME');
      expect(AnilistLibraryKind.manga.mediaType, 'MANGA');
      expect(
        AnilistLibraryKind.novel.mediaType,
        'MANGA',
        reason: 'AniList has no NOVEL type; asking for one is an error',
      );
    });
  });
}

String _collection(List<Map<String, dynamic>> entries) => jsonEncode({
  'data': {
    'MediaListCollection': {
      'lists': [
        {'entries': entries},
      ],
    },
  },
});

Dio _dio(_Adapter adapter) => Dio()..httpClientAdapter = adapter;

/// Answers every request with one body, and keeps what it was asked.
class _Adapter implements HttpClientAdapter {
  _Adapter({required this.body});

  final String body;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
