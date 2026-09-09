import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/widgets/item_appear.dart';

void main() {
  // MaterialApp draws its own route transitions, so the finders have to be
  // scoped to the widget under test.
  final ownFade = find.descendant(
    of: find.byType(ItemAppear),
    matching: find.byType(FadeTransition),
  );
  final ownTransform = find.descendant(
    of: find.byType(ItemAppear),
    matching: find.byType(Transform),
  );

  Matrix4 matrixOf(WidgetTester tester) =>
      tester.widget<Transform>(ownTransform.first).transform;

  Future<void> pumpCard(
    WidgetTester tester, {
    int index = 0,
    int columns = 1,
    Axis axis = Axis.vertical,
    TextDirection direction = TextDirection.ltr,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: direction,
          child: Scaffold(
            body: ItemAppear(
              index: index,
              columns: columns,
              axis: axis,
              child: const SizedBox(width: 100, height: 100),
            ),
          ),
        ),
      ),
    );
  }

  group('ItemAppear', () {
    testWidgets('the card is there from the first frame, only faded and small',
        (tester) async {
      // An entrance that starts from "not built" would leave a grid of holes
      // for anyone whose scroll outruns the animation.
      await pumpCard(tester);
      expect(find.byType(SizedBox), findsWidgets);

      final fade = tester.widget<FadeTransition>(ownFade);
      expect(fade.opacity.value, lessThan(1.0));
      // Starts scaled down and offset, not at rest.
      expect(matrixOf(tester), isNot(Matrix4.identity()));

      await tester.pumpAndSettle();
      expect(fade.opacity.value, 1.0);
    });

    testWidgets('it settles at exactly its resting transform', (tester) async {
      // A card left at 0.999 scale is a card rendering through a filter for
      // the rest of its life.
      await pumpCard(tester);
      await tester.pumpAndSettle();
      expect(matrixOf(tester), Matrix4.identity());
    });

    testWidgets('travel is a fixed distance, not a fraction of the card',
        (tester) async {
      // The bug this replaces: SlideTransition moves a fraction of the child's
      // own size, so the same entrance travelled 14px in one grid and 11px in
      // another for no reason anyone chose.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                ItemAppear(index: 0, child: SizedBox(width: 50, height: 50)),
                ItemAppear(index: 0, child: SizedBox(width: 50, height: 300)),
              ],
            ),
          ),
        ),
      );
      final transforms = tester
          .widgetList<Transform>(ownTransform)
          .map((t) => t.transform.getTranslation().y)
          .toList();
      expect(transforms, hasLength(2));
      expect(transforms.first, transforms.last,
          reason: 'a tall card and a short one must travel the same distance');
      expect(transforms.first, greaterThan(0));
    });

    testWidgets('a rail comes in from the side, not from below',
        (tester) async {
      await pumpCard(tester, axis: Axis.horizontal);
      final t = matrixOf(tester).getTranslation();
      expect(t.y, 0);
      expect(t.x, greaterThan(0), reason: 'LTR rails come from the right');
    });

    testWidgets('and from the other side in RTL', (tester) async {
      await pumpCard(tester, axis: Axis.horizontal,
          direction: TextDirection.rtl);
      expect(matrixOf(tester).getTranslation().x, lessThan(0));
    });

    testWidgets('a row arrives as a row, not column by column',
        (tester) async {
      // Three columns build indices 0, 1, 2 as one row. Stepping them by a
      // flat index put a visible tear between the first column and the third.
      await pumpCard(tester, index: 2, columns: 3);
      await tester.pump(ItemAppear.rowStep);
      // Still within the first row, so it is already moving.
      expect(matrixOf(tester), isNot(Matrix4.identity()));
      await tester.pumpAndSettle();
      expect(matrixOf(tester), Matrix4.identity());
    });

    testWidgets('a later card is not made to wait behind the first screenful',
        (tester) async {
      // Past the stagger limit the delay would be attached to a card the user
      // has already scrolled to, which reads as the grid lagging the finger.
      await pumpCard(tester, index: 400, columns: 3);
      await tester.pump(ItemAppear.duration);
      expect(matrixOf(tester), Matrix4.identity());
    });

    testWidgets('no card waits longer than maxDelay', (tester) async {
      // Row 11 of a single-column list would be 11 × rowStep = 495ms behind
      // the first if the cap were not there, and a card that starts moving
      // half a second after it appeared has already been read as static.
      await pumpCard(tester, index: ItemAppear.staggerLimitDefault - 1);

      // First pump lets the delay timer fire, the second gives the controller
      // a tick to act on it.
      await tester.pump(ItemAppear.maxDelay + const Duration(milliseconds: 10));
      await tester.pump(const Duration(milliseconds: 150));

      final fade = tester.widget<FadeTransition>(ownFade);
      expect(fade.opacity.value, greaterThan(0),
          reason: 'it should already be arriving by maxDelay');

      await tester.pumpAndSettle();
      expect(matrixOf(tester), Matrix4.identity());
    });

    testWidgets('nothing animates when the OS asks for no animation',
        (tester) async {
      // Inside MaterialApp, not around it: MaterialApp installs a MediaQuery
      // of its own from the window and would overwrite one set above it.
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: const Scaffold(
                body: ItemAppear(index: 3, child: Text('plain')),
              ),
            ),
          ),
        ),
      );
      expect(find.text('plain'), findsOneWidget);
      expect(ownFade, findsNothing);
      expect(ownTransform, findsNothing);
    });
  });

  group('columnsForMaxExtent', () {
    test('mirrors what the max-extent delegate settles on', () {
      // A stagger that thinks there are three columns in a four-column grid
      // sweeps diagonally across it.
      expect(columnsForMaxExtent(400, 142, spacing: 10), 3);
      expect(columnsForMaxExtent(142, 142), 1);
      expect(columnsForMaxExtent(0, 142), 1);
      expect(columnsForMaxExtent(1200, 142, spacing: 10), 8);
    });
  });
}
