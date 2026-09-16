import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/search/presentation/widgets/search_result_card.dart';

/// Resolves [searchGridDelegate] under a given viewport and text size.
Future<SliverGridDelegateWithFixedCrossAxisCount> resolve(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  late SliverGridDelegate delegate;
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(textScale),
      ),
      child: Builder(
        builder: (context) {
          delegate = searchGridDelegate(context);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return delegate as SliverGridDelegateWithFixedCrossAxisCount;
}

void main() {
  group('columns', () {
    test('follow the width, not the platform', () {
      // An Android tablet, an iPad and a TV are all "mobile", and all three
      // used to get a phone's three enormous columns.
      expect(searchGridColumns(390), 3);
      expect(searchGridColumns(600), 4);
      expect(searchGridColumns(800), 5);
      expect(searchGridColumns(1100), 6);
      expect(searchGridColumns(1600), 7);
    });
  });

  group('tile height', () {
    testWidgets('leaves the poster a true 2:3 at the default text size', (
      tester,
    ) async {
      final delegate = await resolve(tester);
      // 390 wide, 32 of padding, two 10pt gutters, three columns.
      const tile = (390 - 32 - 20) / 3;
      final poster = tile / (2 / 3);
      expect(delegate.crossAxisCount, 3);
      expect(delegate.mainAxisExtent! - poster, closeTo(46.2, 0.01));
    });

    testWidgets('grows with the text scale, and only by the caption', (
      tester,
    ) async {
      // The whole point of the change: the caption used to be a flat 48, and
      // the poster above it is the Expanded one, so one notch up on the system
      // text slider took the shortfall out of every cover in the grid rather
      // than out of the caption.
      final normal = await resolve(tester);
      final large = await resolve(tester, textScale: 2);

      expect(large.crossAxisCount, normal.crossAxisCount);
      expect(large.mainAxisExtent!, greaterThan(normal.mainAxisExtent!));
      // The poster is unaffected — it is sized from the column width, which
      // the text scale does not touch.
      expect(large.mainAxisExtent! - normal.mainAxisExtent!, closeTo(40.2, 0.01));
    });

    testWidgets('is monotonic across the scales people actually pick', (
      tester,
    ) async {
      var previous = 0.0;
      for (final scale in const [0.85, 1.0, 1.15, 1.3, 1.5, 2.0]) {
        final delegate = await resolve(tester, textScale: scale);
        expect(
          delegate.mainAxisExtent!,
          greaterThan(previous),
          reason: 'text scale $scale',
        );
        previous = delegate.mainAxisExtent!;
      }
    });
  });

  group('searchCardHeight', () {
    testWidgets('agrees with the grid it shares a caption with', (
      tester,
    ) async {
      final delegate = await resolve(tester);
      const tile = (390 - 32 - 20) / 3;
      late double height;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(390, 844)),
          child: Builder(
            builder: (context) {
              height = searchCardHeight(tile, context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(height, closeTo(delegate.mainAxisExtent!, 0.01));
    });

    test('falls back to the unscaled caption without a context', () {
      // The cross-search rail still calls it this way. The fallback is the
      // old behaviour, not a new one, so it must not have moved.
      expect(searchCardHeight(116), closeTo(116 / (2 / 3) + 46.2, 0.01));
    });
  });
}
