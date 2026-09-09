import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/trailer/trailer_query.dart';
import 'package:soplay/core/trailer/trailer_title_lookup.dart';

void main() {
  group('TrailerTitleLookup', () {
    test('a title is asked for once, however many widgets want it', () async {
      final adapter = _Adapter(body: _found('MGRm4IzK1SQ'));
      final lookup = TrailerTitleLookup(dio: _dio(adapter));

      final button = lookup.youtubeIdFor(_query('Attack on Titan'));
      final preview = lookup.youtubeIdFor(_query('Attack on Titan'));

      expect(await button, 'MGRm4IzK1SQ');
      expect(await preview, 'MGRm4IzK1SQ');
      expect(
        adapter.requests,
        hasLength(1),
        reason: 'the second caller waits on the first request, not a new one',
      );
    });

    test('an answer already given is not asked for again', () async {
      final adapter = _Adapter(body: _found('abc123'));
      final lookup = TrailerTitleLookup(dio: _dio(adapter));

      await lookup.youtubeIdFor(_query('Dune'));
      await lookup.youtubeIdFor(_query('Dune'));

      expect(adapter.requests, hasLength(1));
    });

    test('"no trailer" is an answer and is remembered', () async {
      // The case this exists for: most titles on a scraper have none, and
      // without remembering it every page opening the button and the header
      // preview asks again for a name TMDB has already refused.
      final adapter = _Adapter(body: '{"trailer":null}');
      final lookup = TrailerTitleLookup(dio: _dio(adapter));

      expect(await lookup.youtubeIdFor(_query('Arosat')), isNull);
      expect(await lookup.youtubeIdFor(_query('Arosat')), isNull);
      expect(adapter.requests, hasLength(1));
    });

    test('a request that fails is not remembered as "no trailer"', () async {
      // A dropped connection says nothing about the title. Remembering it
      // would cost the title its trailer until the app restarted.
      final adapter = _Adapter(status: 502);
      final lookup = TrailerTitleLookup(dio: _dio(adapter));

      expect(await lookup.youtubeIdFor(_query('Dune')), isNull);
      expect(await lookup.youtubeIdFor(_query('Dune')), isNull);
      expect(adapter.requests, hasLength(2));
    });

    test('isSerial picks the type, and the year narrows the search', () async {
      final adapter = _Adapter(body: _found('x1'));
      final lookup = TrailerTitleLookup(dio: _dio(adapter));

      await lookup.youtubeIdFor(
        const TrailerQuery(title: 'Shogun', year: 2024, isSerial: true),
      );
      await lookup.youtubeIdFor(
        const TrailerQuery(title: 'Shogun', year: 1980, isSerial: false),
      );

      expect(adapter.requests[0].queryParameters,
          {'title': 'Shogun', 'year': 2024, 'type': 'tv'});
      expect(adapter.requests[1].queryParameters,
          {'title': 'Shogun', 'year': 1980, 'type': 'movie'});
    });

    test('a year the provider does not publish is left off', () async {
      final adapter = _Adapter(body: _found('x1'));
      final lookup = TrailerTitleLookup(dio: _dio(adapter));

      await lookup.youtubeIdFor(_query('Dune'));

      expect(adapter.requests.single.queryParameters.containsKey('year'),
          isFalse);
    });

    test('casing and stray spaces are the same title', () async {
      final adapter = _Adapter(body: _found('x1'));
      final lookup = TrailerTitleLookup(dio: _dio(adapter));

      await lookup.youtubeIdFor(_query('Attack on Titan'));
      await lookup.youtubeIdFor(_query('  attack  on   titan '));

      expect(adapter.requests, hasLength(1));
    });

    test('a title too short for the endpoint never leaves the device',
        () async {
      final adapter = _Adapter(body: _found('x1'));
      final lookup = TrailerTitleLookup(dio: _dio(adapter));

      expect(await lookup.youtubeIdFor(_query('X')), isNull);
      expect(adapter.requests, isEmpty);
    });

    test('anything that is not the documented shape reads as no trailer', () {
      expect(TrailerTitleLookup.youtubeIdFrom(null), isNull);
      expect(TrailerTitleLookup.youtubeIdFrom('<html>502</html>'), isNull);
      expect(TrailerTitleLookup.youtubeIdFrom({'trailer': null}), isNull);
      expect(TrailerTitleLookup.youtubeIdFrom({'trailer': 'MGRm4IzK1SQ'}),
          isNull);
      expect(
        TrailerTitleLookup.youtubeIdFrom({
          'trailer': {'youtubeId': 42},
        }),
        isNull,
      );
      expect(
        TrailerTitleLookup.youtubeIdFrom({
          'trailer': {'youtubeId': '  '},
        }),
        isNull,
      );
      expect(
        TrailerTitleLookup.youtubeIdFrom({
          'trailer': {'youtubeId': ' MGRm4IzK1SQ ', 'official': true},
        }),
        'MGRm4IzK1SQ',
      );
    });
  });

  group('TrailerQuery', () {
    test('two queries built from the same title are equal', () {
      // What stops the header preview tearing the playing trailer down: the
      // detail header rebuilds on every scroll frame and hands the preview a
      // freshly built query each time.
      const a = TrailerQuery(title: 'Dune', year: 2021, isSerial: false);
      const b = TrailerQuery(title: 'Dune', year: 2021, isSerial: false);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('a different title, year, type or id is a different query', () {
      const base = TrailerQuery(title: 'Dune', year: 2021, isSerial: false);

      expect(base,
          isNot(const TrailerQuery(title: 'Dune', year: 1984, isSerial: false)));
      expect(base,
          isNot(const TrailerQuery(title: 'Dune', year: 2021, isSerial: true)));
      expect(
        base,
        isNot(const TrailerQuery(
          title: 'Dune',
          year: 2021,
          isSerial: false,
          youtubeId: 'abc',
        )),
      );
    });
  });
}

TrailerQuery _query(String title) =>
    TrailerQuery(title: title, year: null, isSerial: false);

String _found(String id) => jsonEncode({
      'trailer': {'youtubeId': id, 'official': true},
      'match': {'tmdbId': 1429, 'score': 1},
    });

Dio _dio(_Adapter adapter) =>
    Dio(BaseOptions(baseUrl: 'https://api.example'))
      ..httpClientAdapter = adapter;

/// Answers every request with one body, and keeps what it was asked.
class _Adapter implements HttpClientAdapter {
  _Adapter({this.body = '', this.status = 200});

  final String body;
  final int status;
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
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
