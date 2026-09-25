// A long list in a short box used to be a list with its rows cut in half.
//
// The source sheet holds several hundred entries in a window eight rows tall,
// and the window gave no sign of being one: rows were sliced flat against the
// filter field above and the footer below, which reads as a rendering fault
// rather than as "there is more". The fade has to be on the side there is
// something beyond, and only there — a fade over the first row of a list that
// is already at its top is dimming a row for no reason.
//
// Read off the rendered pixels rather than off the widget tree, because the
// tree is identical either way: the mask is composited, and only the composite
// says what it did.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/widgets/edge_fade.dart';

void main() {
  const rowExtent = 40.0;
  const boxHeight = 200.0;
  const boxWidth = 100.0;
  const fade = 20.0;

  final key = GlobalKey();

  /// Opacity of the white rows at a given row from the top of the box, 0 to 1.
  /// The background is black, so a channel value IS the mask's alpha there.
  Future<double> brightnessAt(WidgetTester tester, double y) async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    late double value;
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final bytes = data!.buffer.asUint8List();
      final i = ((y.round() * boxWidth.round()) + 50) * 4;
      value = bytes[i] / 255.0;
    });
    return value;
  }

  /// [settle] off for the fade tests: the two treatments are independent, and
  /// a row scaled down at the edge leaves a gap of background exactly where
  /// the fade is being read, so measuring one through the other measures
  /// neither.
  Future<ScrollController> pump(
    WidgetTester tester,
    int rows, {
    bool settle = false,
  }) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: key,
            child: ColoredBox(
              color: const Color(0xFF000000),
              child: SizedBox(
                height: boxHeight,
                width: boxWidth,
                child: EdgeFade(
                  extent: fade,
                  child: ListView.builder(
                    controller: controller,
                    itemExtent: rowExtent,
                    itemCount: rows,
                    // Solid white rows, edge to edge: anything less than the
                    // full opacity read back is the mask's doing.
                    itemBuilder: (_, i) {
                      const row = ColoredBox(color: Color(0xFFFFFFFF));
                      if (!settle) return row;
                      return ScrollSettle(
                        controller: controller,
                        index: i,
                        extent: rowExtent,
                        child: row,
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return controller;
  }

  testWidgets('at rest at the top, only the bottom edge is faded', (
    tester,
  ) async {
    await pump(tester, 40);
    expect(
      await brightnessAt(tester, 1),
      greaterThan(0.95),
      reason: 'nothing above the first row to suggest',
    );
    expect(
      await brightnessAt(tester, boxHeight - 1),
      lessThan(0.2),
      reason: 'thirty-nine rows below it',
    );
  });

  testWidgets('scrolled into the middle, both edges are faded', (tester) async {
    final c = await pump(tester, 40);
    c.jumpTo(400);
    await tester.pump();
    expect(await brightnessAt(tester, 1), lessThan(0.2));
    expect(await brightnessAt(tester, boxHeight - 1), lessThan(0.2));
    // And the middle is untouched — a fade deeper than its edges would be a
    // vignette over the list rather than an edge on it.
    expect(await brightnessAt(tester, boxHeight / 2), greaterThan(0.95));
  });

  testWidgets('at the end, only the top edge is faded', (tester) async {
    final c = await pump(tester, 40);
    c.jumpTo(c.position.maxScrollExtent);
    await tester.pump();
    expect(await brightnessAt(tester, 1), lessThan(0.2));
    expect(
      await brightnessAt(tester, boxHeight - 1),
      greaterThan(0.95),
      reason: 'the last row is the last row',
    );
  });

  testWidgets('a list that fits is not faded at either end', (tester) async {
    // Four rows in a box that holds five. Fading here would invent a
    // suggestion that there is more.
    await pump(tester, 4);
    expect(await brightnessAt(tester, 1), greaterThan(0.95));
    expect(await brightnessAt(tester, 4 * rowExtent - 1), greaterThan(0.95));
  });

  testWidgets('rows settle to full size away from the edges', (tester) async {
    final c = await pump(tester, 40, settle: true);
    c.jumpTo(400);
    await tester.pump();

    double scaleOf(int index) {
      final t = tester.widget<Transform>(
        find
            .descendant(
              of: find.byWidget(
                tester.widget(
                  find.byWidgetPredicate(
                    (w) => w is ScrollSettle && w.index == index,
                  ),
                ),
              ),
              matching: find.byType(Transform),
            )
            .first,
      );
      // The x scale, not `getMaxScaleOnAxis`: `Transform.scale` leaves z at
      // 1, and the max across all three axes is therefore always 1.
      return t.transform.storage[0];
    }

    // Row 10 sits hard against the top edge at this offset; row 12 is two rows
    // in, which is past the falloff.
    expect(scaleOf(10), lessThan(scaleOf(12)));
    expect(scaleOf(12), closeTo(1.0, 0.001));
  });
}
