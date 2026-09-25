import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/player/local_hls_proxy.dart';

void main() {
  group('LocalHlsProxy', () {
    late _MockUpstream upstream;
    late LocalHlsProxy proxy;
    late Dio dio;

    setUp(() async {
      upstream = await _MockUpstream.start();
      dio = Dio(BaseOptions(validateStatus: (_) => true));
      proxy = LocalHlsProxy(dio);
    });

    tearDown(() async {
      await proxy.dispose();
      await upstream.close();
      dio.close(force: true);
    });

    test('does not forward Origin to upstream', () async {
      upstream.respond(
        path: '/cdn/manifest/video/x.m3u8',
        contentType: 'application/vnd.apple.mpegurl',
        body: '#EXTM3U\n#EXT-X-VERSION:3\n',
      );

      final loopback = await proxy.register(
        upstreamUrl:
            '${upstream.origin}/cdn/manifest/video/x.m3u8?sec=token123',
        headers: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 13)',
          'Referer': 'https://www.dailymotion.com/',
          'Origin': 'https://www.dailymotion.com',
        },
      );

      final body = await _httpGetString(loopback);
      expect(body, contains('#EXTM3U'));

      final received = upstream.lastHeaders;
      expect(received, isNotNull);
      expect(
        received!.containsKey('origin'),
        isFalse,
        reason: 'Origin must be stripped before sending upstream',
      );
      expect(
        received.containsKey('referer'),
        isFalse,
        reason: 'Referer must be stripped before sending upstream',
      );
      expect(received['user-agent'], contains('Android'));
    });

    test('rewrites same-host playlist URIs to loopback paths', () async {
      upstream.respond(
        path: '/cdn/manifest/video/x.m3u8',
        contentType: 'application/vnd.apple.mpegurl',
        body:
            '#EXTM3U\n'
            '#EXT-X-STREAM-INF:BANDWIDTH=800000\n'
            '${upstream.origin}/cdn/manifest/video/variant_low.m3u8?sec=tok\n'
            '#EXT-X-STREAM-INF:BANDWIDTH=2000000\n'
            'variant_high.m3u8\n',
      );

      final loopback = await proxy.register(
        upstreamUrl: '${upstream.origin}/cdn/manifest/video/x.m3u8?sec=tok',
        headers: const {'User-Agent': 'test'},
      );

      final body = await _httpGetString(loopback);

      final loopbackUri = Uri.parse(loopback);
      final base = '/hls/${loopbackUri.pathSegments[1]}';
      expect(
        body,
        contains('$base/cdn/manifest/video/variant_low.m3u8?sec=tok'),
      );
      expect(body, contains('$base/cdn/manifest/video/variant_high.m3u8'));
    });

    test('rewrites cross-host segment URIs into base64 _h/ form', () async {
      const altAuthority = 'vod3.dmcdn.net';
      upstream.respond(
        path: '/cdn/manifest/video/x.m3u8',
        contentType: 'application/vnd.apple.mpegurl',
        body:
            '#EXTM3U\n'
            '#EXT-X-STREAM-INF:BANDWIDTH=1000000\n'
            'https://$altAuthority/seg/720p.m3u8?t=1\n',
      );

      final loopback = await proxy.register(
        upstreamUrl: '${upstream.origin}/cdn/manifest/video/x.m3u8',
        headers: const {'User-Agent': 'test'},
      );

      final body = await _httpGetString(loopback);
      final expectedTag = base64UrlEncode(
        utf8.encode(altAuthority),
      ).replaceAll('=', '');
      expect(body, contains('/_h/$expectedTag/seg/720p.m3u8?t=1'));
    });

    test('forwards binary segment bytes verbatim', () async {
      final segmentBytes = List<int>.generate(256, (i) => i % 256);
      upstream.respond(
        path: '/cdn/manifest/video/x.m3u8',
        contentType: 'application/vnd.apple.mpegurl',
        body: '#EXTM3U\nseg0.ts\n',
      );
      upstream.respondBytes(
        path: '/cdn/manifest/video/seg0.ts',
        contentType: 'video/MP2T',
        body: segmentBytes,
      );

      final loopback = await proxy.register(
        upstreamUrl: '${upstream.origin}/cdn/manifest/video/x.m3u8',
        headers: const {'User-Agent': 'test'},
      );

      final manifestBody = await _httpGetString(loopback);
      final loopbackUri = Uri.parse(loopback);
      final sid = loopbackUri.pathSegments[1];
      expect(manifestBody, contains('/hls/$sid/cdn/manifest/video/seg0.ts'));

      final base = 'http://127.0.0.1:${loopbackUri.port}';
      final segBytes = await _httpGetBytes(
        '$base/hls/$sid/cdn/manifest/video/seg0.ts',
      );
      expect(segBytes, equals(segmentBytes));
    });

    test('forwards range requests and preserves 206 response', () async {
      final segmentBytes = List<int>.generate(10, (i) => i + 10);
      upstream.respondBytes(
        path: '/cdn/manifest/video/seg0.ts',
        status: 206,
        contentType: 'video/MP2T',
        headers: const {
          'content-range': 'bytes 10-19/100',
          'accept-ranges': 'bytes',
          'content-length': '10',
        },
        body: segmentBytes,
      );

      final loopback = await proxy.register(
        upstreamUrl: '${upstream.origin}/cdn/manifest/video/x.m3u8',
        headers: const {'User-Agent': 'test'},
      );
      final loopbackUri = Uri.parse(loopback);
      final sid = loopbackUri.pathSegments[1];
      final base = 'http://127.0.0.1:${loopbackUri.port}';

      final response = await _httpGetBytesWithHeaders(
        '$base/hls/$sid/cdn/manifest/video/seg0.ts',
        headers: const {'Range': 'bytes=10-19'},
      );

      expect(upstream.lastHeaders?['range'], 'bytes=10-19');
      expect(response.statusCode, 206);
      expect(response.headers['content-range'], 'bytes 10-19/100');
      expect(response.headers['accept-ranges'], 'bytes');
      expect(response.bytes, equals(segmentBytes));
    });

    test('applies uzmovi rc4 transform per upstream request', () async {
      final menuData = base64.encode(utf8.encode('menu-data'));
      upstream.respondWhere(
        matches: (uri) {
          final parts = uri.pathSegments;
          return parts.length == 2 &&
              parts[0].length == 30 &&
              parts[1].length == 14 &&
              parts[1].endsWith('.mpd');
        },
        contentType: 'application/vnd.apple.mpegurl',
        body: '#EXTM3U\nseg0.ts\n',
      );

      final loopback = await proxy.register(
        upstreamUrl: '${upstream.origin}/live/show/index.m3u8',
        headers: const {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 13)',
          'Origin': 'https://uzmovi.net',
          'Referer': 'https://uzmovi.net/movie.html',
        },
        localProxy: {
          'transform': 'uzmovi-rc4-v1',
          'targetHost': Uri.parse(upstream.origin).host,
        },
        requestTransform: {
          'type': 'uzmovi-rc4-v1',
          'pageHost': 'uzmovi.net',
          'menuData': menuData,
          'randomPath': {'first': 30, 'second': 10, 'extension': '.mpd'},
          'headerNames': {
            'deviceId': 'X-ATT-DeviceId',
            'match': 'X-Match',
            'path': 'X-Path',
          },
        },
      );

      final body = await _httpGetString(loopback);
      final loopbackUri = Uri.parse(loopback);
      final sid = loopbackUri.pathSegments[1];
      expect(body, contains('/hls/$sid/live/show/seg0.ts'));

      final received = upstream.lastHeaders;
      expect(received, isNotNull);
      expect(received!['origin'], 'https://uzmovi.net');
      expect(received['referer'], 'https://uzmovi.net/movie.html');
      expect(
        received['x-att-deviceid'],
        base64.encode(_rc4Bytes('movie', base64.decode(menuData))),
      );
      expect(received['x-path']?.length, 40);

      final matchHeader = received['x-match'];
      expect(matchHeader, isNotNull);
      final decodedMatch = utf8.decode(
        _rc4Bytes('uzmovi.net', base64.decode(matchHeader!)),
      );
      final matchJson = jsonDecode(decodedMatch) as Map<String, dynamic>;
      expect(matchJson['path'], '/live/show/index.m3u8');
      expect(matchJson['time'], isA<num>());
      expect(upstream.lastUri?.path, isNot('/live/show/index.m3u8'));
    });

    test('percent-encodes spaces in loopback + rewritten paths', () async {
      // uzdown paths contain literal spaces (".../uzmovi.com kichina .../…").
      // The player URL and every rewritten manifest URL must be percent-encoded
      // or desktop libmpv refuses to open them (mobile players tolerate spaces).
      // The proxy always fetches upstream with the encoded path, so the mock
      // routes are keyed encoded; the manifest BODY keeps a raw space to prove
      // the rewrite encodes it.
      upstream.respond(
        path: '/live/movie%20hd/index.m3u8',
        contentType: 'application/vnd.apple.mpegurl',
        body: '#EXTM3U\nseg 0.ts\n',
      );
      upstream.respondBytes(
        path: '/live/movie%20hd/seg%200.ts',
        contentType: 'video/MP2T',
        body: const [1, 2, 3, 4],
      );

      final loopback = await proxy.register(
        upstreamUrl: '${upstream.origin}/live/movie%20hd/index.m3u8',
        headers: const {'User-Agent': 'test'},
      );

      // register() hands the player an encoded URL — never a raw space.
      expect(loopback, isNot(contains(' ')));
      expect(loopback, contains('/live/movie%20hd/index.m3u8'));

      final body = await _httpGetString(loopback);
      final loopbackUri = Uri.parse(loopback);
      final sid = loopbackUri.pathSegments[1];
      // The rewritten segment line is encoded, not left with a raw space.
      expect(body, contains('/hls/$sid/live/movie%20hd/seg%200.ts'));
      expect(body, isNot(contains('seg 0.ts')));

      // …and the encoded segment URL still round-trips to the decoded upstream.
      final base = 'http://127.0.0.1:${loopbackUri.port}';
      final segBytes = await _httpGetBytes(
        '$base/hls/$sid/live/movie%20hd/seg%200.ts',
      );
      expect(segBytes, equals(const [1, 2, 3, 4]));
    });

    test('returns 410 for unknown session id', () async {
      await proxy.register(
        upstreamUrl: '${upstream.origin}/cdn/manifest/video/x.m3u8?sec=tok',
        headers: const {'User-Agent': 'test'},
      );
      final port = proxy.debugPort;
      final res = await _httpGetStatus(
        'http://127.0.0.1:$port/hls/deadbeef/cdn/manifest/video/x.m3u8',
      );
      expect(res, 410);
    });

    test('returns upstream status code on 4xx', () async {
      upstream.respondStatus(path: '/cdn/manifest/video/x.m3u8', status: 403);

      final loopback = await proxy.register(
        upstreamUrl: '${upstream.origin}/cdn/manifest/video/x.m3u8',
        headers: const {'User-Agent': 'test'},
      );
      final status = await _httpGetStatus(loopback);
      expect(status, 403);
    });

    test('a DASH manifest comes back with one video rendition and proxied '
        'addresses', () async {
      upstream.respond(
        path: '/v/stream.mpd',
        contentType: 'application/dash+xml',
        body: _mpd('https://other.cdn.test/seg/'),
      );
      final loopback = await proxy.register(
        upstreamUrl: '${upstream.origin}/v/stream.mpd',
        headers: {'User-Agent': 'x'},
        dashRepresentation: 'v720',
      );
      final body = await _httpGetString(loopback);
      expect(body, contains('id="v720"'));
      expect(body, isNot(contains('id="v1080"')));
      expect(body, isNot(contains('id="v480"')));
      // Audio is left alone.
      expect(body, contains('id="a1"'));
      // An absolute BaseURL points back at the proxy, so segments carry the
      // stream's headers.
      expect(body, isNot(contains('https://other.cdn.test')));
      expect(body, contains('/hls/'));
    });
  });
}

