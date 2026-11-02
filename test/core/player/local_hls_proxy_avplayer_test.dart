import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/player/local_hls_proxy.dart';

/// The proxy as AVPlayer uses it.
///
/// On iOS the stream is played by AVPlayer through video_player_avfoundation —
/// `resolvePlayerEngine()` pins every non-Android, non-desktop platform to the
/// native engine because there is no libmpv there. AVFoundation's media loader
/// is far stricter than libmpv or ExoPlayer: it probes with HEAD, it opens a
/// segment with a byte range and insists on 206 plus a matching Content-Range,
/// it re-requests the same bytes, and it gives up with an opaque
/// "cannot open" when any of that is wrong. Each case below is one of those
/// requests, so a regression shows up here rather than on a device.
void main() {
  group('LocalHlsProxy under AVPlayer-shaped requests', () {
    late _RangeUpstream upstream;
    late LocalHlsProxy proxy;
    late Dio dio;

    setUp(() async {
      upstream = await _RangeUpstream.start();
      dio = Dio(BaseOptions(validateStatus: (_) => true));
      proxy = LocalHlsProxy(dio);
    });

    tearDown(() async {
      await proxy.dispose();
      await upstream.close();
      dio.close(force: true);
    });

    Future<String> registerSegmentSession() => proxy.register(
      upstreamUrl: '${upstream.origin}/live/index.m3u8',
      headers: const {'Referer': 'https://uzmovi.net/'},
      keepOriginHeaders: true,
    );

    test('HEAD on a playlist answers with no body but a usable header', () async {
      final url = await registerSegmentSession();
      final res = await _request(url, method: 'HEAD');
      expect(res.statusCode, 200);
      expect(res.headers['content-type'], contains('mpegurl'));
      expect(res.bytes, isEmpty, reason: 'A HEAD must not carry a body');
      expect(res.headers['content-length'], isNotNull);
      expect(
        int.parse(res.headers['content-length']!),
        greaterThan(0),
        reason: 'AVPlayer sizes the resource from this',
      );
    });

    test('a ranged playlist request is answered from the rewritten bytes', () async {
      final url = await registerSegmentSession();
      final whole = await _request(url);
      final total = whole.bytes.length;
      final res = await _request(url, headers: const {'Range': 'bytes=0-9'});
      expect(res.statusCode, 206);
      expect(res.headers['content-length'], '10');
      expect(
        res.headers['content-range'],
        'bytes 0-9/$total',
        reason: 'The size has to be the rewritten playlist, not the upstream one',
      );
      expect(res.bytes, whole.bytes.sublist(0, 10));
    });

    test(
      'a ranged playlist is rewritten from the whole file, not from a slice',
      () async {
        // The playlist is the one resource this proxy has to read end to end
        // before it can answer for it, so the player's Range must not reach the
        // upstream: a host that honours it hands back a few bytes of text, and
        // a rewrite of those bytes is a playlist that claims to be the whole
        // file and is not. uzmovi's signed endpoint ignores Range here, which
        // is why only a mock can hold this line.
        upstream.honourPlaylistRanges = true;
        final url = await registerSegmentSession();
        final whole = await _request(url);
        final total = whole.bytes.length;
        final res = await _request(url, headers: const {'Range': 'bytes=0-9'});
        expect(res.statusCode, 206);
        expect(
          res.headers['content-range'],
          'bytes 0-9/$total',
          reason: 'The total has to be the whole rewritten playlist',
        );
        expect(res.bytes, whole.bytes.sublist(0, 10));
        expect(
          upstream.lastPlaylistRange,
          isNull,
          reason: 'A Range forwarded to the upstream truncates the text this '
              'proxy still has to parse and rewrite',
        );
      },
    );

    test('HEAD on a segment reports the size and byte-range support', () async {
      final url = await registerSegmentSession();
      final segment = _sibling(url, 'index0.ts');
      final res = await _request(segment, method: 'HEAD');
      expect(res.statusCode, 200);
      expect(res.headers['content-type'], 'video/mp2t');
      expect(res.headers['content-length'], '${upstream.segment.length}');
      expect(res.headers['accept-ranges'], 'bytes');
      expect(res.bytes, isEmpty, reason: 'A HEAD must not carry a body');
      expect(
        upstream.lastMethod,
        'HEAD',
        reason: 'A HEAD answered by downloading the segment wastes the CDN '
            'round trip AVPlayer is trying to avoid',
      );
    });

    test('a two-byte probe range comes back as a 206 slice', () async {
      final url = await registerSegmentSession();
      final segment = _sibling(url, 'index0.ts');
      final res = await _request(
        segment,
        headers: const {'Range': 'bytes=0-1'},
      );
      expect(res.statusCode, 206);
      expect(res.headers['content-type'], 'video/mp2t');
      expect(res.headers['content-length'], '2');
      expect(
        res.headers['content-range'],
        'bytes 0-1/${upstream.segment.length}',
      );
      expect(res.headers['accept-ranges'], 'bytes');
      expect(res.bytes.length, 2);
    });

    test('an open-ended range comes back as a 206 to the end', () async {
      final url = await registerSegmentSession();
      final segment = _sibling(url, 'index0.ts');
      final res = await _request(
        segment,
        headers: const {'Range': 'bytes=0-'},
      );
      final total = upstream.segment.length;
      expect(res.statusCode, 206);
      expect(res.headers['content-length'], '$total');
      expect(res.headers['content-range'], 'bytes 0-${total - 1}/$total');
      expect(res.bytes.length, total);
    });

    test('a mid-file range comes back as the right slice', () async {
      final url = await registerSegmentSession();
      final segment = _sibling(url, 'index0.ts');
      final total = upstream.segment.length;
      final res = await _request(
        segment,
        headers: const {'Range': 'bytes=188-375'},
      );
      expect(res.statusCode, 206);
      expect(res.headers['content-length'], '188');
      expect(res.headers['content-range'], 'bytes 188-375/$total');
      expect(res.bytes, upstream.segment.sublist(188, 376));
    });

    test('a plain GET reports its length and advertises ranges', () async {
      final url = await registerSegmentSession();
      final segment = _sibling(url, 'index0.ts');
      final res = await _request(segment);
      expect(res.statusCode, 200);
      expect(res.headers['content-type'], 'video/mp2t');
      expect(res.headers['content-length'], '${upstream.segment.length}');
      expect(res.headers['accept-ranges'], 'bytes');
      expect(res.bytes.length, upstream.segment.length);
    });

    test('the same segment asked for twice answers the same both times', () async {
      final url = await registerSegmentSession();
      final segment = _sibling(url, 'index0.ts');
      final first = await _request(segment, headers: const {'Range': 'bytes=0-'});
      final second = await _request(
        segment,
        headers: const {'Range': 'bytes=0-'},
      );
      expect(second.statusCode, first.statusCode);
      expect(second.headers['content-length'], first.headers['content-length']);
      expect(second.headers['content-range'], first.headers['content-range']);
      expect(second.bytes, first.bytes);
    });

    test(
      'a range the upstream ignores is still answered as a 206 slice',
      () async {
        upstream.honourRanges = false;
        final url = await registerSegmentSession();
        final segment = _sibling(url, 'index0.ts');
        final total = upstream.segment.length;
        final res = await _request(
          segment,
          headers: const {'Range': 'bytes=0-1'},
        );
        expect(
          res.statusCode,
          206,
          reason: 'AVPlayer asked for a range, and a 200 carrying the whole '
              'file in reply is a protocol error it abandons the stream over',
        );
        expect(res.headers['content-length'], '2');
        expect(res.headers['content-range'], 'bytes 0-1/$total');
        expect(res.bytes.length, 2);
      },
    );

    test(
      'a mid-file range the upstream ignores is sliced, not sent whole',
      () async {
        upstream.honourRanges = false;
        final url = await registerSegmentSession();
        final segment = _sibling(url, 'index0.ts');
        final total = upstream.segment.length;
        final res = await _request(
          segment,
          headers: const {'Range': 'bytes=1000-1187'},
        );
        expect(res.statusCode, 206);
        expect(res.headers['content-length'], '188');
        expect(res.headers['content-range'], 'bytes 1000-1187/$total');
        expect(res.bytes, upstream.segment.sublist(1000, 1188));
      },
    );

    test('a HEAD the upstream refuses falls back to a GET', () async {
      upstream.rejectHead = true;
      final url = await registerSegmentSession();
      final segment = _sibling(url, 'index0.ts');
      final res = await _request(segment, method: 'HEAD');
      expect(
        res.statusCode,
        200,
        reason: 'Some CDNs answer 403/405 to HEAD; AVPlayer then has no size '
            'and stops, so the proxy has to ask again as a GET',
      );
      expect(res.headers['content-length'], '${upstream.segment.length}');
      expect(res.bytes, isEmpty);
    });

    test('a range past the end of the segment is refused with a 416', () async {
      upstream.honourRanges = false;
      final url = await registerSegmentSession();
      final segment = _sibling(url, 'index0.ts');
      final res = await _request(
        segment,
        headers: {'Range': 'bytes=${upstream.segment.length + 10}-'},
      );
      expect(res.statusCode, 416);
      expect(res.headers['content-range'], 'bytes */${upstream.segment.length}');
    });
  });
}

