import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/manga/presentation/widgets/pinch_zoom_scroll.dart';

void main() {
  final controller = ScrollController();

  Widget reader() => MaterialApp(
    home: PinchZoomScroll(
      builder: (context, physics) => ListView.builder(
        controller: controller,
        physics: physics,
        itemCount: 50,
        itemBuilder: (context, i) => SizedBox(height: 400, child: Text('$i')),
      ),
    ),
  );

  double scaleOf(WidgetTester tester) => tester
      .widget<InteractiveViewer>(find.byType(InteractiveViewer))
      .transformationController!
      .value
      .getMaxScaleOnAxis();

  testWidgets('one finger scrolls the pages', (tester) async {
    await tester.pumpWidget(reader());
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(200));
  });

  testWidgets('a pinch zooms, even with its fingers moving up and down', (
    tester,
  ) async {
    await tester.pumpWidget(reader());
    final start = controller.offset;
    final top = await tester.createGesture(pointer: 1);
    final bottom = await tester.createGesture(pointer: 2);
    await top.down(const Offset(200, 280));
    await bottom.down(const Offset(200, 320));
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await top.moveBy(const Offset(0, -10));
      await bottom.moveBy(const Offset(0, 10));
      await tester.pump();
    }
    await top.up();
    await bottom.up();
    await tester.pumpAndSettle();
    expect(scaleOf(tester), greaterThan(1.5));
    expect(controller.offset, start);
  });
}
