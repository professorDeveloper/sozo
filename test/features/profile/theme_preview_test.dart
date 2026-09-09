import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/theme/app_accent.dart';
import 'package:soplay/core/theme/app_palette.dart';
import 'package:soplay/core/theme/app_theme.dart';
import 'package:soplay/features/profile/presentation/widgets/theme_preview.dart';

/// Layout guards for the Appearance page's two colour samples.
///
/// Two things about the setup are load-bearing:
///
/// **[ThemePreview] takes no palette.** It paints through `AppColors`, which
/// reads [AppPalette.current] — deliberately, so the preview shows the exact
/// globals the app's other call sites read rather than a parallel copy. These
/// tests therefore swap the global, pump, and put it back.
///
/// **Text is wider here than in the app.** `flutter test` renders with the
/// FlutterTest font, where every glyph is a full em square, so a label is
/// roughly twice the width a real font gives it. That makes these a
/// deliberately pessimistic width check: anything that fits here fits at any
/// translation.
void main() {
  final original = AppPalette.current;

  tearDown(() => AppPalette.current = original);

  Future<void> pumpAt(WidgetTester tester, Widget child, double width) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Theme(
            data: AppTheme.dark,
            // The samples show real Material controls — a real switch, a real
            // ElevatedButton — so they need the ancestors those get in the app.
            child: Material(
              color: Colors.transparent,
              child: Center(
                child: SizedBox(width: width, child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }

  group('ThemePreview', () {
    // Appearance hands it the page's content width, so these are a mid-size
    // phone and a small one rather than an arbitrary canvas.
    for (final width in [328.0, 288.0]) {
      testWidgets('fits ${width.toInt()}px wide at every accent and darkness',
          (tester) async {
        for (final accent in AppAccent.presets) {
          for (final darkness in AppDarkness.values) {
            AppPalette.current =
                AppPalette.resolve(accent: accent, darkness: darkness);
            await pumpAt(tester, const ThemePreview(), width);
            expect(
              tester.takeException(),
              isNull,
              reason: '${accent.id} / ${darkness.name} overflowed at $width',
            );
          }
        }
      });
    }

    testWidgets('a custom accent renders too', (tester) async {
      AppPalette.current = AppPalette.resolve(
        accent: AppAccent.custom(const Color(0xFFFFFF00)),
        darkness: AppDarkness.black,
      );
      await pumpAt(tester, const ThemePreview(), 328);
      expect(tester.takeException(), isNull);
    });
  });

  group('DarknessSample', () {
    // This one really is pinned to 240 by the accent sheet.
    testWidgets('fits its 240px box at every accent', (tester) async {
      for (final accent in AppAccent.presets) {
        for (final darkness in AppDarkness.values) {
          await pumpAt(
            tester,
            DarknessSample(
              palette: AppPalette.resolve(accent: accent, darkness: darkness),
            ),
            240,
          );
          expect(
            tester.takeException(),
            isNull,
            reason: '${accent.id} / ${darkness.name} overflowed',
          );
        }
      }
    });
  });
}
