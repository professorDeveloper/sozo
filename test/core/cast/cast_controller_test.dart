import 'dart:io';

import 'package:dart_cast/dart_cast.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/cast/cast_controller.dart';

void main() {
  group('castTypeFor', () {
    test('an m3u8 is HLS, which is most of what this app plays', () {
      expect(castTypeFor('https://cdn/x/master.m3u8'), CastMediaType.hls);
      expect(castTypeFor('https://cdn/x/master.M3U8'), CastMediaType.hls);
    });

    test('the backend type hint beats the extension', () {
      // Plenty of these links end in a token or a bare id and say what they are
      // only in the resolve response. Trusting the URL alone would send an HLS
      // playlist to a receiver told to expect mp4.
      expect(
        castTypeFor('https://cdn/stream?token=abc', hint: 'hls'),
        CastMediaType.hls,
      );
    });

    test('containers map to what a receiver understands', () {
      expect(castTypeFor('https://cdn/a.mp4'), CastMediaType.mp4);
      expect(castTypeFor('https://cdn/a.m4v'), CastMediaType.mp4);
      expect(castTypeFor('https://cdn/a.mkv'), CastMediaType.mkv);
      expect(castTypeFor('https://cdn/seg.ts'), CastMediaType.mpegTs);
    });

    test('DASH is refused rather than guessed at', () {
      // No receiver reached over this protocol plays it, and guessing mp4 would
      // turn "not supported" into a spinner that never ends.
      expect(castTypeFor('https://cdn/a.mpd'), isNull);
    });

    test('anything that is not fetchable over the network is refused', () {
      // A cast device fetches the media itself. It cannot open a path on this
      // phone's disk or a content:// handle, so offering the button would
      // promise something that can only fail.
      expect(castTypeFor('/data/user/0/app/files/ep1.mp4'), isNull);
      expect(castTypeFor('file:///storage/ep1.mp4'), isNull);
      expect(castTypeFor('content://media/external/video/1'), isNull);
      expect(castTypeFor(''), isNull);
    });

    test('an unknown extension over http is treated as mp4', () {
      // The one guess worth making: a redirect to an mp4 is the common shape,
      // and a receiver recovers from a wrong container hint on its own.
      expect(castTypeFor('https://cdn/watch/12345'), CastMediaType.mp4);
    });
  });

  group('CastController', () {
    test('starts idle, with nothing to control', () {
      final c = CastController(service: CastService());
      addTearDown(c.dispose);

      expect(c.isCasting, isFalse);
      expect(c.device, isNull);
      expect(c.devices, isEmpty);
      expect(c.state, SessionState.disconnected);
    });

    test('controls on no session do not throw', () async {
      // Every one of these is a button under a thumb, and the failure is always
      // the same shape — the TV went away. A tap handler must not become a
      // crash report.
      final c = CastController(service: CastService());
      addTearDown(c.dispose);

      await expectLater(c.play(), completes);
      await expectLater(c.pause(), completes);
      await expectLater(c.seek(const Duration(seconds: 30)), completes);
      await expectLater(c.setVolume(0.5), completes);
      await expectLater(c.stopCasting(), completes);
    });

    test('stopping when nothing is casting leaves it idle', () async {
      final c = CastController(service: CastService());
      addTearDown(c.dispose);

      await c.stopCasting();

      expect(c.isCasting, isFalse);
      expect(c.state, SessionState.disconnected);
    });

    test('a failed connection does not leave a half-open session', () async {
      // CastService with no providers cannot create a session, so connect
      // throws — which is the same path a TV that went off standby takes.
      final c = CastController(service: CastService());
      addTearDown(c.dispose);

      final ok = await c.castTo(
        CastDevice(
          id: 'x',
          name: 'Living room',
          protocol: CastProtocol.chromecast,
          address: InternetAddress('192.168.1.50'),
          port: 8009,
        ),
        const CastMedia(url: 'https://cdn/a.m3u8', type: CastMediaType.hls),
      );

      expect(ok, isFalse);
      expect(c.isCasting, isFalse, reason: 'nothing is left connected');
      expect(c.device, isNull, reason: 'and no TV is claimed in the UI');
      expect(c.error, isNotNull, reason: 'the reason survives for the toast');
    });
  });
}
