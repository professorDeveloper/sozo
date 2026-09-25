import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/system/responsive.dart';

void main() {
  group('SozoWidth', () {
    test('bands split on the window width, not on the host OS', () {
      expect(SozoWidth.fromWidth(0), SozoWidth.compact);
      expect(SozoWidth.fromWidth(599), SozoWidth.compact);
      // A desktop window dragged this narrow is a phone layout, whatever
      // Platform.isWindows says.
      expect(SozoWidth.fromWidth(599).isAtLeastMedium, isFalse);

      expect(SozoWidth.fromWidth(600), SozoWidth.medium);
      expect(SozoWidth.fromWidth(899), SozoWidth.medium);
      expect(SozoWidth.fromWidth(600).isAtLeastMedium, isTrue);

      // And an iPad gets the wide layout it always had the room for.
      expect(SozoWidth.fromWidth(900), SozoWidth.expanded);
      expect(SozoWidth.fromWidth(1366).isExpanded, isTrue);
    });

    testWidgets('of() reads the current MediaQuery width', (tester) async {
      late SozoWidth seen;
      Future<void> pumpAt(double width) => tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(size: Size(width, 800)),
          child: Builder(
            builder: (context) {
              seen = SozoWidth.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      await pumpAt(420);
      expect(seen, SozoWidth.compact);

      // The point of the helper: the same running app changes band when the
      // window is resized.
      await pumpAt(1100);
      expect(seen, SozoWidth.expanded);
    });

    testWidgets('fitsTwoPane is the rail-plus-detail floor', (tester) async {
      late bool fits;
      Future<void> pumpAt(double width) => tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(size: Size(width, 800)),
          child: Builder(
            builder: (context) {
              fits = SozoWidth.fitsTwoPane(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      await pumpAt(1199);
      expect(fits, isFalse);
      await pumpAt(1200);
      expect(fits, isTrue);
    });
  });

  group('HoverTap', () {
    tearDown(() => debugHoverTapIsDesktopOverride = null);

    // flutter test runs on the host, so isDesktopPlatform is true here and the
    // phone branch — what almost every call site actually ships — has to be
    // selected explicitly.
    Future<void> pumpTap(
      WidgetTester tester, {
      required bool desktop,
      VoidCallback? onTap,
      bool disableAnimations = false,
    }) {
      debugHoverTapIsDesktopOverride = desktop;
      return tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: disableAnimations),
            child: Center(
              child: HoverTap(
                onTap: onTap ?? () {},
                child: const SizedBox(width: 120, height: 180),
              ),
            ),
          ),
        ),
      );
    }

    final ownScale = find.descendant(
      of: find.byType(HoverTap),
      matching: find.byType(AnimatedScale),
    );

    testWidgets('a poster dips while the finger is down', (tester) async {
      await pumpTap(tester, desktop: false);
      expect(tester.widget<AnimatedScale>(ownScale).scale, 1.0);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(HoverTap)),
      );
      await tester.pump();
      expect(tester.widget<AnimatedScale>(ownScale).scale, lessThan(1.0));
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.descendant(
                of: find.byType(HoverTap),
                matching: find.byType(AnimatedOpacity),
              ),
            )
            .opacity,
        lessThan(1.0),
      );

      await gesture.up();
      await tester.pump();
      expect(tester.widget<AnimatedScale>(ownScale).scale, 1.0);
    });

    testWidgets('the press releases when the gesture is cancelled', (
      tester,
    ) async {
      await pumpTap(tester, desktop: false);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(HoverTap)),
      );
      await tester.pump();
      expect(tester.widget<AnimatedScale>(ownScale).scale, lessThan(1.0));

      // Dragging off the card is a scroll, not a tap: the poster must settle
      // back rather than stay stuck small.
      await gesture.moveBy(const Offset(0, 300));
      await gesture.up();
      await tester.pump();
      expect(tester.widget<AnimatedScale>(ownScale).scale, 1.0);
    });

    testWidgets('reduce-motion drops the press machinery entirely', (
      tester,
    ) async {
      await pumpTap(tester, desktop: false, disableAnimations: true);
      expect(ownScale, findsNothing);

      var taps = 0;
      await pumpTap(
        tester,
        desktop: false,
        disableAnimations: true,
        onTap: () => taps++,
      );
      await tester.tap(find.byType(HoverTap));
      expect(taps, 1);
    });

    testWidgets('announces itself as a button, not as artwork', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpTap(tester, desktop: false);
      expect(
        tester.getSemantics(find.byType(HoverTap)),
        isSemantics(isButton: true, hasTapAction: true),
      );
      handle.dispose();
    });

    testWidgets('desktop can be reached and fired from the keyboard', (
      tester,
    ) async {
      var taps = 0;
      await pumpTap(tester, desktop: true, onTap: () => taps++);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final focus = Focus.of(
        tester.element(find.byType(SizedBox).first),
        scopeOk: true,
      );
      expect(focus.hasFocus, isTrue, reason: 'Tab never reached the card');

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('Space bubbles past a focused card instead of activating it', (
      tester,
    ) async {
      // Space is play/pause in the player and page-forward in the reader, and
      // both handlers sit ABOVE the posters. If the card reports Space as
      // handled, Tab-ing onto one kills the app's most important key.
      debugHoverTapIsDesktopOverride = true;
      var taps = 0;
      var spaceSeenAbove = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Focus(
            // A pure ancestor key handler: it must not compete for focus with
            // the card, only receive what the card lets through.
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: (_, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.space) {
                spaceSeenAbove++;
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Center(
              child: HoverTap(
                onTap: () => taps++,
                child: const SizedBox(width: 120, height: 180),
              ),
            ),
          ),
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final focus = Focus.of(
        tester.element(find.byType(SizedBox).first),
        scopeOk: true,
      );
      expect(focus.hasFocus, isTrue, reason: 'Tab never reached the card');

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(taps, 0, reason: 'Space must not activate the card');
      expect(spaceSeenAbove, 1, reason: 'Space never reached the ancestor');
    });
  });

  group('showAdaptiveModal', () {
    /// Drives the real entry point rather than a predicate, because the whole
    /// defect was that the *route* chosen for ~37 call sites flipped.
    Future<void> pumpModal(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      late BuildContext hostContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              hostContext = context;
              return const Scaffold();
            },
          ),
        ),
      );
      unawaited(
        showAdaptiveModal<void>(
          context: hostContext,
          builder: (_) => const SizedBox(height: 120),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a phone in landscape still gets a bottom sheet', (
      tester,
    ) async {
      // 844x390 is an ordinary phone turned sideways — and it is 844dp WIDE, so
      // any width-based test calls it a tablet. It is exactly the geometry the
      // subtitle, audio-track and quality pickers are used in.
      await pumpModal(tester, const Size(844, 390));
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('a tablet in portrait gets the centred dialog', (tester) async {
      await pumpModal(tester, const Size(834, 1112));
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('a tablet in landscape gets the centred dialog', (
      tester,
    ) async {
      // Same device as above, rotated: unlike a phone it is roomy on BOTH axes,
      // so the answer must not change with the orientation.
      await pumpModal(tester, const Size(1112, 834));
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('a window squeezed narrow falls back to the sheet', (
      tester,
    ) async {
      await pumpModal(tester, const Size(500, 900));
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
    });

    Future<double> sheetHeight(WidgetTester tester, double content) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      late BuildContext hostContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              hostContext = context;
              return const Scaffold();
            },
          ),
        ),
      );
      unawaited(
        showAdaptiveModal<void>(
          context: hostContext,
          showDragHandle: true,
          builder: (_) => SingleChildScrollView(
            child: SizedBox(height: content),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester.getSize(find.byType(BottomSheet)).height;
    }

    testWidgets('a long sheet opens past 9/16 of the screen', (tester) async {
      final height = await sheetHeight(tester, 2000);
      expect(height, greaterThan(800 * 9 / 16));
      expect(height, lessThanOrEqualTo(800 * 0.9));
    });

    testWidgets('a short sheet stays as tall as its content', (tester) async {
      final height = await sheetHeight(tester, 150);
      expect(height, lessThan(300));
    });
  });
}
