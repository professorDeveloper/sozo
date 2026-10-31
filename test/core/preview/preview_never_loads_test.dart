import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/preview/frame_preview_service.dart';

/// The decoder as it behaves on a slow host: a frame takes [frameTakes] to
/// come back, and nothing the viewer does makes the host any faster.
class SlowDecoder {
  SlowDecoder({required this.frameTakes});

  final Duration frameTakes;
  int frameCalls = 0;
  int closes = 0;

  Future<dynamic> call(String method, Map<String, dynamic>? args) async {
    switch (method) {
      case 'open':
        return true;
      case 'close':
        closes++;
        return true;
      default:
        frameCalls++;
        await Future<void>.delayed(frameTakes);
        return Uint8List.fromList([7]);
    }
  }
}

void main() {
  const url = 'https://cdn.test/v/master.m3u8';

  FramePreviewSession production(SlowDecoder decoder) => FramePreviewSession(
    supported: true,
    invoke: decoder.call,
    openTimeout: FramePreviewService.openAllowance,
    frameTimeout: FramePreviewService.frameAllowance,
  );

  test(
    'a 2.3 MB segment on a 2 Mbit/s connection (about 9 s) gets its frame',
    () {
      fakeAsync((clock) {
        final decoder = SlowDecoder(frameTakes: const Duration(seconds: 9));
        final session = production(decoder);
        Uint8List? got;
        session.open(url, const {}).then((_) {
          session.frame(60000).then((b) => got = b);
        });
        clock.elapse(const Duration(seconds: 30));
        expect(got, isNotNull, reason: 'The frame arrived and was thrown away');
      });
    },
  );

  test(
    'a finger lifted while a frame is decoding does not lose that frame',
    () {
      fakeAsync((clock) {
        final decoder = SlowDecoder(frameTakes: const Duration(seconds: 4));
        final session = production(decoder);
        session.open(url, const {}).then((_) => session.frame(60000));
        clock.elapse(const Duration(seconds: 1));
        session.endScrub(); // The drag was over in a second.
        clock.elapse(const Duration(seconds: 10));
        expect(
          session.nearest(60000),
          isNotNull,
          reason: 'Short drags on a slow host would never show a picture',
        );
      });
    },
  );

  test(
    'short drags on a slow host end with a picture, not a restart each time',
    () {
      fakeAsync((clock) {
        final decoder = SlowDecoder(frameTakes: const Duration(seconds: 4));
        final session = production(decoder);
        session.open(url, const {});
        clock.elapse(Duration.zero);
        for (var drag = 0; drag < 5; drag++) {
          session.frame(60000);
          clock.elapse(const Duration(seconds: 1));
          session.endScrub();
          clock.elapse(const Duration(seconds: 2));
        }
        clock.elapse(const Duration(seconds: 10));
        expect(session.nearest(60000), isNotNull);
        expect(
          decoder.frameCalls,
          lessThanOrEqualTo(2),
          reason: 'Every drag paid for the same segment again',
        );
      });
    },
  );

  test('a frame that lands after the source changed is not kept', () {
    fakeAsync((clock) {
      final decoder = SlowDecoder(frameTakes: const Duration(seconds: 4));
      final session = production(decoder);
      session.open(url, const {}).then((_) => session.frame(60000));
      clock.elapse(const Duration(seconds: 1));
      session.open('https://cdn.test/other/master.m3u8', const {});
      clock.elapse(const Duration(seconds: 10));
      expect(session.nearest(60000), isNull);
    });
  });

  test('a host that was down for a while is tried again', () {
    fakeAsync((clock) {
      var up = false;
      final session = FramePreviewSession(
        supported: true,
        openTimeout: const Duration(seconds: 1),
        frameTimeout: const Duration(seconds: 1),
        idleTimeout: const Duration(days: 1),
        invoke: (method, args) async {
          if (method != 'frame') return true;
          if (up) return Uint8List.fromList([1]);
          return Completer<dynamic>().future;
        },
      );
      final warmer = PreviewGridWarmer(
        session: session,
        url: url,
        headers: const {},
        durationMs: 1200000,
        count: 40,
        pace: const Duration(seconds: 1),
        isScrubbing: () => false,
      )..start();
      clock.elapse(const Duration(minutes: 1));
      expect(session.consecutiveFailures, greaterThanOrEqualTo(6));
      final tries = session.consecutiveFailures;
      clock.elapse(const Duration(seconds: 20));
      expect(
        session.consecutiveFailures,
        lessThanOrEqualTo(tries + 1),
        reason: 'A dead host is not hammered while the warmer rests',
      );
      up = true;
      clock.elapse(const Duration(minutes: 3));
      expect(
        session.nearest(600000, withinMs: 1200000),
        isNotNull,
        reason: 'A network blip must not end the grid for the whole episode',
      );
      warmer.stop();
      clock.elapse(const Duration(hours: 1));
    });
  });

  group('a stream the retriever cannot read goes to the extractor', () {
    Uint8List frame() => Uint8List.fromList([9]);

    test('a refused open', () async {
      final seen = <String>[];
      final decoder = FallbackDecoder(
        primary: (m, a) async => m == 'open' ? false : null,
        secondary: (m, a) async {
          seen.add(m);
          return m == 'open' ? true : frame();
        },
      );
      expect(await decoder.call('open', {'url': url}), isTrue);
      expect(await decoder.call('frame', {'posMs': 0}), [9]);
      expect(seen, ['open', 'frame']);
    });

    test('an open that never comes back', () {
      fakeAsync((clock) {
        Object? opened;
        final decoder = FallbackDecoder(
          primary: (m, a) => Completer<dynamic>().future,
          secondary: (m, a) async => true,
        );
        decoder.call('open', {'url': url}).then((v) => opened = v);
        clock.elapse(const Duration(seconds: 11));
        expect(opened, isTrue, reason: 'Inside the session allowance of 15 s');
        expect(decoder.openLimit, lessThan(FramePreviewService.openAllowance));
      });
    });

    test('an open that throws', () async {
      final decoder = FallbackDecoder(
        primary: (m, a) => Future<dynamic>.error(StateError('no retriever')),
        secondary: (m, a) async => true,
      );
      expect(await decoder.call('open', {'url': url}), isTrue);
    });

    test('a retriever that opens but only ever gives nulls', () async {
      final decoder = FallbackDecoder(
        primary: (m, a) async => m == 'open' ? true : null,
        secondary: (m, a) async => m == 'open' ? true : frame(),
      );
      await decoder.call('open', {'url': url, 'generation': 1});
      expect(await decoder.call('frame', {'generation': 1}), isNull);
      expect(await decoder.call('frame', {'generation': 1}), [9]);
    });

    test('one miss from a working retriever changes nothing', () async {
      var calls = 0;
      var secondary = 0;
      final decoder = FallbackDecoder(
        primary: (m, a) async {
          if (m == 'open') return true;
          return ++calls == 1 ? null : frame();
        },
        secondary: (m, a) async {
          secondary++;
          return true;
        },
      );
      await decoder.call('open', {'url': url});
      expect(await decoder.call('frame', const {}), isNull);
      expect(await decoder.call('frame', const {}), [9]);
      expect(secondary, 0);
    });

    test('a new stream starts on the retriever again', () async {
      var primaryOpens = 0;
      final decoder = FallbackDecoder(
        primary: (m, a) async {
          if (m == 'open') primaryOpens++;
          return m == 'open' ? primaryOpens > 1 : null;
        },
        secondary: (m, a) async => true,
      );
      await decoder.call('open', {'url': url});
      await decoder.call('open', {'url': '$url?other'});
      expect(primaryOpens, 2);
    });
  });
}
