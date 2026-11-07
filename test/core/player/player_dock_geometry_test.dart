// Where the desktop corner player sits is plain arithmetic, so it is pinned
// here without a window: the four corners at the margin, the size clamped to
// what leaves the page under it usable, the snap on release, and the resize
// grips growing the box toward the middle of the window.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/player/player_dock.dart';

void main() {
  const area = Size(1200, 800);
  const m = DockGeometry.margin;

  group('rectFor', () {
    const size = Size(400, 225);

    test('puts each corner at the margin', () {
      expect(
        DockGeometry.rectFor(DockCorner.topLeft, size, area),
        const Rect.fromLTWH(m, m, 400, 225),
      );
      expect(
        DockGeometry.rectFor(DockCorner.topRight, size, area),
        const Rect.fromLTWH(1200 - 400 - m, m, 400, 225),
      );
      expect(
        DockGeometry.rectFor(DockCorner.bottomLeft, size, area),
        const Rect.fromLTWH(m, 800 - 225 - m, 400, 225),
      );
      expect(
        DockGeometry.rectFor(DockCorner.bottomRight, size, area),
        const Rect.fromLTWH(1200 - 400 - m, 800 - 225 - m, 400, 225),
      );
    });
  });

  group('sizeFor', () {
    test('keeps the picture shape', () {
      expect(DockGeometry.sizeFor(400, 16 / 9, area), const Size(400, 225));
    });

    test('never smaller than the minimum', () {
      expect(DockGeometry.sizeFor(10, 16 / 9, area).width, 240);
    });

    test('never more than the share of the window', () {
      expect(DockGeometry.sizeFor(5000, 16 / 9, area).width, 1200 * 0.6);
    });

    test('a short window caps it by height instead', () {
      const short = Size(1600, 300);
      final s = DockGeometry.sizeFor(5000, 16 / 9, short);
      expect(s.height, lessThanOrEqualTo(300 - 2 * m + 1));
    });

    test('a window narrower than the minimum still gets the minimum', () {
      expect(
        DockGeometry.sizeFor(400, 16 / 9, const Size(200, 150)).width,
        240,
      );
    });
  });

  group('clampAspect', () {
    test('maps nonsense to 16:9 and extremes into range', () {
      expect(DockGeometry.clampAspect(0), 16 / 9);
      expect(DockGeometry.clampAspect(double.nan), 16 / 9);
      expect(DockGeometry.clampAspect(-2), 16 / 9);
      expect(DockGeometry.clampAspect(10), 2.6);
      expect(DockGeometry.clampAspect(0.1), 0.5);
      expect(DockGeometry.clampAspect(4 / 3), 4 / 3);
    });
  });

  group('nearest', () {
    Rect at(Offset centre) =>
        Rect.fromCenter(center: centre, width: 300, height: 170);

    test('picks the quarter the centre is in', () {
      expect(
        DockGeometry.nearest(at(const Offset(200, 150)), Offset.zero, area),
        DockCorner.topLeft,
      );
      expect(
        DockGeometry.nearest(at(const Offset(1000, 150)), Offset.zero, area),
        DockCorner.topRight,
      );
      expect(
        DockGeometry.nearest(at(const Offset(200, 700)), Offset.zero, area),
        DockCorner.bottomLeft,
      );
      expect(
        DockGeometry.nearest(at(const Offset(1000, 700)), Offset.zero, area),
        DockCorner.bottomRight,
      );
    });

    test('a flick from the middle lands where it was thrown', () {
      // Released just right of and below the middle, but flung up-left.
      final r = at(const Offset(620, 420));
      expect(
        DockGeometry.nearest(r, const Offset(-1500, -1500), area),
        DockCorner.topLeft,
      );
      expect(
        DockGeometry.nearest(r, Offset.zero, area),
        DockCorner.bottomRight,
      );
    });
  });

  group('resized', () {
    test('grows toward the middle of the window from every corner', () {
      // Left corners: the grip is on the right, so dragging right grows.
      expect(
        DockGeometry.resized(400, const Offset(50, 0), DockCorner.topLeft, 1),
        450,
      );
      expect(
        DockGeometry.resized(
          400,
          const Offset(50, 0),
          DockCorner.bottomLeft,
          1,
        ),
        450,
      );
      // Right corners: the grip is on the left, so dragging left grows.
      expect(
        DockGeometry.resized(400, const Offset(-50, 0), DockCorner.topRight, 1),
        450,
      );
      expect(
        DockGeometry.resized(
          400,
          const Offset(-50, 0),
          DockCorner.bottomRight,
          1,
        ),
        450,
      );
    });

    test('a vertical pull changes the width through the aspect', () {
      // Bottom corners: the grip is on top, so dragging up grows.
      expect(
        DockGeometry.resized(
          400,
          const Offset(0, -10),
          DockCorner.bottomRight,
          2,
        ),
        420,
      );
      expect(
        DockGeometry.resized(400, const Offset(0, 10), DockCorner.topLeft, 2),
        420,
      );
    });
  });

  test('dragged keeps the box inside the window', () {
    const r = Rect.fromLTWH(100, 100, 300, 170);
    expect(
      DockGeometry.dragged(r, const Offset(-500, -500), area),
      const Rect.fromLTWH(0, 0, 300, 170),
    );
    expect(
      DockGeometry.dragged(r, const Offset(5000, 5000), area),
      const Rect.fromLTWH(900, 630, 300, 170),
    );
    expect(
      DockGeometry.dragged(r, const Offset(10, 20), area),
      const Rect.fromLTWH(110, 120, 300, 170),
    );
  });
}