class _MockUpstream {
  _MockUpstream._(this._server);

  final HttpServer _server;
  final Map<String, _MockResponse> _routes = {};
  final List<_MockMatcher> _matchers = [];
  Map<String, String>? lastHeaders;
  Uri? lastUri;

  String get origin => 'http://${_server.address.host}:${_server.port}';

  static Future<_MockUpstream> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final mock = _MockUpstream._(server);
    server.listen(mock._handle);
    return mock;
  }

  void respond({
    required String path,
    required String body,
    String? contentType,
  }) {
    _routes[path] = _MockResponse(
      status: 200,
      bytes: utf8.encode(body),
      contentType: contentType,
    );
  }

  void respondBytes({
    required String path,
    required List<int> body,
    int status = 200,
    String? contentType,
    Map<String, String> headers = const {},
  }) {
    _routes[path] = _MockResponse(
      status: status,
      bytes: body,
      contentType: contentType,
      headers: headers,
    );
  }

  void respondStatus({required String path, required int status}) {
    _routes[path] = _MockResponse(status: status, bytes: const []);
  }

  void respondWhere({
    required bool Function(Uri uri) matches,
    required String body,
    String? contentType,
  }) {
    _matchers.add(
      _MockMatcher(
        matches: matches,
        response: _MockResponse(
          status: 200,
          bytes: utf8.encode(body),
          contentType: contentType,
        ),
      ),
    );
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest req) async {
    lastHeaders = {};
    lastUri = req.uri;
    req.headers.forEach((name, values) {
      lastHeaders![name.toLowerCase()] = values.join(',');
    });
    var route = _routes[req.uri.path];
    if (route == null) {
      for (final matcher in _matchers) {
        if (matcher.matches(req.uri)) {
          route = matcher.response;
          break;
        }
      }
    }
    if (route == null) {
      req.response.statusCode = 404;
      await req.response.close();
      return;
    }
    req.response.statusCode = route.status;
    if (route.contentType != null) {
      req.response.headers.set(
        HttpHeaders.contentTypeHeader,
        route.contentType!,
      );
    }
    route.headers.forEach(req.response.headers.set);
    req.response.add(route.bytes);
    await req.response.close();
  }
}

