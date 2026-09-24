import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/recap/data/recap_remote_data_source.dart';
import 'package:soplay/features/recap/domain/recap.dart';

void main() {
  const request = RecapRequest(
    provider: 'asilmedia',
    contentUrl: 'https://example.com/show',
    title: 'Show',
    episode: 6,
    label: '2-fasl 5-qism',
    tmdbId: 1399,
    fallbackEpisode: 5,
  );

  test('asks with the ids, episode, label and language', () async {
    final adapter = _Adapter((_) => (200, _ok(6)));
    final source = RecapRemoteDataSource(dio: _dio(adapter));

    final recap = await source.load(request, lang: 'uz');

    expect(recap.text, 'Recap before 6');
    expect(adapter.requests.single.path, '/contents/recap');
    expect(adapter.requests.single.queryParameters, {
      'provider': 'asilmedia',
      'url': 'https://example.com/show',
      'episode': 6,
      'label': '2-fasl 5-qism',
      'tmdbId': 1399,
      'lang': 'uz',
    });
  });

  test('an answer is remembered for the session', () async {
    final adapter = _Adapter((_) => (200, _ok(6)));
    final source = RecapRemoteDataSource(dio: _dio(adapter));

    await source.load(request, lang: 'en');
    await source.load(request, lang: 'en');

    expect(adapter.requests, hasLength(1));
    expect(source.peek(request, lang: 'en'), isNotNull);
    expect(source.peek(request, lang: 'ru'), isNull);
  });

  test('no_data for the next episode falls back to the finished one', () async {
    final adapter = _Adapter((o) {
      final ep = o.queryParameters['episode'];
      return ep == 6 ? (404, _noData) : (200, _ok(5));
    });
    final source = RecapRemoteDataSource(dio: _dio(adapter));

    final recap = await source.load(request, lang: 'en');

    expect(recap.text, 'Recap before 5');
    expect(adapter.requests.map((r) => r.queryParameters['episode']), [6, 5]);
  });

  test('no_data with nothing to fall back to is unavailable', () async {
    final adapter = _Adapter((_) => (404, _noData));
    final source = RecapRemoteDataSource(dio: _dio(adapter));

    await expectLater(
      source.load(request.withEpisode(3), lang: 'en'),
      throwsA(isA<RecapUnavailable>()),
    );
  });

  test('a 200 with no text is unavailable, not an empty page', () async {
    final adapter = _Adapter((_) => (200, '{"text":""}'));
    final source = RecapRemoteDataSource(dio: _dio(adapter));

    await expectLater(
      source.load(request.withEpisode(3), lang: 'en'),
      throwsA(isA<RecapUnavailable>()),
    );
  });

  test('a server failure is retryable and not remembered', () async {
    var fail = true;
    final adapter = _Adapter((_) => fail ? (502, '{}') : (200, _ok(3)));
    final source = RecapRemoteDataSource(dio: _dio(adapter));
    final r = request.withEpisode(3);

    await expectLater(source.load(r, lang: 'en'), throwsA(isA<DioException>()));
    fail = false;
    final recap = await source.load(r, lang: 'en');
    expect(recap.text, 'Recap before 3');
    expect(adapter.requests, hasLength(2));
  });

  test('isUnavailable only for the server\'s "there is none"', () {
    expect(
      RecapRemoteDataSource.isUnavailable(404, {'reason': 'no_data'}),
      isTrue,
    );
    expect(
      RecapRemoteDataSource.isUnavailable(400, {'reason': 'bad_request'}),
      isTrue,
    );
    expect(RecapRemoteDataSource.isUnavailable(404, 'Not found'), isFalse);
    expect(RecapRemoteDataSource.isUnavailable(400, {'message': 'x'}), isFalse);
    expect(RecapRemoteDataSource.isUnavailable(500, null), isFalse);
  });
}

const _noData = '{"reason":"no_data","message":"none"}';

String _ok(int episode) => jsonEncode({
  'title': 'Show',
  'season': 2,
  'episode': episode,
  'upToEpisode': episode - 1,
  'attribution': 'TMDB',
  'items': [],
  'lang': 'en',
  'source': 'stitched',
  'text': 'Recap before $episode',
});

Dio _dio(HttpClientAdapter adapter) =>
    Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = adapter;

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);

  final (int, String) Function(RequestOptions) respond;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final (status, body) = respond(options);
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
