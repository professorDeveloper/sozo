import 'package:flutter/material.dart';
import 'kaizoku_colors.dart';

/// Cinematic typography definitions for Kaizoku across Mobile, Desktop, and 10-foot TV.
@immutable
class KaizokuTypography {
  const KaizokuTypography._();

  static const String fontFamily = 'Roboto';

  // ── Mobile / Compact Scale ──────────────────────────────────────────────────

  static const TextStyle displayLargeMobile = TextStyle(
    fontFamily: fontFamily,
    fontSize: 32,
    fontWeight: FontWeight.w900,
    height: 1.15,
    letterSpacing: -0.5,
    color: KaizokuColors.textHigh,
  );

  static const TextStyle displayMediumMobile = TextStyle(
    fontFamily: fontFamily,
    fontSize: 24,
    fontWeight: FontWeight.w800,
    height: 1.2,
    letterSpacing: -0.3,
    color: KaizokuColors.textHigh,
  );

  static const TextStyle headlineLargeMobile = TextStyle(
    fontFamily: fontFamily,
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 1.25,
    letterSpacing: -0.2,
    color: KaizokuColors.textHigh,
  );

  static const TextStyle headlineMediumMobile = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    height: 1.3,
    color: KaizokuColors.textHigh,
  );

  static const TextStyle bodyLargeMobile = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 1.4,
    color: KaizokuColors.textHigh,
  );

  static const TextStyle bodyMediumMobile = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.45,
    color: KaizokuColors.textMedium,
  );

  static const TextStyle labelSmallMobile = TextStyle(
    fontFamily: fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    height: 1.3,
    letterSpacing: 0.5,
    color: KaizokuColors.textMuted,
  );

  static const TextStyle badgeMobile = TextStyle(
    fontFamily: fontFamily,
    fontSize: 10,
    fontWeight: FontWeight.w800,
    height: 1.2,
    letterSpacing: 0.8,
    color: Colors.white,
  );

  // ── TV & Desktop 10-Foot / Widescreen Scale ──────────────────────────────────

  static const TextStyle displayLargeTv = TextStyle(
    fontFamily: fontFamily,
    fontSize: 44,
    fontWeight: FontWeight.w900,
    height: 1.15,
    letterSpacing: -0.5,
    color: KaizokuColors.textHigh,
  );

  static const TextStyle displayMediumTv = TextStyle(
    fontFamily: fontFamily,
    fontSize: 34,
    fontWeight: FontWeight.w800,
    height: 1.2,
    letterSpacing: -0.3,
    color: KaizokuColors.textHigh,
  );

  static const TextStyle headlineLargeTv = TextStyle(
    fontFamily: fontFamily,
    fontSize: 26,
    fontWeight: FontWeight.w700,
    height: 1.25,
    letterSpacing: -0.2,
    color: KaizokuColors.textHigh,
  );

  static const TextStyle headlineMediumTv = TextStyle(
    fontFamily: fontFamily,
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 1.3,
    color: KaizokuColors.textHigh,
  );

  static const TextStyle bodyLargeTv = TextStyle(
    fontFamily: fontFamily,
    fontSize: 17,
    fontWeight: FontWeight.w500,
    height: 1.4,
    color: KaizokuColors.textHigh,
  );

  static const TextStyle bodyMediumTv = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.45,
    color: KaizokuColors.textMedium,
  );

  static const TextStyle labelSmallTv = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.3,
    letterSpacing: 0.5,
    color: KaizokuColors.textMuted,
  );

  static const TextStyle badgeTv = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w800,
    height: 1.2,
    letterSpacing: 1.0,
    color: Colors.white,
  );
}
