import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/main/presentation/widgets/scroll_compact_navigation.dart';

FixedScrollMetrics metrics(
  double pixels, {
  double max = 1200,
  AxisDirection axis = AxisDirection.down,
}) => FixedScrollMetrics(
  minScrollExtent: 0,
  maxScrollExtent: max,
  pixels: pixels,
  viewportDimension: 600,
  axisDirection: axis,
  devicePixelRatio: 1,
);

void main() {
  testWidgets(
    'only deliberate long vertical scroll collapses; reverse and top restore',
    (tester) async {
      final controller = NavigationScrollState();
      addTearDown(controller.dispose);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      final context = tester.element(find.byType(SizedBox).first);
      controller.onScroll(
        ScrollStartNotification(
          metrics: metrics(0),
          context: context,
          dragDetails: DragStartDetails(),
        ),
      );
      void update(
        double pixels,
        double delta, {
        double max = 1200,
        AxisDirection axis = AxisDirection.down,
      }) => controller.onScroll(
        ScrollUpdateNotification(
          metrics: metrics(pixels, max: max, axis: axis),
          context: context,
          scrollDelta: delta,
        ),
      );
      update(40, 40);
      expect(controller.value, isFalse);
      update(100, 60);
      expect(controller.value, isTrue);
      update(95, -5);
      expect(
        controller.value,
        isTrue,
        reason: 'Small reversals should not flicker',
      );
      update(70, -25);
      expect(controller.value, isFalse);
      update(140, 70);
      expect(controller.value, isTrue);
      update(0, -140);
      expect(controller.value, isFalse);
      update(150, 150, axis: AxisDirection.right);
      expect(controller.value, isFalse);
      update(50, 50, max: 60);
      expect(controller.value, isFalse);
      controller.expand();
      update(200, 200);
      expect(
        controller.value,
        isFalse,
        reason: 'Programmatic scrolling is ignored',
      );
    },
  );

  testWidgets(
    'compact bar preserves tap targets and selection without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var compact = false;
      int? selected;
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return Scaffold(
                body: Align(
                  alignment: Alignment.bottomCenter,
                  child: ScrollCompactNavigation(
                    compact: compact,
                    expanded: const SizedBox(
                      width: 360,
                      height: 100,
                      child: Text('Expanded navigation'),
                    ),
                    items: const [
                      NavigationDestination(
                        icon: Icon(Icons.home),
                        label: 'Home',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.search),
                        label: 'Search',
                      ),
                    ],
                    selectedIndex: 0,
                    onSelected: (i) => selected = i,
                  ),
                ),
              );
            },
          ),
        ),
      );
      rebuild(() => compact = true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      final button = find.ancestor(
        of: find.byIcon(Icons.search),
        matching: find.byType(InkWell),
      );
      expect(tester.getSize(button), const Size(48, 48));
      await tester.tap(button);
      expect(selected, 1);
      rebuild(() => compact = false);
      await tester.pumpAndSettle();
      expect(find.text('Expanded navigation').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
