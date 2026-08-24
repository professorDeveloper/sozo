import 'package:flutter/material.dart';

/// One accent colour the user can pick in Settings → Appearance.
///
/// An accent is a *triple*, not a single colour: [base] is what
/// `AppColors.primary` becomes, [dark] and [light] are the pressed / hover /
/// glow variants that `AppColors.primaryDark` and `AppColors.primaryLight`
/// become. Every screen in the app already reads those three, so swapping an
/// accent repaints the whole product without a single call site changing.
///
/// ## The legibility contract
///
/// The app is dark-only and puts **white** text and icons on top of
/// `AppColors.primary` in ~140 places (buttons, chips, badges, the play FAB).
/// None of those pass a colour down — they hard-code `Colors.white`. So an
/// accent is only safe if white stays readable on it.
///
/// Every preset below therefore sits at or above **3.8:1 against white**, and
/// [AppAccent.custom] pushes an arbitrary picked colour down in lightness until
/// it does too. 3.8 is not arbitrary: the shipped Sozo red is 4.79:1 against
/// white and 3.70:1 against the dark background, so the floor is set just under
/// the red's *worse* direction. Any accent the user can choose is at least as
/// legible as the one the app has always shipped, in both directions.
///
/// ## The family rule
///
/// [dark] and [light] are not eyeballed per colour — they are the exact
/// relationship the shipped red triple already had, so every accent is a
/// sibling of the original rather than a different-looking design:
///
///   * `dark`  = base scaled by 0.7773 in sRGB      (#E50914 → #B20710, exact)
///   * `light` = HSL lightness raised 33.8% of the
///               way to white, saturation × 1.0818  (#E50914 → #FF4B55, exact)
///
/// The preset triples below are the pre-computed result, so no colour maths
/// runs at startup; [AppAccent.custom] applies the same two rules live.
@immutable
class AppAccent {
  const AppAccent({
    required this.id,
    required this.base,
    required this.dark,
    required this.light,
    this.isCustom = false,
  });

  /// Stable key persisted in Hive. Never localise or renumber these — an
  /// install that stored `'violet'` must still resolve to violet after an
  /// update, and an id that no longer exists falls back to [fallback].
  final String id;

  final Color base;
  final Color dark;
  final Color light;

  /// True only for the user's own picked colour, which is stored as an ARGB
  /// value rather than by id.
  final bool isCustom;

  /// Translation key for the swatch label.
  String get labelKey => isCustom ? 'appearance.accent_custom' : 'appearance.accent_$id';

  /// The id stored for a custom colour. Its actual value lives under
  /// [AppConstants.customAccentKey].
  static const String customId = 'custom';

  /// The accent the app has always shipped. Also the value a corrupt or
  /// unknown stored id falls back to, so a bad preference can never leave the
  /// app unthemed.
  static const AppAccent fallback = AppAccent(
    id: 'red',
    base: Color(0xFFE50914),
    dark: Color(0xFFB20710),
    light: Color(0xFFFF4B55),
  );

  /// The swatch row, in hue order starting from the default red. Slate sits
  /// last on purpose: it is the "no colour" choice and reads as the end of the
  /// wheel rather than a hue on it.
  static const List<AppAccent> presets = <AppAccent>[
    fallback,
    AppAccent(
      id: 'ember',
      base: Color(0xFFED4700),
      dark: Color(0xFFB83700),
      light: Color(0xFFFF804A),
    ),
    AppAccent(
      id: 'amber',
      base: Color(0xFFB57408),
      dark: Color(0xFF8D5A06),
      light: Color(0xFFFEAF2C),
    ),
    AppAccent(
      id: 'emerald',
      base: Color(0xFF179644),
      dark: Color(0xFF127535),
      light: Color(0xFF37E876),
    ),
    AppAccent(
      id: 'teal',
      base: Color(0xFF0E928E),
      dark: Color(0xFF0B716E),
      light: Color(0xFF24F3EC),
    ),
    AppAccent(
      id: 'sky',
      base: Color(0xFF0C8BC4),
      dark: Color(0xFF096C98),
      light: Color(0xFF3BBFFB),
    ),
    AppAccent(
      id: 'ocean',
      base: Color(0xFF2F7BF6),
      dark: Color(0xFF2560BF),
      light: Color(0xFF70A6FE),
    ),
    AppAccent(
      id: 'indigo',
      base: Color(0xFF6366F1),
      dark: Color(0xFF4D4FBB),
      light: Color(0xFF9496FA),
    ),
    AppAccent(
      id: 'violet',
      base: Color(0xFF9B51E0),
      dark: Color(0xFF783FAE),
      light: Color(0xFFBD88EE),
    ),
    AppAccent(
      id: 'magenta',
      base: Color(0xFFE040A0),
      dark: Color(0xFFAE327C),
      light: Color(0xFFEF7CC1),
    ),
    AppAccent(
      id: 'rose',
      base: Color(0xFFF43657),
      dark: Color(0xFFBE2A44),
      light: Color(0xFFFD758C),
    ),
    AppAccent(
      id: 'slate',
      base: Color(0xFF64748B),
      dark: Color(0xFF4E5A6C),
      light: Color(0xFF95A2B5),
    ),
  ];

