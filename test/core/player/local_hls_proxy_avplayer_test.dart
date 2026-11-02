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

    test(
      'a playlist at an extensionless path is never answered from a slice',
      () async {
        // `/live/playlist` says what it is only in its first bytes, so the
        // player's Range is already upstream by the time this proxy knows it is
        // holding text it has to rewrite whole. A host that honours that Range
        // hands back a slice, and a rewrite of a slice is a playlist cut off
        // mid-segment-list that declares itself complete — AVPlayer then plays
        // whatever part of the film survived the cut and stops.
        final url = await proxy.register(
          upstreamUrl: '${upstream.origin}/live/playlist',
          headers: const {'Referer': 'https://uzmovi.net/'},
          keepOriginHeaders: true,
        );
        final whole = await _request(url);
        final total = whole.bytes.length;
        expect(utf8.decode(whole.bytes), contains('#EXT-X-ENDLIST'));

        final res = await _request(url, headers: const {'Range': 'bytes=0-9'});
        expect(res.statusCode, 206);
        expect(
          res.headers['content-range'],
          'bytes 0-9/$total',
          reason: 'The total has to be the whole rewritten playlist, not the '
              'few bytes the upstream was willing to hand over',
        );
        expect(res.bytes, whole.bytes.sublist(0, 10));

        final tail = await _request(
          url,
          headers: {'Range': 'bytes=${total - 5}-'},
        );
        expect(tail.statusCode, 206);
        expect(tail.headers['content-range'], 'bytes ${total - 5}-${total - 1}/$total');
        expect(
          tail.bytes,
          whole.bytes.sublist(total - 5),
          reason: 'The end of the playlist exists only if the whole file was '
              'fetched; a forwarded Range never reaches it',
        );
      },
    );

    test(
      'a HEAD on an extensionless playlist reports the rewritten length',
      () async {
        final url = await proxy.register(
          upstreamUrl: '${upstream.origin}/live/playlist',
          headers: const {},
        );
        final whole = await _request(url);
        final res = await _request(url, method: 'HEAD');
        expect(res.statusCode, 200);
        expect(res.headers['content-length'], '${whole.bytes.length}');
        expect(res.bytes, isEmpty);
      },
    );

    test('a probe range on an image-wrapped segment is a 206 slice', () async {
      // The hosts that store video on image CDNs are the reason the unwrapping
      // exists, and on iOS those streams are opened with exactly this probe. A
      // 200 carrying the whole segment in reply, with byte ranges disclaimed,
      // is the protocol error AVPlayer abandons the stream over.
      final url = await proxy.register(
        upstreamUrl: '${upstream.origin}/live/index.m3u8',
        headers: const {},
      );
      final wrapped = _sibling(url, 'seg0.png');
      final total = upstream.wrappedPayload.length;
      final res = await _request(wrapped, headers: const {'Range': 'bytes=0-1'});
      expect(res.statusCode, 206);
      expect(res.headers['content-type'], 'video/mp2t');
      expect(res.headers['content-length'], '2');
      expect(
        res.headers['content-range'],
        'bytes 0-1/$total',
        reason: 'The size is the transport stream behind the picture, not the '
            'file the upstream served',
      );
      expect(res.headers['accept-ranges'], 'bytes');
      expect(res.bytes, upstream.wrappedPayload.sublist(0, 2));
    });

    test('a mid-file range on an image-wrapped segment is the right slice', () async {
      final url = await proxy.register(
        upstreamUrl: '${upstream.origin}/live/index.m3u8',
        headers: const {},
      );
      final wrapped = _sibling(url, 'seg0.png');
      final total = upstream.wrappedPayload.length;
      final res = await _request(
        wrapped,
        headers: const {'Range': 'bytes=188-375'},
      );
      expect(res.statusCode, 206);
      expect(res.headers['content-length'], '188');
      expect(res.headers['content-range'], 'bytes 188-375/$total');
      expect(res.bytes, upstream.wrappedPayload.sublist(188, 376));
    });

    test(
      'an image-wrapped segment is unwrapped even when the host honours ranges',
      () async {
        // Reading from an offset would land in the middle of the picture, where
        // there is no telling where the video starts, so the probe must not be
        // forwarded for a path that may be a wrapper.
        upstream.honourRanges = true;
        final url = await proxy.register(
          upstreamUrl: '${upstream.origin}/live/index.m3u8',
          headers: const {},
        );
        final wrapped = _sibling(url, 'seg0.png');
        final res = await _request(
          wrapped,
          headers: const {'Range': 'bytes=0-1'},
        );
        expect(res.statusCode, 206);
        expect(res.bytes, upstream.wrappedPayload.sublist(0, 2));
        expect(
          upstream.lastRange,
          isNull,
          reason: 'A Range forwarded here returns two bytes of PNG signature '
              'and the wrapper can never be found',
        );
      },
    );

    test('a plain GET of a wrapped segment states the unwrapped length', () async {
      final url = await proxy.register(
        upstreamUrl: '${upstream.origin}/live/index.m3u8',
        headers: const {},
      );
      final wrapped = _sibling(url, 'seg0.png');
      final res = await _request(wrapped);
      expect(res.statusCode, 200);
      expect(res.headers['content-type'], 'video/mp2t');
      expect(
        res.headers['content-length'],
        '${upstream.wrappedPayload.length}',
        reason: 'AVPlayer sizes the resource from this, and a segment of '
            'unknown length it cannot seek in is one it will not play',
      );
      expect(res.headers['accept-ranges'], 'bytes');
      expect(res.bytes, upstream.wrappedPayload);
    });

    test(
      'an upstream that sends fewer bytes than it declared fails before the '
      'response is committed',
      () async {
        // The slice used to be streamed out under a Content-Length taken from
        // the upstream's own claim. A host that overstates it left the response
        // promised a length it could never reach, which dies mid-flight with
        // the player already reading it; a status it never got to see is a
        // cleaner answer than a truncated body.
        upstream.honourRanges = false;
        upstream.truncateAfter = 100;
        final url = await proxy.register(
          upstreamUrl: '${upstream.origin}/live/index.m3u8',
          headers: const {},
        );
        final segment = _sibling(url, 'index0.ts');
        final res = await _request(
          segment,
          headers: const {'Range': 'bytes=0-187'},
        ).timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw StateError(
            'The response never finished: it was committed to a length the '
            'upstream could not deliver',
          ),
        );
        expect(res.statusCode, 502);
        expect(res.bytes, isEmpty);
      },
    );

    test(
      'a HEAD whose upstream states no length still answers completely',
      () async {
        // The upstream HEAD is usable only when it carries a size, since that
        // is the one thing AVPlayer is asking for. Without it the body has to
        // be fetched, and the whole answer — status, content type and length —
        // has to come from that fetch. _answerHead therefore decides before it
        // writes anything at all: a half-written response handed back to the
        // caller only survives while every branch below happens to set the
        // same two headers again.
        upstream.headWithoutLength = true;
        final url = await registerSegmentSession();
        final segment = _sibling(url, 'index0.ts');
        final res = await _request(segment, method: 'HEAD');
        expect(res.statusCode, 200);
        expect(res.headers['content-type'], 'video/mp2t');
        expect(res.headers['content-length'], '${upstream.segment.length}');
        expect(res.headers['accept-ranges'], 'bytes');
        expect(res.bytes, isEmpty);
      },
    );

    test(
      'a range is answered without waiting for the rest of the download',
      () async {
        // The upstream here ignores the range and starts sending megabytes of
        // which two are wanted. Reading the rest would keep the player waiting
        // on bytes nobody asked for, so the slice is answered as soon as it is
        // complete. It is only the answer that is prompt: the connection itself
        // is not taken down, which is measured and commented on below.
        final url = await proxy.register(
          upstreamUrl: '${upstream.origin}/live/index.m3u8',
          headers: const {},
        );
        final segment = _sibling(url, 'big.ts');
        final total = upstream.big.length;
        final res = await _request(
          segment,
          headers: const {'Range': 'bytes=0-1'},
        ).timeout(
          const Duration(seconds: 20),
          onTimeout: () => throw StateError(
            'The range was held open waiting for the rest of the file',
          ),
        );
        // Read the moment the answer is in the player's hands: the upstream
        // goes on sending afterwards, because cancelling the stream this
        // response arrives on does not take the connection down — see the
        // note on [_RangeUpstream.sentBytes].
        final sentWhenAnswered = upstream.sentBytes;
        expect(res.statusCode, 206);
        expect(res.headers['content-length'], '2');
        expect(res.headers['content-range'], 'bytes 0-1/$total');
        expect(res.bytes, upstream.big.sublist(0, 2));
        expect(
          sentWhenAnswered,
          lessThan(total),
          reason: 'The upstream was still sending when the player already had '
              'its answer, which is the point: nothing waits on bytes nobody '
              'asked for',
        );
      },
    );

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

