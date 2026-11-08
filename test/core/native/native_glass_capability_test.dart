import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/glass/native_glass.dart';

void main() {
  test('an older Swift side that sends no glassControls reads as false', () {
    final cap = NativeGlassCapability.fromChannel(const {
      'systemVersion': '26.0',
      'majorVersion': 26,
      'systemGlass': true,
      'glassStyles': ['regular', 'clear'],
      'materials': ['thin'],
      'reduceTransparency': false,
    });
    expect(cap.glassControls, isFalse);
    expect(NativeGlassCapability.absent.glassControls, isFalse);
  });

  test('glassControls is read and counts in equality', () {
    Map<String, Object?> said(bool controls) => {
      'systemGlass': true,
      'glassStyles': ['clear'],
      'glassControls': controls,
    };
    final yes = NativeGlassCapability.fromChannel(said(true));
    expect(yes.glassControls, isTrue);
    expect(yes == NativeGlassCapability.fromChannel(said(false)), isFalse);
    expect(yes == NativeGlassCapability.fromChannel(said(true)), isTrue);
  });
}
