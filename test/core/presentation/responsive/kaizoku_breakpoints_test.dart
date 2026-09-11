import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/presentation/responsive/kaizoku_breakpoints.dart';

void main() {
  group('KaizokuBreakpoints', () {
    test('verifies constant threshold hierarchy', () {
      expect(KaizokuBreakpoints.compact, 600.0);
      expect(KaizokuBreakpoints.medium, 1024.0);
      expect(KaizokuBreakpoints.large, 1440.0);
      expect(KaizokuBreakpoints.ultra, 1920.0);
      expect(KaizokuBreakpoints.compact < KaizokuBreakpoints.medium, isTrue);
      expect(KaizokuBreakpoints.medium < KaizokuBreakpoints.large, isTrue);
    });

    testWidgets('KaizokuResponsiveLayout renders mobile builder on compact screen', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: KaizokuResponsiveLayout(
            mobile: (context) => const Text('Mobile Layout'),
            tablet: (context) => const Text('Tablet Layout'),
            desktop: (context) => const Text('Desktop Layout'),
          ),
        ),
      );

      expect(find.text('Mobile Layout'), findsOneWidget);
      expect(find.text('Tablet Layout'), findsNothing);
      expect(find.text('Desktop Layout'), findsNothing);
    });

    testWidgets('KaizokuResponsiveLayout renders tablet builder on medium screen', (tester) async {
      tester.view.physicalSize = const Size(768, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: KaizokuResponsiveLayout(
            mobile: (context) => const Text('Mobile Layout'),
            tablet: (context) => const Text('Tablet Layout'),
            desktop: (context) => const Text('Desktop Layout'),
          ),
        ),
      );

      // On mobile OS or fallback, 768px resolves to tablet
      expect(find.text('Tablet Layout'), findsOneWidget);
    });

    testWidgets('KaizokuResponsiveLayout renders desktop builder on wide screen', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: KaizokuResponsiveLayout(
            mobile: (context) => const Text('Mobile Layout'),
            tablet: (context) => const Text('Tablet Layout'),
            desktop: (context) => const Text('Desktop Layout'),
          ),
        ),
      );

      expect(find.text('Desktop Layout'), findsOneWidget);
    });
  });
}
