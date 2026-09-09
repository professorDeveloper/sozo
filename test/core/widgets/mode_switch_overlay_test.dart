import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/content/content_mode.dart';
import 'package:soplay/core/widgets/mode_switch_overlay.dart';

void main() {
  group('ModeSwitchOverlay', () {
    /// The style the label actually renders with, after Flutter has merged it
    /// with whatever it inherited. `Text` hands the merged result to the
    /// `RichText` it builds, which is where the inherited half becomes
    /// visible.
    TextStyle resolvedLabelStyle(WidgetTester tester) {
      final rich = tester.widget<RichText>(
        find.descendant(
          of: find.byType(Text),
          matching: find.byType(RichText),
        ),
      );
      return rich.text.style!;
    }

    testWidgets('the label carries no inherited error decoration',
        (tester) async {
      // The regression this guards is visible and was reported as "a yellow
      // line when switching to manga".
      //
      // MaterialApp installs `_errorTextStyle` — 48px red monospace with a
      // DOUBLE YELLOW UNDERLINE — as the app-wide default, and only `Material`
      // replaces it. This overlay is inserted straight into the root Overlay,
      // which has no Material above it, and the label's own TextStyle sets a
      // colour and a size but says nothing about `decoration`. A merge keeps
      // what it is not told to replace, so the underline came through.
      await tester.pumpWidget(
        const MaterialApp(home: ModeSwitchOverlay(mode: ContentMode.manga)),
      );
      await tester.pump(const Duration(milliseconds: 300));

      final style = resolvedLabelStyle(tester);
      expect(style.decoration ?? TextDecoration.none, TextDecoration.none);
      expect(style.fontFamily, isNot('monospace'));
    });

    testWidgets('plays and removes itself without leaving an exception',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: ModeSwitchOverlay(mode: ContentMode.manga)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('the cover holds until the new mode has loaded',
        (tester) async {
      // The point of the cover is to hide the reload. Lifting on a fixed timer
      // meant a slow source got uncovered mid-load: the switch looked like it
      // had failed, and the content arrived a second later as if unrelated.
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox.expand();
            },
          ),
        ),
      );

      final reload = Completer<void>();
      final played = ModeSwitchOverlay.play(
        ctx,
        ContentMode.manga,
        until: reload.future,
      );
      await tester.pump();
      expect(find.byType(ModeSwitchOverlay), findsOneWidget);

      // Well past the beat it would have used on its own.
      await tester.pump(ModeSwitchOverlay.minimumBeat * 3);
      expect(
        find.byType(ModeSwitchOverlay),
        findsOneWidget,
        reason: 'lifted before the reload finished',
      );

      reload.complete();
      await tester.pumpAndSettle();
      expect(find.byType(ModeSwitchOverlay), findsNothing);
      await played;
    });

    testWidgets('a load that never finishes does not strand the cover',
        (tester) async {
      // It absorbs input, so a cover that never comes off is a frozen app.
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox.expand();
            },
          ),
        ),
      );

      final played = ModeSwitchOverlay.play(
        ctx,
        ContentMode.manga,
        until: Completer<void>().future,
      );
      await tester.pump();
      await tester.pump(ModeSwitchOverlay.maxWait + const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.byType(ModeSwitchOverlay), findsNothing);
      await played;
    });
  });
}
