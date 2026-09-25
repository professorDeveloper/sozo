// A countdown has to count.
//
// What was there was one line of text — "next episode in 3d 4h" — worked out
// when the page was built and never again. It looked identical whether it had
// been computed a second ago or an hour ago, which for the one number on the
// page whose entire value is that it is running is the wrong shape.
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soplay/core/widgets/flip_clock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  /// A clock the test drives, because a widget test's own does not advance —
  /// and "does it tick" is the whole behaviour.
  late DateTime clock;
  setUp(() => clock = DateTime(2026, 1, 1, 12));

  Future<void> pump(
    WidgetTester tester,
    Duration ahead, {
    VoidCallback? onFinished,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: FlipClock(
            target: clock.add(ahead),
            now: () => clock,
            onFinished: onFinished,
          ),
        ),
      ),
    ),
  );

  /// Moves the clock and lets the widget notice.
  Future<void> advance(WidgetTester tester, Duration by) async {
    clock = clock.add(by);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Every digit currently on screen, in order.
  List<String> digits(WidgetTester tester) => tester
      .widgetList<FlipDigit>(find.byType(FlipDigit))
      .map((d) => d.digit)
      .toList();

  testWidgets('it ticks', (tester) async {
    await pump(tester, const Duration(minutes: 5));
    final before = digits(tester).join();
    await advance(tester, const Duration(seconds: 1));
    expect(digits(tester).join(), isNot(before));
  });

  testWidgets('days are dropped when there are none', (tester) async {
    // A pair of zeros on the left claims a precision the rest of the row
    // already has, and costs the space the seconds need.
    await pump(tester, const Duration(hours: 5));
    expect(find.text('DAYS'), findsNothing);
    expect(digits(tester), hasLength(6), reason: 'hours, minutes, seconds');
  });

  testWidgets('and seconds are kept even when the wait is days', (
    tester,
  ) async {
    // They used to be dropped past a day, on the grounds that a digit flipping
    // sixty times a minute beside a number that moves once a day is noise. The
    // second card is the only part of this that is visibly alive; without it a
    // clock four days out is a row of numbers that could as easily be stopped.
    await pump(tester, const Duration(days: 3, hours: 2));
    expect(
      digits(tester),
      hasLength(8),
      reason: 'days, hours, minutes, seconds',
    );
  });

  testWidgets('a long wait grows a third card rather than clamping', (
    tester,
  ) async {
    // A clamped "99" would be a lie a viewer cannot see through.
    await pump(tester, const Duration(days: 140, hours: 3));
    expect(digits(tester), hasLength(9), reason: '3 day digits + 6');
    expect(digits(tester).take(3).join(), '140');
  });

  group('the flip is a split-flap, not a card turning over', () {
    const w = 26.0;
    const h = 36.0;

    /// One card, on white, with room around it for a leaf that overflows.
    const pad = 12.0;
    final boundary = GlobalKey();

    Future<void> pumpDigit(WidgetTester tester, String digit) =>
        tester.pumpWidget(
          Directionality(
            // Prefixed: easy_localization pulls in intl, which has a
            // TextDirection of its own with different members.
            textDirection: ui.TextDirection.ltr,
            child: Center(
              child: RepaintBoundary(
                key: boundary,
                child: ColoredBox(
                  color: const Color(0xFFFFFFFF),
                  child: Padding(
                    padding: const EdgeInsets.all(pad),
                    child: FlipDigit(digit: digit),
                  ),
                ),
              ),
            ),
          ),
        );

    /// True when anything has been painted over the white, at this point.
    Future<bool> painted(WidgetTester tester, double x, double y) async {
      final object =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      var dirty = false;
      await tester.runAsync(() async {
        final image = await object.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        final bytes = data!.buffer.asUint8List();
        final stride = (w + pad * 2).round() * 4;
        final i = y.round() * stride + x.round() * 4;
        dirty = bytes[i] < 240;
      });
      return dirty;
    }

    /// Every glyph painted for one card. A settled card paints one; a card
    /// mid-flip paints three — the new digit's top, the old digit's bottom and
    /// the leaf in flight between them.
    List<String> facesOfUnits(WidgetTester tester) => tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(FlipDigit).last,
            matching: find.byType(Text),
          ),
        )
        .map((t) => t.data ?? '')
        .toList();

    testWidgets('a settled card paints one face', (tester) async {
      await pump(tester, const Duration(minutes: 5));
      expect(facesOfUnits(tester), hasLength(1));
    });

    testWidgets('and mid-flip the new digit is already on screen', (
      tester,
    ) async {
      await pump(tester, const Duration(minutes: 5, seconds: 8));
      expect(facesOfUnits(tester), ['8']);

      clock = clock.add(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 110));

      final faces = facesOfUnits(tester);
      expect(faces, hasLength(3), reason: 'new top, old bottom, falling leaf');
      expect(faces, contains('7'), reason: 'the digit being arrived at');
      expect(faces, contains('8'), reason: 'the digit being left behind');
    });

    testWidgets('and every layer is half a card, not a whole one', (
      tester,
    ) async {
      // The bug this exists for. Under `StackFit.expand` a non-positioned
      // child is given TIGHT constraints, which overrules the half-height box
      // inside each layer and leaves `Align.heightFactor` nothing to
      // shrink-wrap — so both static layers painted the WHOLE card, the old
      // digit's face covered the new one completely, and the digit changed in
      // one frame at the end. The tree was identical either way; only the
      // geometry says which.
      await pumpDigit(tester, '8');
      await pumpDigit(tester, '7');
      await tester.pump(const Duration(milliseconds: 110));

      final clips = find.descendant(
        of: find.byType(FlipDigit),
        matching: find.byType(ClipRect),
      );
      expect(clips, findsNWidgets(3));
      for (var i = 0; i < 3; i++) {
        expect(
          tester.getSize(clips.at(i)),
          const Size(w, h / 2),
          reason: 'layer $i is not half a card',
        );
      }
    });

    testWidgets('and the flap comes towards the viewer, not away', (
      tester,
    ) async {
      // The other bug, and the other one no widget-tree assertion can see.
      // `rotateX` with a POSITIVE angle brings the top of a widget towards the
      // viewer; written negative, the flap folds backwards into the card. Both
      // silhouettes shrink to a line, so the only thing that tells them apart
      // is what the perspective does to the free edge: coming towards you it
      // grows past the sides of the card, going away it shrinks inside them.
      await pumpDigit(tester, '8');
      // Nothing outside the card at rest, or the probe proves nothing.
      expect(await painted(tester, pad - 2, pad + h / 4), isFalse);

      await pumpDigit(tester, '7');
      var overhung = false;
      for (var frame = 0; frame < 12 && !overhung; frame++) {
        await tester.pump(const Duration(milliseconds: 20));
        for (var y = pad + 2; y < pad + h / 2 && !overhung; y += 2) {
          overhung = await painted(tester, pad - 2, y);
        }
      }
      expect(
        overhung,
        isTrue,
        reason: 'the leaf never overflowed the card it came out of',
      );
    });

    testWidgets('and settles back to one face', (tester) async {
      await pump(tester, const Duration(minutes: 5, seconds: 8));
      await advance(tester, const Duration(seconds: 1));
      // Past the turn, so the leaf is gone rather than parked at zero degrees:
      // a card left in its animated form is three layers and a perspective
      // matrix, once per card, for as long as the page is open.
      await tester.pump(const Duration(milliseconds: 400));
      expect(facesOfUnits(tester), ['7']);
    });
  });

  testWidgets('a target in the past reads zero, not a negative', (
    tester,
  ) async {
    await pump(tester, const Duration(seconds: -90));
    expect(digits(tester).join(), '000000');
  });

  testWidgets('finishing is announced once, not once a tick', (tester) async {
    var calls = 0;
    await pump(tester, const Duration(seconds: 2), onFinished: () => calls++);
    await advance(tester, const Duration(seconds: 3));
    expect(calls, 1);
    await advance(tester, const Duration(seconds: 3));
    expect(calls, 1, reason: 'it kept announcing after zero');
  });

  testWidgets('the timer stops with the widget', (tester) async {
    // A periodic timer outliving its State is the classic way a countdown
    // leaks; the test framework fails the test if one is still pending.
    await pump(tester, const Duration(minutes: 5));
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(const Duration(seconds: 2));
  });
}
