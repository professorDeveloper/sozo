import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/widgets/poster_hero.dart';
import 'package:soplay/features/detail/presentation/widgets/detail_hero.dart';

/// Runs [body] as if the app were on [platform], and puts the override back
/// before the test ends.
///
/// Reset here rather than in an `addTearDown`: the test binding checks that no
/// foundation debug variable survived the body, and it checks before tear-downs
/// run, so a tear-down reset fails every test that uses one.
Future<void> _onPlatform(
  TargetPlatform platform,
  Future<void> Function() body,
) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

/// Pushes the header onto a second route, which is the only place it is ever
/// seen — the bloom reads `ModalRoute.of(context).animation`, and the first
/// route of an app has nothing to arrive from.
///
/// A null thumbnail on purpose: it keeps the whole test off the network while
/// leaving [PosterHero] — the thing the bloom wraps — exactly where it is.
Future<void> _openHeader(WidgetTester tester) async {
  final nav = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: nav,
      home: const Scaffold(body: Text('behind')),
    ),
  );
  nav.currentState!.push(
    MaterialPageRoute<void>(
      builder: (_) => const Scaffold(
        body: DetailHeroBackground(
          thumbnail: null,
          title: 'Fixture',
          // `hasFlight` is `heroTag != null` (detail_hero.dart:75), and it is
          // what decides whether the scrims subscribe to the route animation
          // at all. Without a tag the fade is off for everyone and a gate test
          // would pass on both platforms for the wrong reason.
          heroTag: 'fixture',
        ),
      ),
    ),
  );
}

/// The blur and the grow live in one `ImageFiltered`, so its presence is the
/// bloom's presence: gated off, the widget is not built at all.
Finder get _bloom => find.byType(ImageFiltered);

void main() {
  testWidgets('the header blooms in on Android', (tester) async {
    await _onPlatform(TargetPlatform.android, () async {
      await _openHeader(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        tester.widget<ImageFiltered>(_bloom).enabled,
        isTrue,
        reason: 'mid-arrival the poster should still be resolving into focus',
      );

      await tester.pumpAndSettle();
      expect(
        tester.widget<ImageFiltered>(_bloom).enabled,
        isFalse,
        reason: 'a settled page pays for no filter',
      );
    });
  });

  testWidgets('the header does not bloom on iOS', (tester) async {
    await _onPlatform(TargetPlatform.iOS, () async {
      await _openHeader(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(_bloom, findsNothing);

      await tester.pumpAndSettle();
      expect(_bloom, findsNothing);
      // Gated the effect, not the artwork: the poster is still the thing in
      // the header, it simply arrives with the Cupertino page around it.
      expect(find.byType(PosterHero), findsOneWidget);
    });
  });

  testWidgets('an iOS back swipe does not blur the poster under the thumb', (
    tester,
  ) async {
    // The defect this gate exists for. On iOS the route is the platform page,
    // and Cupertino's edge gesture drives that route's own animation — the
    // same animation the bloom reads. Ungated, every drag from the left edge
    // runs an 18px blur and a 10% grow across the largest image on the screen,
    // backwards, one frame per finger movement.
    await _onPlatform(TargetPlatform.iOS, () async {
      await _openHeader(tester);
      await tester.pumpAndSettle();

      final swipe = await tester.startGesture(const Offset(2, 300));
      await swipe.moveBy(const Offset(200, 0));
      await tester.pump();
      expect(_bloom, findsNothing, reason: 'mid-drag');

      await swipe.moveBy(const Offset(300, 0));
      await tester.pump();
      expect(_bloom, findsNothing, reason: 'further into the drag');

      await swipe.up();
      await tester.pumpAndSettle();
      // Proves the drag was a live back gesture rather than a dead touch —
      // without this the assertions above would hold for a screen nothing
      // happened on.
      expect(find.text('behind'), findsOneWidget);
    });
  });

  /// The scrims are wrapped in a `FadeTransition` only when they are riding
  /// the route animation; gated off, the state returns its child untouched.
  /// So the presence of one under the header is the subscription's presence.
  Finder scrimFade() => find.descendant(
    of: find.byType(DetailHeroBackground),
    matching: find.byType(FadeTransition),
  );

  testWidgets('the header scrims do not ride the route animation on iOS', (
    tester,
  ) async {
    // The bloom was gated and this was not, so half the arrival animation
    // still played backwards under the thumb: on iOS the route is a Cupertino
    // page, its animation IS the edge swipe, and the header gradients faded
    // out as the finger moved on a drag the user could still abandon. Both
    // ride the same controller, so both answer to the same gate.
    await _onPlatform(TargetPlatform.iOS, () async {
      await _openHeader(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(scrimFade(), findsNothing);
      await tester.pumpAndSettle();
    });
  });

  testWidgets('the header scrims still fade in everywhere else', (
    tester,
  ) async {
    // The other half of the gate: this must not become "the scrims never
    // animate", which would be a silent way to pass the test above.
    await _onPlatform(TargetPlatform.android, () async {
      await _openHeader(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(scrimFade(), findsWidgets);
      await tester.pumpAndSettle();
    });
  });
}
