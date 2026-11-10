import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/player/media_controller.dart';

void main() {
  test('Linux avoids the OpenGL interop', () {
    expect(mediaKitVideoConfiguration(isLinux: true).hwdec, 'auto-copy');
  });

  test('other platforms keep the library default', () {
    expect(mediaKitVideoConfiguration(isLinux: false).hwdec, isNull);
  });
}
