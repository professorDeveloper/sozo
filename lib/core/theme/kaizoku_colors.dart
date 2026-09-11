import 'package:flutter/material.dart';

/// Kaizoku Design System color tokens (Direction 1: "Shin Kaizoku" — Cyber-Obsidian & Neon Crimson).
@immutable
class KaizokuColors {
  const KaizokuColors._();

  // ── Canvas & Surfaces ───────────────────────────────────────────────────────

  /// Deep void obsidian canvas (#090A0F).
  static const Color canvas = Color(0xFF090A0F);

  /// Pure AMOLED black canvas (#000000).
  static const Color canvasAmoled = Color(0xFF000000);

  /// Standard card and rail surface (#12151F).
  static const Color surface = Color(0xFF12151F);

  /// Elevated modals, dialogs, and popups (#1A1E2C).
  static const Color surfaceElevated = Color(0xFF1A1E2C);

  /// High-tier modal / drawer surface (#222738).
  static const Color surfaceHigh = Color(0xFF222738);

  /// Frosted glass background with 80% opacity.
  static const Color surfaceGlass = Color(0xCC141824);

  // ── Accent & Brand Colors ───────────────────────────────────────────────────

  /// Primary Kaizoku neon crimson (#FF2A55).
  static const Color crimson = Color(0xFFFF2A55);

  /// Darkened crimson for pressed states (#D61B43).
  static const Color crimsonDark = Color(0xFFD61B43);

  /// Light crimson for glow rings and highlights (#FF577B).
  static const Color crimsonLight = Color(0xFFFF577B);

  /// Solar amber for star ratings, VIP badges, and accents (#FFB800).
  static const Color amber = Color(0xFFFFB800);

  /// Electric cyan for downloads, tracker links, and active toggles (#00F5D4).
  static const Color cyan = Color(0xFF00F5D4);

  // ── Borders & Outlines ──────────────────────────────────────────────────────

  /// Subtle hairline divider and card outline (#1E2333).
  static const Color borderSubtle = Color(0xFF1E2333);

  /// Interactive hover / active border highlight (#FF2A55).
  static const Color borderActive = Color(0xFFFF2A55);

  /// 10-foot Android TV high-visibility focus ring (#FFB800).
  static const Color tvFocusRing = Color(0xFFFFB800);

  // ── Typography Colors ───────────────────────────────────────────────────────

  /// High-emphasis primary headings and titles (#F8F9FA).
  static const Color textHigh = Color(0xFFF8F9FA);

  /// Medium-emphasis secondary text, subtitles, and metadata (#A0A5B5).
  static const Color textMedium = Color(0xFFA0A5B5);

  /// Low-emphasis placeholders, timestamps, and captions (#5D6375).
  static const Color textMuted = Color(0xFF5D6375);

  // ── Semantic Convenience Aliases ────────────────────────────────────────────

  /// Primary accent color alias (neon crimson).
  static const Color primary = crimson;

  /// Light primary accent alias.
  static const Color primaryLight = crimsonLight;

  /// Dark primary accent alias.
  static const Color primaryDark = crimsonDark;

  /// Default background canvas alias (cyber obsidian).
  static const Color background = canvas;

  /// High-emphasis text primary alias.
  static const Color textPrimary = textHigh;

  /// Medium-emphasis text secondary alias.
  static const Color textSecondary = textMedium;

  /// Low-emphasis / hint text alias.
  static const Color textHint = textMuted;

  /// Standard card surface alias.
  static const Color card = surface;

  /// Navigation bar background alias.
  static const Color navBackground = surface;

  /// Standard subtle border alias.
  static const Color border = borderSubtle;

  /// Subtle hairline divider alias.
  static const Color divider = borderSubtle;

  /// Elevated surface variant alias.
  static const Color surfaceVariant = surfaceElevated;

  /// Semantic error / danger color (#FF4D4F).
  static const Color error = Color(0xFFFF4D4F);

  /// Subtle light error tint (#FF7875).
  static const Color errorLight = Color(0xFFFF7875);

  /// Semantic success color (#52C41A).
  static const Color success = Color(0xFF52C41A);

  /// Rating / star color alias (solar amber).
  static const Color rating = amber;

  /// Brand accent color alias (crimson).
  static const Color accent = crimson;

  // ── Design Spec Name Aliases ───────────────────────────────────────────────

  /// Neon crimson primary accent (#FF2A55).
  static const Color neonCrimson = crimson;

  /// Cyber obsidian dark surface (#12151F).
  static const Color cyberObsidian = surface;

  /// Solar amber badge and star accent (#FFB800).
  static const Color solarAmber = amber;

  /// Electric cyan accent for toggles and links (#00F5D4).
  static const Color electricCyan = cyan;

  /// Standard card outline border (#1E2333).
  static const Color cardBorder = borderSubtle;

  /// Elevated light surface variant (#1A1E2C).
  static const Color surfaceLight = surfaceElevated;

  /// Translucent glass border highlight.
  static const Color borderGlass = Color(0x2E1E2333);

  /// Podium medal colors.
  static const Color medalGold = amber;
  static const Color medalSilver = Color(0xFFC0C0C0);
  static const Color medalBronze = Color(0xFFCD7F32);

  // ── Scrims & Overlays ───────────────────────────────────────────────────────

  /// Poster card bottom title scrim gradient.
  static const LinearGradient posterScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Colors.transparent,
      Color(0x66090A0F),
      Color(0xF2090A0F),
    ],
    stops: [0.4, 0.75, 1.0],
  );

  /// Hero backdrop banner bottom blend gradient.
  static const LinearGradient heroScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Colors.transparent,
      Color(0x80090A0F),
      Color(0xFF090A0F),
    ],
    stops: [0.5, 0.8, 1.0],
  );

  /// Ambient glow box shadow for focused or highlighted cards.
  static List<BoxShadow> glowShadow({Color color = crimson, double radius = 14}) => [
        BoxShadow(
          color: color.withAlpha(80),
          blurRadius: radius,
          spreadRadius: 2,
        ),
      ];
}
