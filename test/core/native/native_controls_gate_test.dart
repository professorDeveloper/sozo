import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/glass/native_glass.dart';
import 'package:soplay/core/native/native_controls_gate.dart';

NativeGlassCapability _cap({
  bool systemGlass = true,
  Set<String> styles = const {'regular', 'clear'},
  bool glassControls = true,
}) => NativeGlassCapability(
  systemVersion: '26.0',
  majorVersion: 26,
  systemGlass: systemGlass,
  styles: styles,
  materials: const {'thin'},
  reduceTransparency: false,
  glassControls: glassControls,
);

bool _draw({
  bool isIOS = true,
  bool isTv = false,
  bool isDesktop = false,
  NativeGlassCapability? cap,
  bool rt = false,
}) => nativeControlsDraw(
  isIOS: isIOS,
  isTv: isTv,
  isDesktop: isDesktop,
  cap: cap ?? _cap(),
  reduceTransparency: rt,
);

void main() {
  test('an iOS 26 iPhone with clear glass and the bar factory hosts', () {
    expect(_draw(), isTrue);
  });

  test('Reduce Transparency keeps Flutter', () {
    expect(_draw(rt: true), isFalse);
  });

  test('no glassControls keeps Flutter', () {
    expect(_draw(cap: _cap(glassControls: false)), isFalse);
  });

  test('regular-only glass keeps Flutter', () {
    expect(_draw(cap: _cap(styles: const {'regular'})), isFalse);
    expect(_draw(cap: _cap(systemGlass: false)), isFalse);
  });

  test('Android, TV and desktop never host', () {
    expect(_draw(isIOS: false), isFalse);
    expect(_draw(isTv: true), isFalse);
    expect(_draw(isDesktop: true), isFalse);
  });

  test('absent capability keeps Flutter', () {
    expect(_draw(cap: NativeGlassCapability.absent), isFalse);
  });
}
