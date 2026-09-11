import 'package:flutter/material.dart';
import 'kaizoku_colors.dart';
import 'kaizoku_typography.dart';

/// Kaizoku theme builder configuring Material 3 Dark theme with custom Kaizoku tokens.
class KaizokuTheme {
  const KaizokuTheme._();

  static ThemeData dark({bool amoled = false}) {
    final background = amoled ? KaizokuColors.canvasAmoled : KaizokuColors.canvas;
    final surface = amoled ? const Color(0xFF07080B) : KaizokuColors.surface;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      colorScheme: ColorScheme.dark(
        surface: surface,
        primary: KaizokuColors.crimson,
        onPrimary: Colors.white,
        secondary: KaizokuColors.amber,
        onSecondary: Colors.black,
        tertiary: KaizokuColors.cyan,
        onTertiary: Colors.black,
        error: const Color(0xFFFF4D4F),
        onError: Colors.white,
        outline: KaizokuColors.borderSubtle,
      ),
      dividerTheme: const DividerThemeData(
        color: KaizokuColors.borderSubtle,
        thickness: 1,
        space: 1,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: KaizokuColors.borderSubtle, width: 1),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: KaizokuTypography.headlineLargeMobile,
        iconTheme: const IconThemeData(color: KaizokuColors.textHigh),
      ),
      textTheme: const TextTheme(
        displayLarge: KaizokuTypography.displayLargeMobile,
        displayMedium: KaizokuTypography.displayMediumMobile,
        headlineLarge: KaizokuTypography.headlineLargeMobile,
        headlineMedium: KaizokuTypography.headlineMediumMobile,
        bodyLarge: KaizokuTypography.bodyLargeMobile,
        bodyMedium: KaizokuTypography.bodyMediumMobile,
        labelSmall: KaizokuTypography.labelSmallMobile,
      ),
    );
  }
}