  /// Resolve a persisted id. Unknown ids (an accent removed in a later build, a
  /// hand-edited box) return null so the caller can fall back deliberately.
  static AppAccent? byId(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final accent in presets) {
      if (accent.id == id) return accent;
    }
    return null;
  }

  /// Minimum contrast an accent must have against white, so the app-wide
  /// `Colors.white` foreground stays readable on top of it. See the class doc.
  static const double minWhiteContrast = 3.8;

  /// Minimum contrast an accent must have against the *page*, so accent-coloured
  /// text and icons stay readable on the background.
  ///
  /// Measured against true black, which is the harder of the two darkness
  /// levels to sit on. 3.6 is just under the shipped red's 3.70 against the
  /// ordinary #181818, so this floor never rejects anything the app already
  /// ships. Without it a custom pick of near-black would satisfy the white rule
  /// perfectly and then vanish — the splash wordmark, which is nothing but
  /// accent on black, would be a blank screen.
  static const double minBackgroundContrast = 3.6;

  /// Build a full triple from a colour the user picked on the wheel.
  ///
  /// [seed] is honoured in hue and saturation, but its lightness is pulled into
  /// the band where the colour works in BOTH directions — white stays legible on
  /// top of it, and it stays legible on the page. Picking pure yellow gives a
  /// deep gold rather than an unreadable button; picking near-black gives a
  /// visible dark tone rather than an invisible one. The step is small (0.2%
  /// lightness) so the result stays as close to the pick as the contract allows.
  factory AppAccent.custom(Color seed) {
    final base = _enforceLegibility(seed);
    return AppAccent(
      id: customId,
      base: base,
      dark: _deriveDark(base),
      light: _deriveLight(base),
      isCustom: true,
    );
  }

  /// Contrast ratio of [color] against pure white, per WCAG 2.1.
  static double whiteContrast(Color color) =>
      1.05 / (color.computeLuminance() + 0.05);

  /// Contrast ratio of [color] against pure black, per WCAG 2.1.
  static double blackContrast(Color color) =>
      (color.computeLuminance() + 0.05) / 0.05;

  /// True when [color] is legible in both directions — see the class doc.
  static bool isLegibleAccent(Color color) =>
      whiteContrast(color) >= minWhiteContrast &&
      blackContrast(color) >= minBackgroundContrast;

  /// Walk the seed's HSL lightness into the legible band.
  ///
  /// The band is never empty: the two rules put relative luminance between
  /// 0.130 and 0.226, and luminance rises continuously with HSL lightness, so
  /// every hue and saturation passes through it. The walk is one-directional —
  /// too bright means darken, too dark means lighten — and bounded, so it
  /// always terminates.
  static Color _enforceLegibility(Color seed) {
    final opaque = seed.withValues(alpha: 1.0);
    if (isLegibleAccent(opaque)) return opaque;

    final hsl = HSLColor.fromColor(opaque);
    final tooBright = whiteContrast(opaque) < minWhiteContrast;
    final step = tooBright ? -0.002 : 0.002;
    var lightness = hsl.lightness;
    var best = opaque;

    for (var i = 0; i < 500; i++) {
      final next = lightness + step;
      if (next < 0 || next > 1) break;
      lightness = next;
      best = hsl.withLightness(lightness).toColor();
      if (isLegibleAccent(best)) return best;
    }
    return best;
  }

  /// sRGB scale — the exact transform that takes #E50914 to #B20710.
  static Color _deriveDark(Color base) => scaleChannels(base, 0.7773);

  /// Multiply every channel and snap the result back onto the 8-bit grid.
  ///
  /// The rounding is not cosmetic. Flutter's wide-gamut [Color] keeps channels
  /// as doubles, so `0x14 * 0.7773` lands on 0.06097 rather than on `0x10`'s
  /// 0.06275 — the same pixel once rasterised, but a different value to `==`.
  /// Snapping keeps derived colours comparable, hashable and equal to the hex
  /// codes this file documents.
  static Color scaleChannels(Color base, double factor) => Color.fromARGB(
    255,
    (base.r * 255 * factor).round().clamp(0, 255),
    (base.g * 255 * factor).round().clamp(0, 255),
    (base.b * 255 * factor).round().clamp(0, 255),
  );

  /// Lift 33.8% of the way to white with a small saturation boost — the exact
  /// transform that takes #E50914 to #FF4B55.
  static Color _deriveLight(Color base) {
    final hsl = HSLColor.fromColor(base);
    return hsl
        .withSaturation((hsl.saturation * 1.0818).clamp(0.0, 1.0))
        .withLightness(
          (hsl.lightness + (1.0 - hsl.lightness) * 0.3380).clamp(0.0, 1.0),
        )
        .toColor();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppAccent &&
          other.id == id &&
          other.base == base &&
          other.dark == dark &&
          other.light == light;

  @override
  int get hashCode => Object.hash(id, base, dark, light);
}
