// The always-on blurs (nav bars, scroll headers) give way to a plain fill on
// phones that pay for every blurred frame.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/glass/glass_power.dart';
import 'package:soplay/core/glass/reducible_blur.dart';

const _gb = 1024 * 1024 * 1024;

void main() {
  group('the decision', () {
    test('an unanswered reading keeps the blur', () {
      expect(GlassPowerReading.ample.reducesEffects, isFalse);
    });

    test('a capable phone keeps it', () {
      const r = GlassPowerReading(
        memoryBytes: 8 * _gb,
        sdk: 34,
        glEs: 3,
        refreshHz: 120,
      );
      expect(r.reducesEffects, isFalse);
    });

    test('no Vulkan alone loses the refraction but not the blur', () {
      const r = GlassPowerReading(memoryBytes: 6 * _gb, vulkan11: false);
      expect(r.affordsRefraction, isFalse);
      expect(r.reducesEffects, isFalse);
    });

    test('Go flag, small RAM, GL ES 2 or Battery Saver reduce', () {
      expect(const GlassPowerReading(lowRam: true).reducesEffects, isTrue);
      expect(
        const GlassPowerReading(memoryBytes: 2 * _gb).reducesEffects,
        isTrue,
      );
      expect(const GlassPowerReading(glEs: 2).reducesEffects, isTrue);
      expect(const GlassPowerReading(powerSave: true).reducesEffects, isTrue);
    });
  });

  group('ReducibleBlur', () {
    Widget host(GlassPowerReading reading) => Directionality(
      textDirection: TextDirection.ltr,
      child: GlassPower.withReading(
        reading,
        child: const ReducibleBlur(
          sigma: 20,
          reducedFill: Color(0x80000000),
          child: SizedBox(width: 10, height: 10),
        ),
      ),
    );

    testWidgets('blurs when effects are not reduced', (tester) async {
      await tester.pumpWidget(host(GlassPowerReading.ample));
      expect(find.byType(BackdropFilter), findsOneWidget);
    });

    testWidgets('fills instead when they are', (tester) async {
      await tester.pumpWidget(host(const GlassPowerReading(lowRam: true)));
      expect(find.byType(BackdropFilter), findsNothing);
      final fill = tester.widget<ColoredBox>(find.byType(ColoredBox));
      expect(fill.color, const Color(0x80000000));
    });

    testWidgets('flips when Battery Saver turns on', (tester) async {
      await tester.pumpWidget(host(GlassPowerReading.ample));
      expect(find.byType(BackdropFilter), findsOneWidget);
      await tester.pumpWidget(host(const GlassPowerReading(powerSave: true)));
      expect(find.byType(BackdropFilter), findsNothing);
    });
  });
}
