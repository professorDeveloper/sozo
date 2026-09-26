// Telling a Cloudflare challenge on a stream host from every other refusal:
// only a challenge is worth opening a solver for.
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/player/stream_cloudflare.dart';

void main() {
  const cf = {'server': 'cloudflare', 'cf-ray': '8c1f-FRA'};

  group('classifyCloudflare', () {
    test('Cloudflare saying so outright is a challenge', () {
      expect(
        classifyCloudflare(
          status: 403,
          headers: {...cf, 'cf-mitigated': 'challenge'},
          body: '',
        ),
        CloudflareWall.challenge,
      );
    });

    test('a managed challenge page is a challenge', () {
      const page =
          '<title>Just a moment...</title>'
          '<script src="/cdn-cgi/challenge-platform/h/g/orchestrate/chl_page/v1"></script>';
      expect(
        classifyCloudflare(status: 503, headers: cf, body: page),
        CloudflareWall.challenge,
      );
    });

    test('a block page is a block, with nothing to solve', () {
      const page =
          '<title>Attention Required! | Cloudflare</title>'
          '<h2 class="cf-subheadline">Sorry, you have been blocked</h2>';
      expect(
        classifyCloudflare(status: 403, headers: cf, body: page),
        CloudflareWall.blocked,
      );
    });

    test("a host's own 403 is not Cloudflare's", () {
      expect(
        classifyCloudflare(
          status: 403,
          headers: const {'server': 'nginx'},
          body: 'Just a moment',
        ),
        CloudflareWall.none,
      );
      // Served through Cloudflare, but refused by the origin: no challenge.
      expect(
        classifyCloudflare(status: 403, headers: cf, body: 'token expired'),
        CloudflareWall.none,
      );
    });

    test('a stream that answers is nothing to solve', () {
      expect(
        classifyCloudflare(status: 200, headers: cf, body: '#EXTM3U'),
        CloudflareWall.none,
      );
      expect(
        classifyCloudflare(status: 404, headers: cf, body: 'Just a moment'),
        CloudflareWall.none,
      );
    });
  });

  group('probeCloudflare', () {
    late HttpServer server;
    final seen = <String?>[];

    setUp(() async {
      seen.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        seen.add(req.headers.value('user-agent'));
        final res = req.response;
        switch (req.uri.path) {
          case '/challenge.m3u8':
            res.statusCode = 403;
            res.headers
              ..set('server', 'cloudflare')
              ..set('cf-mitigated', 'challenge');
            res.write('<title>Just a moment...</title>');
          case '/blocked.m3u8':
            res.statusCode = 403;
            res.headers.set('server', 'cloudflare');
            res.write('Sorry, you have been blocked');
          default:
            res.headers.set('server', 'cloudflare');
            res.write('#EXTM3U\n${'#EXTINF:6,\nseg.ts\n' * 4000}');
        }
        await res.close();
      });
    });

    tearDown(() => server.close(force: true));

    Uri at(String path) => Uri.parse('http://127.0.0.1:${server.port}$path');

    test("asks with the player's own headers and reads the answer", () async {
      final dio = Dio();
      expect(
        await probeCloudflare(at('/challenge.m3u8'), {
          'User-Agent': 'PlayerUA/1',
        }, dio: dio),
        CloudflareWall.challenge,
      );
      expect(seen.single, 'PlayerUA/1');
      expect(
        await probeCloudflare(at('/blocked.m3u8'), const {}, dio: dio),
        CloudflareWall.blocked,
      );
      expect(
        await probeCloudflare(at('/ok.m3u8'), const {}, dio: dio),
        CloudflareWall.none,
      );
    });

    test('a host that cannot be asked is not called a challenge', () async {
      final gone = at('/challenge.m3u8');
      await server.close(force: true);
      expect(
        await probeCloudflare(gone, const {}, dio: Dio()),
        CloudflareWall.none,
      );
    });
  });
}
