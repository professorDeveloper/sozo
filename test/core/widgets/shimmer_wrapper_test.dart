import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shimmer/shimmer.dart';
import 'package:soplay/core/widgets/shimmer_wrapper.dart';

void main() {
  Future<void> pumpSkeleton(WidgetTester tester, {required bool reduced}) {
    return tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: const Directionality(
          textDirection: TextDirection.ltr,
          // A white block, because that is what every skeleton in the app is
          // made of — the palette comes from the wrapper, not from the block.
          child: ShimmerWrapper(
            child: SizedBox(
              width: 100,
              height: 100,
              child: ColoredBox(color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }

  group('ShimmerWrapper', () {
    testWidgets('sweeps when motion is allowed', (tester) async {
      await pumpSkeleton(tester, reduced: false);
      expect(find.byType(Shimmer), findsOneWidget);
    });

    testWidgets('reduce-motion gets a still placeholder, not a slow one', (
      tester,
    ) async {
      // The AnimationController on infinite repeat is the whole cost here, so
      // the point is that no Shimmer exists at all — the skeleton still reads
      // as one, it just does not move.
      await pumpSkeleton(tester, reduced: true);
      expect(find.byType(Shimmer), findsNothing);
      // srcIn, not a colour behind the child: the blocks are white, so a
      // backdrop would leave them white.
      expect(
        tester.widget<ColorFiltered>(find.byType(ColorFiltered)).colorFilter,
        const ColorFilter.mode(ShimmerWrapper.base, BlendMode.srcIn),
      );
    });
  });
}