/// The smallest PNG shape the unwrapping looks at: signature, then IEND and
/// its CRC.
const _tinyPng = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0, 0, 0, 0, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

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

  /// The transport stream hidden inside [wrapped], which is what the player
  /// must end up with.
  final Uint8List wrappedPayload = Uint8List.fromList(
    List<int>.generate(188 * 4, (i) => i % 188 == 0 ? 0x47 : (i & 0x7f) + 1),
  );

  /// A segment stored on an image CDN: a picture, some padding, then the video.
  Uint8List get wrapped => Uint8List.fromList([
    ..._tinyPng,
    ...List.filled(37, 0xFF),
    ...wrappedPayload,
  ]);

  /// How many bytes of the body to send before hanging up, for a host that
  /// declares a Content-Length larger than what it delivers.
  int? truncateAfter;

  /// A file far larger than any socket buffer, served chunk by chunk and
  /// ignoring ranges, so what the upstream had sent by the time the proxy let
  /// go of the connection can be counted.
  final Uint8List big = Uint8List.fromList(
    List<int>.generate(8 * 1024 * 1024, (i) => i % 188 == 0 ? 0x47 : i & 0xff),
  );

  /// How much of [big] has gone out, which the proxy's answer is raced
  /// against. It keeps climbing after that answer: the proxy stops reading
  /// the body but the connection stays up and this mock delivers the rest, so
  /// only the count taken at the moment of the answer says anything.
  int sentBytes = 0;

  /// When true HEAD answers without a Content-Length, which is the one thing
  /// the probe exists to learn.
  bool headWithoutLength = false;

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

    // A playlist served at a path that does not name itself one — the shape
    // every static host and object store falls into, with ranges honoured.
    if (req.uri.path.endsWith('/playlist')) {
      lastPlaylistRange = lastRange;
      final body = utf8.encode(
        '#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:10\n'
        '#EXTINF:10.0,\nindex0.ts\n#EXTINF:10.0,\nindex1.ts\n'
        '#EXTINF:10.0,\nindex2.ts\n#EXT-X-ENDLIST\n',
      );
      res.headers.set(HttpHeaders.contentTypeHeader, 'text/plain');
      await _serveBody(req, Uint8List.fromList(body));
      return;
    }

    if (req.uri.path.endsWith('big.ts')) {
      res.statusCode = 200;
      res.headers.set(HttpHeaders.contentTypeHeader, 'video/mp2t');
      res.headers.set(HttpHeaders.contentLengthHeader, '${big.length}');
      const chunk = 64 * 1024;
      try {
        for (var at = 0; at < big.length; at += chunk) {
          final stop = at + chunk > big.length ? big.length : at + chunk;
          res.add(Uint8List.sublistView(big, at, stop));
          await res.flush();
          sentBytes = stop;
          // A real CDN takes time over eight megabytes, and without that pause
          // loopback delivers all of them into the client's buffers before the
          // proxy has answered the two bytes it was asked for — the test then
          // passes or fails on who won the race rather than on whether the
          // download was let go of.
          await Future<void>.delayed(const Duration(milliseconds: 2));
        }
        await res.close();
      } catch (_) {
        // A host whose client has gone away stops here rather than failing the
        // test around it.
      }
      return;
    }

    if (req.uri.path.endsWith('.png')) {
      res.headers.set(HttpHeaders.contentTypeHeader, 'image/png');
      res.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      await _serveBody(req, wrapped);
      return;
    }

    res.headers.set(HttpHeaders.contentTypeHeader, 'video/mp2t');
    res.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    await _serveBody(req, segment);
  }

  /// [body] served the way the flags above say: whole with a 200, or as the
  /// 206 slice that was asked for, and cut short when [truncateAfter] is set.
  Future<void> _serveBody(HttpRequest req, Uint8List body) async {
    final res = req.response;
    final range = honourRanges ? _parseRange(lastRange, body.length) : null;
    final slice = range == null
        ? body
        : Uint8List.sublistView(body, range.$1, range.$2 + 1);
    final declared = slice.length;
    if (range != null) {
      res.statusCode = 206;
      res.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes ${range.$1}-${range.$2}/${body.length}',
      );
    } else {
      res.statusCode = 200;
    }
    if (req.method == 'HEAD' && headWithoutLength) {
      await res.close();
      return;
    }
    final cut = truncateAfter;
    if (cut == null || req.method == 'HEAD' || cut >= declared) {
      res.headers.set(HttpHeaders.contentLengthHeader, '$declared');
      if (req.method != 'HEAD') res.add(slice);
      await res.close();
      return;
    }
    // Written by hand: Dart's own HttpResponse refuses to under-deliver a
    // Content-Length it has been given, which is the whole point here.
    final contentType =
        res.headers.value(HttpHeaders.contentTypeHeader) ?? 'video/mp2t';
    final socket = await res.detachSocket(writeHeaders: false);
    socket.write(
      'HTTP/1.1 ${res.statusCode} OK\r\n'
      'Content-Type: $contentType\r\n'
      'Content-Length: $declared\r\n'
      'Connection: close\r\n\r\n',
    );
    socket.add(Uint8List.sublistView(slice, 0, cut));
    await socket.flush();
    await socket.close();
    socket.destroy();
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
