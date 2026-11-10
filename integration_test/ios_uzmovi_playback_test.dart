// Why this test exists
//
// uzmovi films do not play on iOS 3.2.1, and every layer below the player has
// already been cleared: the backend resolve answers 200 with a complete
// uzmovi-rc4-v1 config, the signed CDN returns a real playlist and real
// segments, and `LocalHlsProxy` serves both correctly when driven from Dart on
// macOS. What is left is the one thing that is only true on iOS — the stream is
// played by AVFoundation (`resolvePlayerEngine()` returns
// `PlayerEngine.native` on every non-Android, non-desktop platform, because
// there is no libmpv for iOS), and AVFoundation's refusal arrives as an opaque
// message unless somebody reads it off a device.
//
// So this runs the real chain on a real iOS target and prints what the player
// says: resolve live, register the proxy, fetch the playlist and the first
// segment through it from inside the app (proving the proxy half on-device),
// then hand the proxy URL to the player and report `errorDescription` verbatim.
//
//   flutter test integration_test/ios_uzmovi_playback_test.dart -d <device>
//
// A failure here is the point of the test, not a defect in it: the assertions
// come last, after everything has been printed.
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:soplay/core/player/local_hls_proxy.dart';
import 'package:soplay/core/player/media_controller.dart';
import 'package:soplay/core/player/player_engine.dart';

const _api = 'https://apisozo.azamov.me/api';
// A film rather than a serial: one resolve, no episode list in the way.
const _page =
    'https://uzmovi.net/tarjima-kinolarri/9102-xudo-asrasin-2-premyera-qirgiz-filmi-ozbek-tilida-uzbek.html';

void say(String line) => debugPrint('UZMOVI_IOS $line');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a uzmovi film plays on this device, or says why not', (
    tester,
  ) async {
    say('platform=${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    say('engine=${resolvePlayerEngine().id}');

    final dio = Dio(BaseOptions(validateStatus: (_) => true));
    final resolved = await dio.get<Map<String, dynamic>>(
      '$_api/contents/media',
      queryParameters: const {'provider': 'uzmovi', 'ref': _page},
    );
    say('resolve status=${resolved.statusCode}');
    final body = resolved.data!;
    final sources = (body['videoSources'] as List).cast<Map<String, dynamic>>();
    say('sources=${sources.length}');
    final src = sources.first;
    say('quality=${src['quality']} type=${src['type']} '
        'useLocalProxy=${src['useLocalProxy']} host=${src['host']}');

    final proxy = LocalHlsProxy(dio);
    final proxied = await proxy.register(
      upstreamUrl: src['videoUrl'] as String,
      headers: Map<String, String>.from(src['headers'] as Map),
      localProxy: Map<String, dynamic>.from(src['localProxy'] as Map),
      requestTransform: Map<String, dynamic>.from(
        (src['requestTransform'] ?? const {}) as Map,
      ),
    );
    say('proxy url=$proxied');

    // The proxy half, from inside this app on this device. If this fails the
    // player never had a chance and the fault is not AVFoundation's.
    final client = HttpClient();
    final playlistReq = await client.getUrl(Uri.parse(proxied));
    final playlistRes = await playlistReq.close();
    final playlist = await playlistRes.transform(utf8.decoder).join();
    say('playlist status=${playlistRes.statusCode} '
        'type=${playlistRes.headers.contentType} '
        'len=${playlist.length} '
        'cl=${playlistRes.headers.contentLength}');
    final firstSegment = playlist
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty && !l.startsWith('#'), orElse: () => '');
    say('first segment line=$firstSegment');
    if (firstSegment.isNotEmpty) {
      final segUri = Uri.parse(proxied).resolve(firstSegment);
      final segReq = await client.getUrl(segUri);
      // The way AVFoundation opens a segment.
      segReq.headers.set(HttpHeaders.rangeHeader, 'bytes=0-');
      final segRes = await segReq.close();
      var bytes = 0;
      await for (final chunk in segRes) {
        bytes += chunk.length;
      }
      say('segment status=${segRes.statusCode} '
          'range=${segRes.headers.value('content-range')} '
          'accept-ranges=${segRes.headers.value('accept-ranges')} '
          'cl=${segRes.headers.contentLength} read=$bytes');
    }
    client.close();

    // Now the player itself.
    final controller = PlayerController.networkUrl(
      Uri.parse(proxied),
      httpHeaders: const {},
      formatHint: VideoFormat.hls,
    );
    say('controller=${controller.runtimeType}');
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: controller.buildView())),
    );
    String? failure;
    try {
      await controller.initialize().timeout(const Duration(seconds: 60));
      say('initialized size=${controller.value.size} '
          'duration=${controller.value.duration}');
      await controller.play();
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (controller.value.position < const Duration(seconds: 2) &&
          !controller.value.hasError &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        await tester.pump();
      }
      say('position=${controller.value.position} '
          'playing=${controller.value.isPlaying} '
          'buffered=${controller.value.buffered}');
    } catch (e) {
      failure = '$e';
      say('THREW: $e');
    }
    // Verbatim, because this is the line that has been missing all along.
    say('hasError=${controller.value.hasError}');
    say('errorDescription=${controller.value.errorDescription}');

    final position = controller.value.position;
    await tester.pumpWidget(const SizedBox());
    await controller.dispose();
    await proxy.dispose();

    expect(failure, isNull, reason: 'player threw: $failure');
    expect(
      controller.value.errorDescription,
      isNull,
      reason: 'player reported: ${controller.value.errorDescription}',
    );
    expect(
      position,
      greaterThanOrEqualTo(const Duration(seconds: 2)),
      reason: 'playback did not reach 2s',
    );
  }, timeout: const Timeout(Duration(minutes: 5)));
}