class _MockResponse {
  _MockResponse({
    required this.status,
    required this.bytes,
    this.contentType,
    this.headers = const {},
  });

  final int status;
  final List<int> bytes;
  final String? contentType;
  final Map<String, String> headers;
}

class _MockMatcher {
  _MockMatcher({required this.matches, required this.response});

  final bool Function(Uri uri) matches;
  final _MockResponse response;
}

Future<String> _httpGetString(String url) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url));
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    return body;
  } finally {
    client.close();
  }
}

Future<List<int>> _httpGetBytes(String url) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url));
    final res = await req.close();
    final out = <int>[];
    await for (final chunk in res) {
      out.addAll(chunk);
    }
    return out;
  } finally {
    client.close();
  }
}

Future<_HttpBytesResponse> _httpGetBytesWithHeaders(
  String url, {
  Map<String, String> headers = const {},
}) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url));
    headers.forEach(req.headers.set);
    final res = await req.close();
    final out = <int>[];
    await for (final chunk in res) {
      out.addAll(chunk);
    }
    final responseHeaders = <String, String>{};
    res.headers.forEach((name, values) {
      responseHeaders[name.toLowerCase()] = values.join(',');
    });
    return _HttpBytesResponse(
      statusCode: res.statusCode,
      headers: responseHeaders,
      bytes: out,
    );
  } finally {
    client.close();
  }
}

