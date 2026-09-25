import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/onboarding/presentation/pages/onboarding_page.dart';

void main() {
  test('a settled page shows only its own backdrop', () {
    expect(backdropOpacities(0), [1.0, 0.0, 0.0]);
    expect(backdropOpacities(1), [0.0, 1.0, 0.0]);
    expect(backdropOpacities(2), [0.0, 0.0, 1.0]);
  });

  test('mid-swipe the page underneath stays fully opaque', () {
    final o = backdropOpacities(0.5);
    expect(o[0], 1.0, reason: 'no dip through the dark page');
    expect(o[1], 0.5);
    expect(o[2], 0.0);
    expect(backdropOpacities(1.25), [0.0, 1.0, 0.25]);
  });

  test('overscroll past either end stays on a full backdrop', () {
    expect(backdropOpacities(-0.2)[0], 1.0);
    expect(backdropOpacities(2.3)[2], 1.0);
  });
}
