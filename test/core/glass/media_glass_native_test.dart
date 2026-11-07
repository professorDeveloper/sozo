import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/glass/glass_surface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/glass/media_glass.dart';
import 'package:soplay/core/glass/native_glass.dart';

NativeGlassCapability _phone({
  required bool systemGlass,
  Set<String> styles = const {'regular', 'clear'},
}) => NativeGlassCapability(
  systemVersion: systemGlass ? '26.0' : '18.5',
  majorVersion: systemGlass ? 26 : 18,
  systemGlass: systemGlass,
  styles: systemGlass ? styles : const {},
  materials: const {'ultraThin', 'thin', 'regular', 'thick', 'chrome'},
  reduceTransparency: false,
);

void main() {
  test('an iPhone with the clear glass effect draws the system glass', () {
    expect(
      mediaGlassGoesNative(
        platform: TargetPlatform.iOS,
        capability: _phone(systemGlass: true),
        reduceTransparency: false,
      ),
      isTrue,
    );
  });

  test('an older iPhone keeps the shader, not the blur material', () {
    expect(
      mediaGlassGoesNative(
        platform: TargetPlatform.iOS,
        capability: _phone(systemGlass: false),
        reduceTransparency: false,
      ),
      isFalse,
    );
  });

  test('Reduce Transparency and other platforms never host glass', () {
    expect(
      mediaGlassGoesNative(
        platform: TargetPlatform.iOS,
        capability: _phone(systemGlass: true),
        reduceTransparency: true,
      ),
      isFalse,
    );
    expect(
      mediaGlassGoesNative(
        platform: TargetPlatform.android,
        capability: _phone(systemGlass: true),
        reduceTransparency: false,
      ),
      isFalse,
    );
  });

  test('a glass effect without the clear style keeps the shader', () {
    expect(
      mediaGlassGoesNative(
        platform: TargetPlatform.iOS,
        capability: _phone(systemGlass: true, styles: const {'regular'}),
        reduceTransparency: false,
      ),
      isFalse,
    );
  });

  testWidgets('on an iPhone with system glass each piece is the hosted glass', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.pumpWidget(
      MaterialApp(
        home: NativeGlassScope(
          capability: _phone(systemGlass: true),
          child: const Center(
            child: MediaGlassLayer(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  MediaGlass(child: SizedBox(width: 38, height: 38)),
                  MediaGlass(radius: 10, child: SizedBox(width: 80, height: 44)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(NativeGlass), findsNWidgets(2));
    expect(find.byType(GlassGroup), findsNothing);
    expect(find.byType(GlassShape), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
}
