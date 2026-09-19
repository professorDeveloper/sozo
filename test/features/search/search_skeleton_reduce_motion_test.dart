import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/home/presentation/widgets/home_shared_widgets.dart';

/// What the search tab's skeletons actually paint, in pixels.
///
/// The blocks inside a [ShimmerWrapper] are plain WHITE rectangles, and the
/// only reason they ever read as [ShimmerWrapper.base] is that the sweep is
/// composited through them with `srcIn`. Anything that paints the base colour
/// behind them instead — a ColoredBox, a Container colour — leaves the white
/// on top, and reduce-motion turns the search tab into a wall of white slabs
/// on a near-black app. That failure is invisible to a widget-tree assertion
/// (the tree is right either way; only the paint order is wrong), so this
/// reads the rendered pixel back.
Future<Color> paintedColour(
  WidgetTester tester,
  Widget skeleton, {
  required bool disableAnimations,
}) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: key,
            child: SizedBox(width: 40, height: 40, child: skeleton),
          ),
        ),
      ),
    ),
  );
  // One frame in, so a running shimmer is somewhere in its sweep rather than
  // on the gradient's first pixel.
  await tester.pump(const Duration(milliseconds: 16));

  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  late Color colour;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final bytes = data!.buffer.asUint8List();
    // Centre of the 40x40 boundary: inside the corner radius on every skeleton
    // here, and the calmest part of a sweep.
    const i = ((20 * 40) + 20) * 4;
    colour = Color.fromARGB(bytes[i + 3], bytes[i], bytes[i + 1], bytes[i + 2]);
  });
  return colour;
}

void main() {
  group('reduce motion', () {
    testWidgets('leaves a poster placeholder the skeleton colour', (
      tester,
    ) async {
      // Every cover in the results grid and the trending rail sits on one of
      // these while it loads.
      expect(
        await paintedColour(
          tester,
          const HomeImageSkeleton(),
          disableAnimations: true,
        ),
        ShimmerWrapper.base,
      );
    });

    testWidgets('leaves the genre and results skeleton blocks the same', (
      tester,
    ) async {
      // The shape the search tab builds while genres or results are on their
      // way: one wrapper at the root, plain filled blocks inside it.
      expect(
        await paintedColour(
          tester,
          const ShimmerWrapper(
            child: HomeSkeletonBox(
              width: double.infinity,
              height: double.infinity,
              radius: 10,
            ),
          ),
          disableAnimations: true,
        ),
        ShimmerWrapper.base,
      );
    });
  });

  testWidgets('a running shimmer paints between base and highlight', (
    tester,
  ) async {
    // The still frame has to be the same colour the sweep rests at, or
    // reduce-motion would be a different screen rather than a quieter one.
    final colour = await paintedColour(
      tester,
      const HomeImageSkeleton(),
      disableAnimations: false,
    );
    expect(colour.a, 1.0);
    expect(colour.r, greaterThanOrEqualTo(ShimmerWrapper.base.r));
    expect(colour.r, lessThanOrEqualTo(ShimmerWrapper.highlight.r));
  });
}
