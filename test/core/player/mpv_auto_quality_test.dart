import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/player/media_controller.dart';
import 'package:soplay/core/player/mpv_auto_quality.dart';

Duration s(num v) => Duration(milliseconds: (v * 1000).round());

void main() {
  group('starting rung', () {
    test('Auto opens on the top rendition on Wi-Fi', () {
      expect(
        MpvAutoQuality.startBitrate(
          preference: 0,
          network: NetworkKind.unmetered,
        ),
        'max',
      );
      expect(
        MpvAutoQuality.startBitrate(
          preference: 0,
          network: NetworkKind.unknown,
        ),
        'max',
      );
    });

    test('Auto is capped at 720p on mobile data', () {
      expect(
        MpvAutoQuality.startBitrate(
          preference: 0,
          network: NetworkKind.cellular,
        ),
        PlayerController.hlsBitrateFor(720),
      );
    });

    test('a pinned height ignores the network', () {
      expect(
        MpvAutoQuality.startBitrate(
          preference: 1080,
          network: NetworkKind.cellular,
        ),
        PlayerController.hlsBitrateFor(1080),
      );
    });
  });

  group('step down', () {
    test('one rung below what is playing', () {
      expect(
        MpvAutoQuality.stepDown(currentHeight: 1080, current: 'max'),
        PlayerController.hlsBitrateFor(720),
      );
      expect(
        MpvAutoQuality.stepDown(currentHeight: 720, current: '3500000'),
        PlayerController.hlsBitrateFor(480),
      );
      expect(
        MpvAutoQuality.stepDown(currentHeight: 360, current: '1000000'),
        'min',
      );
      expect(
        MpvAutoQuality.stepDown(currentHeight: 240, current: 'min'),
        isNull,
      );
    });

    test('without a height, one bitrate rung', () {
      expect(
        MpvAutoQuality.stepDown(current: 'max'),
        PlayerController.hlsBitrateFor(1080),
      );
      expect(
        MpvAutoQuality.stepDown(current: PlayerController.hlsBitrateFor(720)),
        PlayerController.hlsBitrateFor(480),
      );
      expect(MpvAutoQuality.stepDown(current: 'min'), isNull);
    });
  });

  group('stall watchdog', () {
    test('three stalls inside a minute trip it, then it counts afresh', () {
      final w = StallWatchdog();
      expect(w.recordStall(s(0)), isFalse);
      expect(w.recordStall(s(20)), isFalse);
      expect(w.recordStall(s(40)), isTrue);
      expect(w.recordStall(s(45)), isFalse);
    });

    test('stalls spread over more than a minute do not', () {
      final w = StallWatchdog();
      expect(w.recordStall(s(0)), isFalse);
      expect(w.recordStall(s(40)), isFalse);
      expect(w.recordStall(s(70)), isFalse);
      expect(w.recordStall(s(130)), isFalse);
    });

    test('the buffering after a seek is not counted', () {
      final w = StallWatchdog();
      w.recordStall(s(0));
      w.recordStall(s(10));
      w.noteSeek(s(19));
      expect(w.recordStall(s(20)), isFalse);
      expect(w.recordStall(s(30)), isTrue);
    });

    test('after an undo it stays quiet', () {
      final w = StallWatchdog()..disable();
      for (var i = 0; i < 5; i++) {
        expect(w.recordStall(s(i)), isFalse);
      }
    });
  });
}
