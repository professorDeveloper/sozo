// Why this test exists
//
// `NativeGlass` (lib/core/glass/native_glass.dart) hosts the phone's own
// glass as a UIKit view, and nothing about that half can be seen from a
// widget test: a `UiKitView` renders nothing in the test renderer, the
// factory `soplay/native_glass` is only registered by a real engine
// (ios/Runner/AppDelegate.swift), and `glassCapability` is only answered by
// a real `UIVisualEffectView` on a real OS. The unit test
// (test/core/glass/native_glass_test.dart) covers the decision; this covers
// the part that can only be true on a device.
//
// It does three things: asks the running OS what its glass can do and
// prints the answer verbatim, checks that the answer and the OS version
// agree (a phone on iOS 26 or later must report the glass effect — if it
// does not, the bridge is not registered, which is the failure this test is
// here to catch), and mounts the widget to prove the platform view is
// actually created rather than throwing.
//
//   flutter test integration_test/native_glass_test.dart -d <device>
//
// The prints come before the assertions on purpose: what the device said is
// the result, whether or not the assertions pass.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:soplay/core/glass/glass_sense.dart';
import 'package:soplay/core/glass/native_glass.dart';

void say(String line) => debugPrint('NATIVE_GLASS $line');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the phone says what its glass can do, and hosts one', (
    tester,
  ) async {
    say('platform=${Platform.operatingSystem} ${Platform.operatingSystemVersion}');

    // The raw map, not the parsed capability: a key the Dart side does not
    // know about yet should still be visible in the output.
    final raw = await GlassSense.channel.invokeMapMethod<String, Object?>(
      NativeGlass.capabilityMethod,
    );
    say('raw=$raw');

    final said = await NativeGlass.capability();
    say('capability=$said');

    final decided = nativeGlassDraw(
      platform: defaultTargetPlatform,
      capability: said,
      reduceTransparency: said.reduceTransparency,
    );
    say('draw=$decided');

    NativeGlassDraw? reported;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: GlassSense(
          child: Center(
            child: SizedBox(
              width: 240,
              height: 120,
              child: NativeGlass(
                borderRadius: BorderRadius.circular(26),
                onDraw: (draw) => reported = draw,
                fallback: (_) =>
                    const ColoredBox(color: Color(0x33FFFFFF), key: Key('fallback')),
              ),
            ),
          ),
        ),
      ),
    );
    // One frame to mount, one for the probe's answer, one for the hosted
    // view the answer asks for.
    await tester.pumpAndSettle();
    say('reported=$reported');
    say('hosted=${find.byType(UiKitView).evaluate().length}');
    say('fellBack=${find.byKey(const Key('fallback')).evaluate().isNotEmpty}');

    // How many views UIKit really built. Counting the Dart `UiKitView`
    // above proves only that Dart asked for one: with the factory
    // unregistered, Flutter leaves the element in the tree and logs the
    // failure instead of throwing, so every assertion here passed while
    // nothing native existed. This is the number that cannot be true
    // unless ios/Runner/NativeGlass.swift ran.
    final built = await GlassSense.channel.invokeMethod<int>('glassViewsBuilt');
    say('built=$built');

    // Now the assertions.
    expect(Platform.isIOS, isTrue, reason: 'this test is about the iPhone');
    expect(raw, isNotNull, reason: 'soplay/glass did not answer glassCapability');
    expect(said.systemVersion, isNotEmpty);
    expect(said.majorVersion, greaterThan(0));
    // Only the dark materials are offered, and all of them are iOS 13+, so
    // every phone that can run this app must list them.
    expect(said.materials, contains('thin'));
    if (said.majorVersion >= 26) {
      expect(
        said.systemGlass,
        isTrue,
        reason: 'iOS ${said.systemVersion} has UIGlassEffect',
      );
      expect(said.styles, containsAll(<String>['regular', 'clear']));
      expect(decided, NativeGlassDraw.systemGlass);
    } else {
      expect(decided, NativeGlassDraw.systemMaterial);
    }
    expect(reported, decided, reason: 'the widget drew something else');
    expect(find.byType(UiKitView), findsOneWidget);
    expect(
      built,
      1,
      reason: 'UIKit built no glass view: the factory soplay/native_glass is '
          'not registered, or the effect could not be made',
    );
  });
}
