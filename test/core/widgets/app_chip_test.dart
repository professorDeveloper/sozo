import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/widgets/app_chip.dart';

void main() {
  Future<void> pumpChip(
    WidgetTester tester, {
    required bool selected,
    VoidCallback? onTap,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AppChip(
              label: '1080p',
              selected: selected,
              icon: Icons.hd_rounded,
              onTap: onTap ?? () {},
            ),
          ),
        ),
      ),
    );
  }

  final chipBox = find.descendant(
    of: find.byType(AppChip),
    matching: find.byType(AnimatedContainer),
  );

  group('AppChip', () {
    testWidgets('a screen reader hears a button and its selection state', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpChip(tester, selected: true);
      expect(
        tester.getSemantics(find.byType(AppChip)),
        isSemantics(isButton: true, isSelected: true, hasTapAction: true),
      );

      await pumpChip(tester, selected: false);
      expect(
        tester.getSemantics(find.byType(AppChip)),
        isSemantics(isButton: true, isSelected: false),
      );
      handle.dispose();
    });

    testWidgets('selection crossfades instead of cutting', (tester) async {
      // The painted fill, not the AnimatedContainer's target: the target jumps
      // on the frame the selection changes, which is exactly what this test
      // has to look past.
      Color? paintedFill() =>
          (tester
                      .widgetList<DecoratedBox>(
                        find.descendant(
                          of: find.byType(AppChip),
                          matching: find.byType(DecoratedBox),
                        ),
                      )
                      .firstWhere(
                        (box) => box.position == DecorationPosition.background,
                      )
                      .decoration
                  as BoxDecoration)
              .color;

      await pumpChip(tester, selected: false);
      final unselected = paintedFill();
      expect(tester.widget<AnimatedContainer>(chipBox), isNotNull);

      await pumpChip(tester, selected: true);
      await tester.pumpAndSettle();
      final settled = paintedFill();
      expect(settled, isNot(unselected));

      // Halfway back the fill is neither end colour, i.e. the two chips in a
      // row hand over to each other instead of both cutting.
      await pumpChip(tester, selected: false);
      await tester.pump(const Duration(milliseconds: 75));
      final midway = paintedFill();
      expect(midway, isNot(settled));
      expect(midway, isNot(unselected));
    });

    testWidgets('still calls back on tap', (tester) async {
      var taps = 0;
      await pumpChip(tester, selected: false, onTap: () => taps++);
      await tester.tap(find.byType(AppChip));
      expect(taps, 1);
    });
  });
}
