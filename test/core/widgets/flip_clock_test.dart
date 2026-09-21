// A countdown has to count.
//
// What was there was one line of text — "next episode in 3d 4h" — worked out
// when the page was built and never again. It looked identical whether it had
// been computed a second ago or an hour ago, which for the one number on the
// page whose entire value is that it is running is the wrong shape.
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
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

  testWidgets('and seconds are dropped when the wait is days', (tester) async {
    // A digit flipping sixty times a minute beside a number that moves once a
    // day is noise, and it keeps the screen busy for nothing.
    await pump(tester, const Duration(days: 3, hours: 2));
    expect(digits(tester), hasLength(6), reason: 'days, hours, minutes');
  });

  testWidgets('a long wait grows a third card rather than clamping', (
    tester,
  ) async {
    // A clamped "99" would be a lie a viewer cannot see through.
    await pump(tester, const Duration(days: 140, hours: 3));
    expect(digits(tester), hasLength(7), reason: '3 day digits + 4');
    expect(digits(tester).take(3).join(), '140');
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
