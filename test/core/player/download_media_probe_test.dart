import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/player/download_media_probe.dart';
import 'package:soplay/features/detail/domain/entities/media_resolve_entity.dart';

void main() {
  test(
    'probe rejects expired token and HTML, accepts real HLS and MP4 with wrong MIME',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        switch (req.uri.path) {
          case '/expired':
            req.response.statusCode = 403;
            break;
          case '/html':
            req.response.write('<html>Access denied</html>');
            break;
          case '/playlist':
            req.response.write(
              '#EXTM3U\n#EXT-X-TARGETDURATION:10\n#EXTINF:10,\nseg.ts\n',
            );
            break;
          case '/video':
            req.response.headers.contentType = ContentType('image', 'jpeg');
            req.response.add([
              0,
              0,
              0,
              24,
              102,
              116,
              121,
              112,
              109,
              112,
              52,
              50,
            ]);
        }
        await req.response.close();
      });
      final dio = Dio();
      final probe = DownloadMediaProbe(dio);
      try {
        Future<bool> check(String path, String type) => probe.accepts(
          MediaResolveEntity(
            videoUrl: 'http://127.0.0.1:${server.port}/$path',
            headers: const {},
            type: type,
          ),
        );
        expect(await check('expired', 'hls'), isFalse);
        expect(await check('html', 'hls'), isFalse);
        expect(await check('playlist', 'hls'), isTrue);
        expect(await check('video', 'mp4'), isTrue);
      } finally {
        dio.close(force: true);
        await server.close(force: true);
      }
    },
  );

  group('verdict', () {
    late HttpServer server;
    late Dio dio;
    late DownloadMediaProbe probe;
    final stalled = <HttpRequest>[];

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        switch (req.uri.path) {
          case '/expired.mp4':
            req.response.statusCode = 403;
          case '/challenge.mp4':
            req.response.headers.contentType = ContentType('video', 'mp4');
            req.response.write('\n<!DOCTYPE html><html>Just a moment');
          case '/page-0.html':
            req.response.headers.contentType = ContentType('text', 'html');
            req.response.add([0x47, 0x40, 0x00, 0x30, ...List.filled(600, 1)]);
          case '/old.mov':
            req.response.add([0, 0, 0, 8, ...'wide'.codeUnits, 0, 0, 0, 1]);
          case '/error.json':
            req.response.write('{"error":"expired"}');
          case '/slow.mp4':
            // Never answers within the probe's time.
            stalled.add(req);
            return;
        }
        await req.response.close();
      });
      dio = Dio();
      probe = DownloadMediaProbe(
        dio,
        timeout: const Duration(milliseconds: 300),
      );
    });

    tearDown(() async {
      for (final req in stalled) {
        unawaited(req.response.close().catchError((_) {}));
      }
      stalled.clear();
      dio.close(force: true);
      await server.close(force: true);
    });

    MediaResolveEntity at(String path, {String? type}) => MediaResolveEntity(
      videoUrl: 'http://127.0.0.1:${server.port}$path',
      headers: const {},
      type: type,
    );

    test('a page labelled video is a web page, and only that blocks', () async {
      final media = at('/challenge.mp4', type: 'mp4');
      expect(await probe.verdict(media), MediaProbeVerdict.webPage);
      expect(await probe.servesWebPage(media), isTrue);
      expect(await probe.accepts(media), isFalse);
    });

    test('TS labelled text/html and a QuickTime file are media', () async {
      expect(
        await probe.verdict(at('/page-0.html', type: 'mp4')),
        MediaProbeVerdict.media,
      );
      expect(
        await probe.verdict(at('/old.mov', type: 'mp4')),
        MediaProbeVerdict.media,
      );
    });

    test('an error status or unknown bytes are rejected, not a page', () async {
      final expired = at('/expired.mp4', type: 'mp4');
      expect(await probe.verdict(expired), MediaProbeVerdict.rejected);
      expect(await probe.servesWebPage(expired), isFalse);
      expect(
        await probe.verdict(at('/error.json', type: 'mp4')),
        MediaProbeVerdict.rejected,
      );
    });

    test('no answer says nothing, and does not block', () async {
      final slow = at('/slow.mp4', type: 'mp4');
      expect(await probe.verdict(slow), MediaProbeVerdict.noAnswer);
      expect(await probe.servesWebPage(slow), isFalse);

      final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = closed.port;
      await closed.close();
      expect(
        await probe.verdict(
          MediaResolveEntity(
            videoUrl: 'http://127.0.0.1:$port/film.mp4',
            headers: const {},
            type: 'mp4',
          ),
        ),
        MediaProbeVerdict.noAnswer,
      );
    });
  });
}
