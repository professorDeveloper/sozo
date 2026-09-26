// Where a horizontal swipe on the video lands: fine near the start, far with
// a long swipe, and nothing at all when the finger comes back.
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/detail/domain/scrub_curve.dart';

void main() {
  const episode = 24 * 60 * 1000;
  int at(double cm, {int from = 600000, int duration = episode}) =>
      ScrubCurve.targetMs(
        baselineMs: from,
        durationMs: duration,
        deltaPx: cm * ScrubCurve.pxPerCm,
      );

  test('a finger back at its start changes nothing', () {
    expect(at(0), 600000);
    expect(at(0.2), 600000);
    expect(at(-0.2), 600000);
    expect(ScrubCurve.cancels(0.2 * ScrubCurve.pxPerCm), isTrue);
    expect(ScrubCurve.cancels(0.5 * ScrubCurve.pxPerCm), isFalse);
  });

  test('fine near the start, far with a long swipe', () {
    // About two seconds a centimetre at first.
    expect(at(1) - 600000, inInclusiveRange(2000, 5000));
    // A long swipe covers minutes — the old 90 s-per-width cap is gone.
    expect(at(8) - 600000, greaterThan(10 * 60 * 1000));
    // Backwards is the mirror of forwards.
    expect(600000 - at(-2), at(2) - 600000);
  });

  test('keeps growing with distance and stays inside the video', () {
    var last = 600000;
    for (var cm = 0.5; cm <= 20; cm += 0.5) {
      final t = at(cm);
      expect(t, greaterThanOrEqualTo(last));
      last = t;
    }
    expect(at(40), episode);
    expect(at(-40), 0);
  });

  test('a short clip still reaches a minute; a film is capped at 20', () {
    expect(
      at(8, from: 0, duration: 90 * 1000),
      greaterThanOrEqualTo(60 * 1000),
    );
    final film = 3 * 60 * 60 * 1000;
    expect(at(8, from: 0, duration: film), lessThanOrEqualTo(21 * 60 * 1000));
  });
}