/// The playlist's address with its last path element swapped, which is where
/// the rewritten segment lines point.
String _sibling(String url, String name) {
  final uri = Uri.parse(url);
  final segments = List<String>.from(uri.pathSegments)
    ..removeLast()
    ..add(name);
  return uri.replace(pathSegments: segments).toString();
}

class _RangeUpstream {
  _RangeUpstream._(this._server);

  static Future<_RangeUpstream> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final upstream = _RangeUpstream._(server);
    server.listen(upstream._handle);
    return upstream;
  }

  final HttpServer _server;

  /// A couple of transport-stream packets, enough to slice.
  final Uint8List segment = Uint8List.fromList(
    List<int>.generate(1880, (i) => i % 188 == 0 ? 0x47 : i & 0xff),
  );

  /// When false the upstream answers every request with the whole file and a
  /// 200, the way uzmovi's signed endpoint does.
  bool honourRanges = true;

  /// When true HEAD is refused, as some CDNs do.
  bool rejectHead = false;

  /// When true the playlist is served with byte ranges honoured, the way any
  /// plain nginx or object store serves a static .m3u8. uzmovi's own signed
  /// endpoint ignores Range on the playlist, so only a mock can show what a
  /// forwarded Range does to a file this proxy has to rewrite whole.
  bool honourPlaylistRanges = false;

  String? lastMethod;
  String? lastRange;
  String? lastPlaylistRange;

  String get origin => 'http://127.0.0.1:${_server.port}';

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest req) async {
    lastMethod = req.method;
    lastRange = req.headers.value('range');
    final res = req.response;
    if (req.method == 'HEAD' && rejectHead) {
      res.statusCode = 405;
      await res.close();
      return;
    }
    if (req.uri.path.endsWith('.m3u8')) {
      lastPlaylistRange = lastRange;
      final body = utf8.encode(
        '#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:10\n'
        '#EXTINF:10.0,\nindex0.ts\n#EXTINF:10.0,\nindex1.ts\n#EXT-X-ENDLIST\n',
      );
      res.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/vnd.apple.mpegurl',
      );
      final range = honourPlaylistRanges
          ? _parseRange(lastRange, body.length)
          : null;
      if (range == null) {
        res.statusCode = 200;
        res.headers.set(HttpHeaders.contentLengthHeader, '${body.length}');
        if (req.method != 'HEAD') res.add(body);
        await res.close();
        return;
      }
      final slice = body.sublist(range.$1, range.$2 + 1);
      res.statusCode = 206;
      res.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes ${range.$1}-${range.$2}/${body.length}',
      );
      res.headers.set(HttpHeaders.contentLengthHeader, '${slice.length}');
      if (req.method != 'HEAD') res.add(slice);
      await res.close();
      return;
    }

    res.headers.set(HttpHeaders.contentTypeHeader, 'video/mp2t');
    res.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    final range = honourRanges ? _parseRange(lastRange, segment.length) : null;
    if (range == null) {
      res.statusCode = 200;
      res.headers.set(HttpHeaders.contentLengthHeader, '${segment.length}');
      if (req.method != 'HEAD') res.add(segment);
      await res.close();
      return;
    }
    final slice = segment.sublist(range.$1, range.$2 + 1);
    res.statusCode = 206;
    res.headers.set(
      HttpHeaders.contentRangeHeader,
      'bytes ${range.$1}-${range.$2}/${segment.length}',
    );
    res.headers.set(HttpHeaders.contentLengthHeader, '${slice.length}');
    if (req.method != 'HEAD') res.add(slice);
    await res.close();
  }

  (int, int)? _parseRange(String? raw, int total) {
    if (raw == null) return null;
    final m = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(raw.trim());
    if (m == null) return null;
    final startText = m.group(1)!;
    final endText = m.group(2)!;
    if (startText.isEmpty && endText.isEmpty) return null;
    if (startText.isEmpty) {
      final length = int.parse(endText);
      return (total - length, total - 1);
    }
    final start = int.parse(startText);
    final end = endText.isEmpty ? total - 1 : int.parse(endText);
    if (start > end || start >= total) return null;
    return (start, end > total - 1 ? total - 1 : end);
  }
}

Future<_Res> _request(
  String url, {
  String method = 'GET',
  Map<String, String> headers = const {},
}) async {
  final client = HttpClient();
  try {
    final req = await client.openUrl(method, Uri.parse(url));
    headers.forEach(req.headers.set);
    final res = await req.close();
    final out = <int>[];
    await for (final chunk in res) {
      out.addAll(chunk);
    }
    final map = <String, String>{};
    res.headers.forEach((name, values) {
      map[name.toLowerCase()] = values.join(',');
    });
    return _Res(statusCode: res.statusCode, headers: map, bytes: out);
  } finally {
    client.close();
  }
}

class _Res {
  const _Res({
    required this.statusCode,
    required this.headers,
    required this.bytes,
  });

  final int statusCode;
  final Map<String, String> headers;
  final List<int> bytes;
}