class _HttpBytesResponse {
  const _HttpBytesResponse({
    required this.statusCode,
    required this.headers,
    required this.bytes,
  });

  final int statusCode;
  final Map<String, String> headers;
  final List<int> bytes;
}

Future<int> _httpGetStatus(String url) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url));
    final res = await req.close();
    await res.drain<void>();
    return res.statusCode;
  } finally {
    client.close();
  }
}

List<int> _rc4Bytes(String key, List<int> input) {
  final keyBytes = utf8.encode(key);
  final state = List<int>.generate(256, (i) => i);
  var j = 0;
  for (var i = 0; i < 256; i++) {
    j = (j + state[i] + keyBytes[i % keyBytes.length]) & 0xff;
    final tmp = state[i];
    state[i] = state[j];
    state[j] = tmp;
  }

  final out = List<int>.filled(input.length, 0);
  var i = 0;
  j = 0;
  for (var n = 0; n < input.length; n++) {
    i = (i + 1) & 0xff;
    j = (j + state[i]) & 0xff;
    final tmp = state[i];
    state[i] = state[j];
    state[j] = tmp;
    final k = state[(state[i] + state[j]) & 0xff];
    out[n] = input[n] ^ k;
  }
  return out;
}

String _mpd(String base) =>
    '''<?xml version="1.0"?>
<MPD xmlns="urn:mpeg:dash:schema:mpd:2011" type="static">
  <Period>
    <BaseURL>$base</BaseURL>
    <AdaptationSet mimeType="video/mp4">
      <Representation id="v1080" width="1920" height="1080" bandwidth="5000000"/>
      <Representation id="v720" width="1280" height="720" bandwidth="2500000"/>
      <Representation id="v480" width="854" height="480" bandwidth="1000000"/>
    </AdaptationSet>
    <AdaptationSet mimeType="audio/mp4">
      <Representation id="a1" bandwidth="128000"/>
    </AdaptationSet>
  </Period>
</MPD>''';
