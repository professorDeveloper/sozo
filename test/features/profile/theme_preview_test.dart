import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/theme/app_accent.dart';
import 'package:soplay/core/theme/app_palette.dart';
import 'package:soplay/features/profile/presentation/widgets/theme_preview.dart';

/// [ThemePreview] is laid out against a hand-computed 240 × 480 canvas — the
/// column of fixed heights has to keep adding up to less than that. These pump
/// it at every accent, both darkness levels, and both the large and thumbnail
/// sizes, so a future tweak to one child's height cannot silently start
/// overflowing.
void main() {
  Future<void> pumpAt(WidgetTester tester, Widget child, Size size) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(width: size.width, height: size.height, child: child),
          ),
        ),
      ),
    );
  }

  testWidgets('renders at the large size for every accent and darkness',
      (tester) async {
    for (final accent in AppAccent.presets) {
      for (final darkness in AppDarkness.values) {
        await pumpAt(
          tester,
          ThemePreview(
            palette: AppPalette.resolve(accent: accent, darkness: darkness),
          ),
          const Size(240, 480),
        );
        expect(
          tester.takeException(),
          isNull,
          reason: '${accent.id} / ${darkness.name} overflowed',
        );
      }
    }
  });

  testWidgets('renders as a thumbnail without chrome', (tester) async {
    // Roughly the width one darkness tile gives it on a small phone.
    await pumpAt(
      tester,
      ThemePreview(
        palette: AppPalette.resolve(
          accent: AppAccent.fallback,
          darkness: AppDarkness.black,
        ),
        showChrome: false,
      ),
      const Size(75, 150),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('survives a very narrow box', (tester) async {
    await pumpAt(
      tester,
      ThemePreview(
        palette: AppPalette.resolve(
          accent: AppAccent.fallback,
          darkness: AppDarkness.dark,
        ),
        showChrome: false,
      ),
      const Size(40, 80),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a custom accent renders too', (tester) async {
    await pumpAt(
      tester,
      ThemePreview(
        palette: AppPalette.resolve(
          accent: AppAccent.custom(const Color(0xFFFFFF00)),
          darkness: AppDarkness.black,
        ),
      ),
      const Size(240, 480),
    );
    expect(tester.takeException(), isNull);
  });
}
