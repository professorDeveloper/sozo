import 'package:flutter/material.dart';
import '../system/platform_utils.dart';
import 'app_colors.dart';

/// The app's one button height and one corner radius.
///
/// Named rather than repeated so a screen that has to build its own control by
/// hand — a gradient CTA, a custom pill — lands on the same grid as the themed
/// buttons beside it instead of being eyeballed.
const double kButtonHeight = 52;
const double kButtonRadius = 10;

/// Fields, cards, sheets and snackbars — everything that is a *surface* rather
/// than a control. Same 10 as the buttons, so a form reads as one object.
const double kFieldRadius = 10;

class AppTheme {
  AppTheme._();

  /// Built fresh on every read, from whatever `AppColors` currently resolves to.
  ///
  /// That is cheap (one `ThemeData` allocation) and it is what lets Appearance
  /// change the accent or switch to true black without a restart: `MyApp` reads
  /// this again on each rebuild, so the Material component defaults follow the
  /// palette in exactly the same breath as the widgets that read `AppColors`
  /// directly.
  static ThemeData get dark => ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: ColorScheme(
          brightness: Brightness.dark,
          primary: AppColors.primary,
          onPrimary: AppColors.onPrimary,
          secondary: AppColors.primary,
          onSecondary: AppColors.onPrimary,
          error: AppColors.error,
          onError: Colors.white,
          surface: AppColors.surface,
          onSurface: AppColors.textPrimary,
          surfaceContainerHighest: AppColors.surfaceVariant,
          outline: AppColors.border,
          // Left unset, M3 resolves outlineVariant to onSurface — i.e. white —
          // and every component that draws its own hairline (TabBar, Divider,
          // ListTile separators) paints it near-white. Harmless-looking on
          // #181818, glaring on true black.
          outlineVariant: AppColors.divider,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
          iconTheme: IconThemeData(color: AppColors.textPrimary),
          actionsIconTheme: IconThemeData(color: AppColors.textPrimary),
        ),
        textTheme: const TextTheme(
          displayLarge: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 57,
          ),
          displayMedium: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 45,
          ),
          displaySmall: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 36,
          ),
          headlineLarge: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 32,
          ),
          headlineMedium: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 28,
          ),
          headlineSmall: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 24,
          ),
          titleLarge: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 22,
          ),
          titleMedium: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w500,
            fontSize: 16,
          ),
          titleSmall: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w500,
            fontSize: 14,
          ),
          bodyLarge: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
          ),
          bodyMedium: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
          ),
          bodySmall: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
          ),
          labelLarge: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
          labelMedium: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
          ),
          labelSmall: TextStyle(
            color: AppColors.textHint,
            fontSize: 11,
          ),
        ),
        cardTheme: CardThemeData(
          color: AppColors.card,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kFieldRadius),
          ),
        ),
        // ── The one button shape ────────────────────────────────────────
        //
        // 52 tall, 10 radius, 15.5/w700 label. These are the numbers the
        // onboarding and auth screens were already using through their own
        // `AuthPrimaryButton`, and they are here now so every ElevatedButton and
        // FilledButton in the app is that button — no screen has to opt in, and
        // none can drift.
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onPrimary,
            disabledBackgroundColor: AppColors.surfaceVariant,
            disabledForegroundColor: AppColors.textHint,
            elevation: 0,
            minimumSize: const Size(double.infinity, kButtonHeight),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(kButtonRadius),
            ),
            textStyle: const TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ),
        // Mirrors elevatedButtonTheme, minus minimumSize: FilledButtons are
        // used compactly inside Rows, where Size(double.infinity, 50) would
        // overflow an unbounded main axis.
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onPrimary,
            disabledBackgroundColor: AppColors.surfaceVariant,
            disabledForegroundColor: AppColors.textHint,
            elevation: 0,
            minimumSize: const Size(0, kButtonHeight),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(kButtonRadius),
            ),
            textStyle: const TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            side: const BorderSide(color: AppColors.textSecondary, width: 1.5),
            minimumSize: const Size(double.infinity, kButtonHeight),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(kButtonRadius),
            ),
            textStyle: const TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surfaceVariant,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(kFieldRadius),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(kFieldRadius),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(kFieldRadius),
            borderSide: BorderSide(color: AppColors.primary, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(kFieldRadius),
            borderSide: const BorderSide(color: AppColors.error, width: 1.5),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(kFieldRadius),
            borderSide: const BorderSide(color: AppColors.error, width: 1.5),
          ),
          hintStyle: const TextStyle(color: AppColors.textHint, fontSize: 14),
          labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
          errorStyle: const TextStyle(color: AppColors.error, fontSize: 12),
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        dividerTheme: DividerThemeData(
          color: AppColors.border,
          thickness: 1,
          space: 1,
        ),
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          backgroundColor: AppColors.background,
          selectedItemColor: AppColors.textPrimary,
          unselectedItemColor: AppColors.textHint,
          showUnselectedLabels: true,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: AppColors.background,
          indicatorColor: AppColors.primary.withValues(alpha: 0.2),
          elevation: 0,
          height: 64,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        ),
        chipTheme: ChipThemeData(
          backgroundColor: AppColors.surfaceVariant,
          selectedColor: AppColors.primary,
          disabledColor: AppColors.surfaceVariant,
          labelStyle: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          side: BorderSide.none,
        ),
        progressIndicatorTheme: ProgressIndicatorThemeData(
          color: AppColors.primary,
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return AppColors.primary;
            return AppColors.textHint;
          }),
          trackColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.primaryDark.withValues(alpha: 0.5);
            }
            return AppColors.surfaceVariant;
          }),
        ),
        sliderTheme: SliderThemeData(
          activeTrackColor: AppColors.primary,
          inactiveTrackColor: AppColors.surfaceVariant,
          thumbColor: AppColors.primary,
          overlayColor: AppColors.primary.withValues(alpha: 0.2),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: AppColors.surfaceVariant,
          contentTextStyle: const TextStyle(color: AppColors.textPrimary),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kFieldRadius),
          ),
          behavior: SnackBarBehavior.floating,
          elevation: isDesktopPlatform ? 6 : null,
          width: isDesktopPlatform ? 420 : null,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: AppColors.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          titleTextStyle: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
          contentTextStyle: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
          ),
        ),
        bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: AppColors.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
        ),
        listTileTheme: const ListTileThemeData(
          tileColor: Colors.transparent,
          iconColor: AppColors.textSecondary,
          textColor: AppColors.textPrimary,
          contentPadding: EdgeInsets.symmetric(horizontal: 16),
        ),
        checkboxTheme: CheckboxThemeData(
          fillColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return AppColors.primary;
            return Colors.transparent;
          }),
          side: const BorderSide(color: AppColors.textSecondary, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
        ),
        radioTheme: RadioThemeData(
          fillColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return AppColors.primary;
            return AppColors.textSecondary;
          }),
        ),
        tabBarTheme: TabBarThemeData(
          labelColor: AppColors.textPrimary,
          unselectedLabelColor: AppColors.textHint,
          indicatorColor: AppColors.primary,
          // Material 3 draws a full-width divider under every TabBar, coloured
          // from the M3 outline role — which lands near-white on this dark
          // theme. Screens that want a rule draw their own (AppTabBar does).
          dividerColor: Colors.transparent,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          unselectedLabelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w400),
        ),
        tooltipTheme: TooltipThemeData(
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
        ),
        expansionTileTheme: ExpansionTileThemeData(
          backgroundColor: AppColors.surface,
          collapsedBackgroundColor: Colors.transparent,
          iconColor: AppColors.textSecondary,
          collapsedIconColor: AppColors.textSecondary,
          textColor: AppColors.textPrimary,
          collapsedTextColor: AppColors.textPrimary,
        ),
      );
}
