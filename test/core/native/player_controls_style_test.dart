import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/glass/glass_surface.dart';
import 'package:soplay/core/glass/media_glass.dart';
import 'package:soplay/core/glass/native_glass.dart';
import 'package:soplay/core/native/player_controls_style.dart';

const _ios26 = NativeGlassCapability(
  systemVersion: '26.0',
  majorVersion: 26,
  systemGlass: true,
  styles: {'regular', 'clear'},
  materials: {'thin'},
  reduceTransparency: false,
  glassControls: true,
);

const _ios18 = NativeGlassCapability(
  systemVersion: '18.5',
  majorVersion: 18,
  systemGlass: false,
  styles: {},
  materials: {'thin'},
  reduceTransparency: false,
);

PlayerControlsStyle _effective(
  PlayerControlsStyle chosen, {
  NativeGlassCapability cap = _ios26,
  bool rt = false,
  bool isIOS = true,
  bool isTv = false,
  bool isDesktop = false,
}) => effectivePlayerControlsStyle(
  chosen: chosen,
  isIOS: isIOS,
  isTv: isTv,
  isDesktop: isDesktop,
  cap: cap,
  reduceTransparency: rt,
);

bool _mediaNative(PlayerControlsStyle style, NativeGlassCapability cap, bool rt) =>
    mediaGlassGoesNative(
      platform: TargetPlatform.iOS,
      capability: cap,
      reduceTransparency: rt,
      style: style,
    );

void main() {
  const native = PlayerControlsStyle.native;
  const system = PlayerControlsStyle.systemGlass;
  const classic = PlayerControlsStyle.classicGlass;

  group('style × iOS version × Reduce Transparency', () {
    final expected = <(PlayerControlsStyle, bool, bool), PlayerControlsStyle>{
      (native, true, false): native,
      (native, true, true): classic,
      (native, false, false): classic,
      (native, false, true): classic,
      (system, true, false): system,
      (system, true, true): classic,
      (system, false, false): classic,
      (system, false, true): classic,
      (classic, true, false): classic,
      (classic, true, true): classic,
      (classic, false, false): classic,
      (classic, false, true): classic,
    };
    expected.forEach((key, want) {
      final (chosen, ios26, rt) = key;
      test('${chosen.name}, iOS ${ios26 ? 26 : 18}, RT $rt -> ${want.name}', () {
        final cap = ios26 ? _ios26 : _ios18;
        expect(_effective(chosen, cap: cap, rt: rt), want);
        // The media glass is the phone's own only on the two iOS 26 styles.
        expect(
          _mediaNative(chosen, cap, rt),
          want == native || want == system,
        );
      });
    });
  });

  test('native without the bar factory keeps the system glass', () {
    const noBars = NativeGlassCapability(
      systemVersion: '26.0',
      majorVersion: 26,
      systemGlass: true,
      styles: {'regular', 'clear'},
      materials: {'thin'},
      reduceTransparency: false,
    );
    expect(_effective(native, cap: noBars), system);
    expect(playerControlsStyleAvailable(native, noBars), isFalse);
    expect(playerControlsStyleAvailable(system, noBars), isTrue);
  });

  test('off an iPhone it is always the classic glass', () {
    for (final s in PlayerControlsStyle.values) {
      expect(_effective(s, isIOS: false), classic);
      expect(_effective(s, isTv: true), classic);
      expect(_effective(s, isDesktop: true), classic);
    }
  });

  test('availability below iOS 26: only the classic glass', () {
    expect(playerControlsStyleAvailable(native, _ios18), isFalse);
    expect(playerControlsStyleAvailable(system, _ios18), isFalse);
    expect(playerControlsStyleAvailable(classic, _ios18), isTrue);
  });

  test('the stored name reads back, and anything else is native', () {
    for (final s in PlayerControlsStyle.values) {
      expect(PlayerControlsStyle.fromName(s.name), s);
    }
    expect(PlayerControlsStyle.fromName(null), native);
    expect(PlayerControlsStyle.fromName('glass'), native);
    expect(PlayerControlsStyle.fromName(3), native);
  });

  test('no style keeps the old media glass decision', () {
    expect(
      mediaGlassGoesNative(
        platform: TargetPlatform.iOS,
        capability: _ios26,
        reduceTransparency: false,
      ),
      isTrue,
    );
  });

  for (final (style, hosted) in [(system, true), (classic, false)]) {
    testWidgets('a layer under ${style.name} draws '
        '${hosted ? 'the system glass' : 'the shader'}', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await tester.pumpWidget(
        MaterialApp(
          home: NativeGlassScope(
            capability: _ios26,
            child: PlayerControlsStyleScope(
              style: style,
              child: const Center(
                child: MediaGlassLayer(
                  child: MediaGlass(child: SizedBox(width: 38, height: 38)),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.byType(NativeGlass), hosted ? findsOneWidget : findsNothing);
      expect(find.byType(GlassGroup), hosted ? findsNothing : findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
