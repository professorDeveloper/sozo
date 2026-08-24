import 'package:flutter/material.dart';

import 'app_palette.dart';

/// The app's colour vocabulary.
///
/// ## Why some of these are getters
///
/// Settings → Appearance lets the user change the accent colour and switch the
/// neutrals to true black (AMOLED). Both have to reach ~1900 existing call
/// sites across 140 files without any of them being rewritten to take a
/// `BuildContext`, so the members those two settings touch read through
/// [AppPalette.current] instead of being compile-time constants.
///
/// Everything the settings do *not* touch is still `const`, both because it is
/// free and because it keeps `const` widget constructors working everywhere
/// they already did:
///
///   * text colours — white-on-dark is right at every accent and both darkness
///     levels, so there is nothing to vary,
///   * [error] — must stay red even when the accent is green. Destructive
///     actions are not a place to express a theme. (It happens to equal the
///     default accent, which is why it was never visible as a separate colour
///     before; it is one now.)
///   * [success], [rating], the medals, and the fixed black/transparent
///     gradient ends.
///
/// Reading a getter costs one static field load and one field read — no map
/// lookup, no `InheritedWidget`, nothing per-frame. What it does cost is that
/// `AppColors.primary` can no longer appear inside a `const` expression; drop
/// the `const` on the widget that holds it.
class AppColors {
  AppColors._();

  // ── Accent-driven ─────────────────────────────────────────────────────────

  static Color get primary => AppPalette.current.primary;
  static Color get primaryDark => AppPalette.current.primaryDark;
  static Color get primaryLight => AppPalette.current.primaryLight;

  /// Foreground for content painted on top of [primary]. Always white — see the
  /// legibility contract on `AppAccent`, which is what makes that safe.
  static Color get onPrimary => AppPalette.current.onPrimary;

  // ── Darkness-driven neutrals ──────────────────────────────────────────────

  static Color get background => AppPalette.current.background;
  static Color get navBackground => AppPalette.current.navBackground;
  static Color get surface => AppPalette.current.surface;
  static Color get card => AppPalette.current.card;
  static Color get surfaceVariant => AppPalette.current.surfaceVariant;
  static Color get border => AppPalette.current.border;
  static Color get divider => AppPalette.current.divider;

  /// The three stops of the accent-tinted page backdrop Profile paints. Follow
  /// both the accent and the darkness level.
  static Color get heroTop => AppPalette.current.heroTop;
  static Color get heroMid => AppPalette.current.heroMid;
  static Color get heroBottom => AppPalette.current.heroBottom;

  /// True while the user has AMOLED on. For the handful of places that need to
  /// *behave* differently on true black rather than just be a shade darker.
  static bool get isBlack => AppPalette.current.isBlack;

  /// True while the bottom bar's selected tab should carry the accent rather
  /// than the shipped white.
  static bool get isNavTinted => AppPalette.current.tintNav;

  // ── Fixed ─────────────────────────────────────────────────────────────────

  /// The splash has always been pure black, at every theme: it is the frame the
  /// native launch screen hands over to, and a mismatch there is a visible
  /// flash rather than a colour choice.
  static const Color splashBackground = Color(0xFF000000);

  static const Color textPrimary   = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFAAAAAA);
  static const Color textHint      = Color(0xFF666666);

  /// Deliberately NOT the accent. Kept at the original red so a destructive
  /// action still reads as destructive under a green or blue accent.
  static const Color error         = Color(0xFFE50914);

  /// The lifted partner to [error], for a rim or a label that has to sit on an
  /// error fill without collapsing into it.
  ///
  /// It is exactly the old default [primaryLight]. Before the accent became a
  /// setting, the "wrong answer" and "failed" states borrowed `primaryLight`
  /// because it happened to be red; pointing them here keeps them pixel-identical
  /// on the default theme while stopping them following a green accent.
  static const Color errorLight    = Color(0xFFFF4B55);
  static const Color success       = Color(0xFF46D369);
  static const Color rating        = Color(0xFFFFD700);

  // Podium medals. Gold points at the existing rating gold on purpose.
  static const Color medalGold     = rating;
  static const Color medalSilver   = Color(0xFFC0C0C0);
  static const Color medalBronze   = Color(0xFFCD7F32);

  static const Color overlay       = Color(0x99000000);
  static const Color gradientTransparent = Color(0x00000000);
  static const Color gradientBlack = Color(0xFF000000);
}
