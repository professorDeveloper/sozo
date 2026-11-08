import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/glass/native_glass.dart';
import 'package:soplay/core/native/player_controls_style.dart';
import 'package:soplay/features/profile/presentation/widgets/player_controls_style_section.dart';

const _ios26 = NativeGlassCapability(
  systemVersion: '26.0',
  majorVersion: 26,
  systemGlass: true,
  styles: {'regular', 'clear'},
  materials: {'thin'},
  reduceTransparency: false,
  glassControls: true,
);

/// No translations are loaded, so every `.tr()` renders as its own key.
void main() {
  Future<List<PlayerControlsStyle>> pump(
    WidgetTester tester, {
    NativeGlassCapability cap = _ios26,
    PlayerControlsStyle chosen = PlayerControlsStyle.native,
  }) async {
    final picked = <PlayerControlsStyle>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PlayerControlsStyleSection(
              chosen: chosen,
              capability: cap,
              onChanged: picked.add,
            ),
          ),
        ),
      ),
    );
    return picked;
  }

  Finder row(PlayerControlsStyle s) =>
      find.byKey(ValueKey('controls-style-${s.name}'));

  for (final platform in TargetPlatform.values) {
    final ios = platform == TargetPlatform.iOS;
    testWidgets('${ios ? 'shown' : 'hidden'} on ${platform.name}', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      await pump(tester);
      expect(PlayerControlsStyleSection.shown, ios);
      expect(find.text('profile.controls_style'), ios ? findsOneWidget : findsNothing);
      for (final s in PlayerControlsStyle.values) {
        expect(row(s), ios ? findsOneWidget : findsNothing);
      }
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('on iOS 26 every style can be picked', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final picked = await pump(tester);
    expect(find.text('profile.controls_style_desc'), findsOneWidget);
    expect(find.text('profile.controls_style_needs_ios26'), findsNothing);
    await tester.tap(row(PlayerControlsStyle.classicGlass));
    await tester.tap(row(PlayerControlsStyle.systemGlass));
    expect(picked, [
      PlayerControlsStyle.classicGlass,
      PlayerControlsStyle.systemGlass,
    ]);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('below iOS 26 the two glass styles are disabled', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final picked = await pump(tester, cap: NativeGlassCapability.absent);
    expect(find.text('profile.controls_style_needs_ios26'), findsNWidgets(2));
    await tester.tap(row(PlayerControlsStyle.native));
    await tester.tap(row(PlayerControlsStyle.systemGlass));
    expect(picked, isEmpty);
    // The classic glass shows as the current one.
    expect(
      find.descendant(
        of: row(PlayerControlsStyle.classicGlass),
        matching: find.byIcon(Icons.radio_button_checked_rounded),
      ),
      findsOneWidget,
    );
    debugDefaultTargetPlatformOverride = null;
  });
}
