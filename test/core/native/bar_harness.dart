import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/glass/glass_sense.dart';
import 'package:soplay/core/glass/native_glass.dart';
import 'package:soplay/core/native/native_controls_gate.dart';
import 'package:soplay/core/native/native_link.dart';

import 'fake_native_host.dart';

const NativeGlassCapability ios26 = NativeGlassCapability(
  systemVersion: '26.0',
  majorVersion: 26,
  systemGlass: true,
  styles: {'regular', 'clear'},
  materials: {'thin'},
  reduceTransparency: false,
  glassControls: true,
);

/// An iPhone on iOS 26 with the bar factory, unless told otherwise.
Widget barHarness(
  Widget child, {
  required FakeNativeHost host,
  NativeGlassCapability capability = ios26,
  bool reduceTransparency = false,
  bool disableAnimations = false,
  TextDirection dir = TextDirection.ltr,
}) => MediaQuery(
  data: MediaQueryData(
    size: const Size(800, 600),
    disableAnimations: disableAnimations,
  ),
  child: Directionality(
    textDirection: dir,
    child: NativeGlassScope(
      capability: capability,
      child: GlassSenseScope(
        reduceTransparency: reduceTransparency,
        child: NativeHostScope(host: host, child: child),
      ),
    ),
  ),
);

/// [body] on an iPhone (not the desktop the tests run on), the overrides
/// reset before the test ends as flutter_test requires.
void testOnIPhone(
  String description,
  Future<void> Function(WidgetTester tester) body, {
  bool desktop = false,
  TargetPlatform platform = TargetPlatform.iOS,
}) {
  testWidgets(description, (tester) async {
    debugDefaultTargetPlatformOverride = platform;
    debugNativeControlsDesktopOverride = desktop;
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      debugNativeControlsDesktopOverride = null;
    }
  });
}
