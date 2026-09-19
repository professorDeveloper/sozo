import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/content/catalogue.dart';
import 'package:soplay/core/content/content_mode.dart';
import 'package:soplay/core/widgets/sozo_signature.dart';
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

      // Well past the beat it would have used on its own, and short of the
      // wait it gives up after.
      await tester.pump(ModeSwitchOverlay.minimumBeat * 1.6);
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

    testWidgets('the mark has finished being written before the cover lifts',
        (tester) async {
      // The whole point of signing the mark is that the viewer watches it
      // being made. A pen caught mid-stroke as the screen uncovers reads as an
      // animation that was interrupted, not as one that was quick — and the
      // two numbers that decide it, signDuration and minimumBeat, live apart
      // and were changed independently twice.
      await tester.pumpWidget(
        const MaterialApp(home: ModeSwitchOverlay(mode: ContentMode.manga)),
      );

      final liftsAt =
          ModeSwitchOverlay.minimumBeat - ModeSwitchOverlay.exitDuration;
      var elapsed = Duration.zero;
      while (elapsed < liftsAt) {
        await tester.pump(const Duration(milliseconds: 20));
        elapsed += const Duration(milliseconds: 20);
      }

      final signature = tester.widget<SozoSignature>(
        find.byType(SozoSignature),
      );
      expect(
        signature.progress,
        greaterThanOrEqualTo(0.999),
        reason: 'the pen was still writing when the cover started to lift',
      );
    });

    testWidgets("a catalogue's cover names the shelf, not just the catalogue",
        (tester) async {
      // AniList is three shelves and all three share a name, a colour and a
      // logo. Without the mode in the word, asking for manga and asking for
      // light novels produced covers that were pixel for pixel the same.
      await tester.pumpWidget(
        const MaterialApp(
          home: ModeSwitchOverlay(
            mode: ContentMode.novel,
            catalogue: Catalogue.anilistNovel,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      final text = tester.widget<Text>(find.byType(Text)).data!;
      expect(text, contains('CATALOGUE.ANILIST'));
      expect(
        text,
        contains('MODE.NOVEL'),
        reason: 'the three AniList shelves are told apart only by the mode',
      );
    });
  });

  group('ModeSwitchOverlay.revealPath', () {
    const size = Size(390, 844);
    // The worst case the overlay actually hands it: a chip in a corner, so
    // the shape has to reach diagonally across the whole screen.
    const corner = Offset(24, 800);
    final reach = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ].map((c) => (c - corner).distance).reduce((a, b) => a > b ? a : b);

    test('every mode covers all four corners once it is open', () {
      for (final mode in ContentMode.values) {
        final path = ModeSwitchOverlay.revealPath(
          mode: mode,
          center: corner,
          reach: reach,
          progress: 1,
        );
        for (final c in [
          const Offset(1, 1),
          Offset(size.width - 1, 1),
          Offset(1, size.height - 1),
          Offset(size.width - 1, size.height - 1),
        ]) {
          expect(
            path.contains(c),
            isTrue,
            reason: '$mode leaves $c showing the screen it replaced',
          );
        }
      }
    });

    test('nothing is revealed before it starts', () {
      for (final mode in ContentMode.values) {
        final path = ModeSwitchOverlay.revealPath(
          mode: mode,
          center: corner,
          reach: reach,
          progress: 0,
        );
        expect(path.contains(corner), isFalse, reason: '$mode');
      }
    });

    test('the three modes do not arrive in the same shape', () {
      Rect boundsAt(ContentMode mode) => ModeSwitchOverlay.revealPath(
        mode: mode,
        center: size.center(Offset.zero),
        reach: 400,
        progress: 0.5,
      ).getBounds();

      final video = boundsAt(ContentMode.video);
      final manga = boundsAt(ContentMode.manga);
      final novel = boundsAt(ContentMode.novel);
      expect(video, isNot(manga));
      expect(video, isNot(novel));
      expect(manga, isNot(novel));
      // Watch is an iris, so it is as tall as it is wide. The novel spread
      // opens at a vertical spine, so half way through it is still taller
      // than it is wide — the pages are travelling outwards.
      expect(video.width, closeTo(video.height, 0.01));
      expect(novel.height, greaterThan(novel.width));
    });
  });
}
