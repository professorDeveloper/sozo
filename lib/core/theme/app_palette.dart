import 'package:flutter/material.dart';

import 'app_accent.dart';

/// How dark the neutral surfaces go.
///
/// Deliberately an enum rather than a bool even though there are two values:
/// the setting is persisted as a name, and a third tier can be added later
/// without another migration.
enum AppDarkness {
  /// The greys the app has always shipped. Default, and byte-identical to the
  /// old hard-coded [AppColors] constants.
  dark,

  /// Pure black background and near-black surfaces. On an OLED panel a black
  /// pixel is an *off* pixel, so this is both the deepest contrast the app can
  /// show and the cheapest to light.
  black,
}

/// The full set of colours the app repaints when Appearance changes.
///
/// Resolved once per theme change and parked in [AppPalette.current], which
/// every `AppColors.*` getter reads. Nothing here is computed per frame.
///
/// Only the neutrals and the accent live here. Text, error, success, rating and
/// the medal colours stay compile-time constants in `AppColors`, on purpose:
///
///   * white-on-dark text is correct at every accent and both darkness levels,
///   * `error` must stay **red** even when the accent is green — an accent that
///     recoloured destructive actions would be a real bug, not a theme.
@immutable
class AppPalette {
  const AppPalette._({
    required this.accent,
    required this.darkness,
    required this.tintNav,
    required this.background,
    required this.navBackground,
    required this.surface,
    required this.card,
    required this.surfaceVariant,
    required this.border,
    required this.divider,
  });

  final AppAccent accent;
  final AppDarkness darkness;

  /// Paint the bottom bar's selected tab in the accent instead of white.
  ///
  /// The stored *preference* ships on — see [AppConstants.tintNavKey]. This
  /// parameter still defaults to false, because [resolve] is a pure function
  /// and a caller that builds a palette by hand should get what it asked for
  /// rather than a policy decision.
  final bool tintNav;

  final Color background;
  final Color navBackground;
  final Color surface;
  final Color card;
  final Color surfaceVariant;
  final Color border;
  final Color divider;

  Color get primary => accent.base;
  Color get primaryDark => accent.dark;
  Color get primaryLight => accent.light;

  /// Foreground for anything painted **on** [primary].
  ///
  /// Always white, and that is a guarantee rather than a coincidence: every
  /// accent — presets and custom picks alike — is held at or above
  /// [AppAccent.minWhiteContrast] against white precisely so the ~140 places
  /// that hard-code `Colors.white` on an accent fill stay correct. See
  /// [AppAccent]'s legibility contract.
  Color get onPrimary => Colors.white;

  bool get isBlack => darkness == AppDarkness.black;

  // ── Neutral ramps ─────────────────────────────────────────────────────────
  //
  // `dark` is the shipped palette, unchanged. `black` keeps the *same ordering*
  // (nav ≤ background < surface < card < surfaceVariant) so every screen's
  // depth cues survive — it just compresses the whole ramp toward zero and
  // pulls background and nav all the way to true black.

  static const Color _darkBackground = Color(0xFF181818);
  static const Color _darkNavBackground = Color(0xFF0F0F0F);
  static const Color _darkSurface = Color(0xFF242424);
  static const Color _darkCard = Color(0xFF282828);
  static const Color _darkSurfaceVariant = Color(0xFF303030);
  static const Color _darkBorder = Color(0xFF3A3A3A);
  static const Color _darkDivider = Color(0xFF2A2A2A);

  static const Color _blackBackground = Color(0xFF000000);
  static const Color _blackNavBackground = Color(0xFF000000);
  static const Color _blackSurface = Color(0xFF0E0E0E);
  static const Color _blackCard = Color(0xFF141414);
  static const Color _blackSurfaceVariant = Color(0xFF1E1E1E);

  /// Borders and dividers are *raised* relative to the rest of the ramp under
  /// AMOLED. On a #181818 background a #3A3A3A hairline separates by luminance
  /// difference; on true black the same job needs a line that is still clearly
  /// above its surface, or every card edge disappears.
  static const Color _blackBorder = Color(0xFF2B2B2B);
  static const Color _blackDivider = Color(0xFF1A1A1A);

  /// The palette in force. Swapped by `ThemeController`, read by every
  /// `AppColors` getter. Starts at the shipped defaults so anything that
  /// touches a colour before the controller has loaded — an early error screen,
  /// a widget test with no DI — still paints the app the app has always been.
  static AppPalette current = resolve(
    accent: AppAccent.fallback,
    darkness: AppDarkness.dark,
  );

  static AppPalette resolve({
    required AppAccent accent,
    required AppDarkness darkness,
    bool tintNav = false,
  }) {
    final black = darkness == AppDarkness.black;
    return AppPalette._(
      accent: accent,
      darkness: darkness,
      tintNav: tintNav,
      background: black ? _blackBackground : _darkBackground,
      navBackground: black ? _blackNavBackground : _darkNavBackground,
      surface: black ? _blackSurface : _darkSurface,
      card: black ? _blackCard : _darkCard,
      surfaceVariant: black ? _blackSurfaceVariant : _darkSurfaceVariant,
      border: black ? _blackBorder : _darkBorder,
      divider: black ? _blackDivider : _darkDivider,
    );
  }

  // ── Accent-tinted page backdrop ───────────────────────────────────────────
  //
  // Profile paints a three-stop vertical gradient behind its content. It used
  // to be the literal list [#1E1416, #181818, #101010] — a red-tinted top over
  // the dark grey — which silently stayed red no matter what accent was chosen.
  // These three getters reproduce that gradient exactly for the default accent
  // and follow the chosen one otherwise.

  /// Top stop: the background nudged onto the accent's hue.
  ///
  /// At the default red this evaluates to #1E1414 — the shipped #1E1416 to
  /// within one step of blue. Under AMOLED it is a far deeper whisper of accent
  /// (#0B0404 at red) so the header still reads as *this* app's header without
  /// giving up the black.
  Color get heroTop {
    final hue = HSLColor.fromColor(primary).hue;
    final base = HSLColor.fromColor(background);
    return HSLColor.fromAHSL(
      1,
      hue,
      isBlack ? 0.50 : 0.20,
      (base.lightness + (isBlack ? 0.030 : 0.004)).clamp(0.0, 1.0),
    ).toColor();
  }

  /// Middle stop: the plain background, so the gradient lands on the same
  /// colour every other screen uses.
  Color get heroMid => background;

  /// Bottom stop: the background scaled to 0.667 in sRGB — exactly the
  /// #181818 → #101010 fall-off the gradient always had. Under AMOLED the
  /// background is already zero, so this stays true black.
  Color get heroBottom => AppAccent.scaleChannels(background, 0.667);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppPalette &&
          other.accent == accent &&
          other.darkness == darkness &&
          other.tintNav == tintNav;

  @override
  int get hashCode => Object.hash(accent, darkness, tintNav);
}
