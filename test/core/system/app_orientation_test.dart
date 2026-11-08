import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/system/app_orientation.dart';

void main() {
  test('600dp shortest side is a large screen', () {
    expect(AppOrientation.isLargeScreen(const Size(393, 852)), isFalse);
    expect(AppOrientation.isLargeScreen(const Size(852, 393)), isFalse);
    expect(AppOrientation.isLargeScreen(const Size(820, 1180)), isTrue);
    expect(AppOrientation.isLargeScreen(const Size(673, 841)), isTrue);
    expect(AppOrientation.isLargeScreen(Size.zero), isFalse);
  });

  test('phones keep the portrait lock', () {
    expect(
      AppOrientation.resolve(AppOrientation.appDefault, largeScreen: false),
      AppOrientation.appDefault,
    );
  });

  test('large screens drop it, but keep the player\'s landscape', () {
    expect(
      AppOrientation.resolve(AppOrientation.appDefault, largeScreen: true),
      DeviceOrientation.values,
    );
    const landscape = [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ];
    expect(AppOrientation.resolve(landscape, largeScreen: true), landscape);
  });
}
