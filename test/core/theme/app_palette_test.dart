import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/theme/app_accent.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/theme/app_palette.dart';

/// The Appearance feature made ~1900 colour reads across the app dynamic. The
/// one thing that must never regress is that the *default* is still exactly the
/// palette the app shipped with — an install that never opens Appearance has to
/// be pixel-identical to the previous build.
void main() {
  setUp(() {
    AppPalette.current = AppPalette.resolve(
      accent: AppAccent.fallback,
      darkness: AppDarkness.dark,
    );
  });

  group('default palette is byte-identical to the shipped constants', () {
    test('accent triple', () {
      expect(AppColors.primary, const Color(0xFFE50914));
      expect(AppColors.primaryDark, const Color(0xFFB20710));
      expect(AppColors.primaryLight, const Color(0xFFFF4B55));
    });

    test('neutral ramp', () {
      expect(AppColors.background, const Color(0xFF181818));
      expect(AppColors.navBackground, const Color(0xFF0F0F0F));
      expect(AppColors.surface, const Color(0xFF242424));
      expect(AppColors.card, const Color(0xFF282828));
      expect(AppColors.surfaceVariant, const Color(0xFF303030));
      expect(AppColors.border, const Color(0xFF3A3A3A));
      expect(AppColors.divider, const Color(0xFF2A2A2A));
    });

    test('fixed roles are untouched by the accent', () {
      expect(AppColors.error, const Color(0xFFE50914));
      // The exact old primaryLight — the "wrong answer" / "failed" states used
      // to borrow it, and must render identically now they point at error.
      expect(AppColors.errorLight, const Color(0xFFFF4B55));
      expect(AppColors.success, const Color(0xFF46D369));
      expect(AppColors.rating, const Color(0xFFFFD700));
      expect(AppColors.splashBackground, const Color(0xFF000000));

      AppPalette.current = AppPalette.resolve(
        accent: AppAccent.presets.firstWhere((a) => a.id == 'ocean'),
        darkness: AppDarkness.dark,
      );
      // Error is deliberately NOT the accent: a destructive action must still
      // read as destructive under a blue theme.
      expect(AppColors.error, const Color(0xFFE50914));
      expect(AppColors.errorLight, const Color(0xFFFF4B55));
      expect(AppColors.primary, isNot(AppColors.error));
      expect(AppColors.primaryLight, isNot(AppColors.errorLight));
    });

    test('hero gradient reproduces the old literal stops', () {
      // Was hard-coded as [#1E1416, #181818, #101010] in profile_page.dart.
      final top = AppColors.heroTop;
      expect(top.r * 255, closeTo(0x1E, 1.0));
      expect(top.g * 255, closeTo(0x14, 1.0));
      expect(top.b * 255, closeTo(0x16, 2.0));
      expect(AppColors.heroMid, const Color(0xFF181818));
      expect(AppColors.heroBottom, const Color(0xFF101010));
    });
  });

  group('AMOLED', () {
    setUp(() {
      AppPalette.current = AppPalette.resolve(
        accent: AppAccent.fallback,
        darkness: AppDarkness.black,
      );
    });

    test('background and nav go to true black', () {
      expect(AppColors.background, const Color(0xFF000000));
      expect(AppColors.navBackground, const Color(0xFF000000));
      expect(AppColors.isBlack, isTrue);
    });

    test('the depth ordering of the ramp survives', () {
      double l(Color c) => c.computeLuminance();
      expect(l(AppColors.background), lessThanOrEqualTo(l(AppColors.surface)));
      expect(l(AppColors.surface), lessThan(l(AppColors.card)));
      expect(l(AppColors.card), lessThan(l(AppColors.surfaceVariant)));
      // Hairlines have to stay clearly above the surface they sit on, or every
      // card edge disappears into the black.
      expect(l(AppColors.border), greaterThan(l(AppColors.surfaceVariant)));
      expect(l(AppColors.divider), greaterThan(l(AppColors.surface)));
    });

    test('the accent is untouched by the darkness level', () {
      expect(AppColors.primary, const Color(0xFFE50914));
    });

    test('hero gradient bottoms out at true black', () {
      expect(AppColors.heroBottom, const Color(0xFF000000));
      expect(AppColors.heroMid, const Color(0xFF000000));
    });
  });

  group('accent legibility contract', () {
    test('every preset keeps white readable on it', () {
      for (final accent in AppAccent.presets) {
        expect(
          AppAccent.whiteContrast(accent.base),
          greaterThanOrEqualTo(AppAccent.minWhiteContrast),
          reason: '${accent.id} would make white text unreadable on a fill',
        );
      }
    });

    test('every preset satisfies the two-sided contract', () {
      for (final accent in AppAccent.presets) {
        expect(
          AppAccent.isLegibleAccent(accent.base),
          isTrue,
          reason: '${accent.id} is outside the legible band',
        );
      }
    });

    test('every preset stays visible against both backgrounds', () {
      double ratio(Color a, Color b) {
        final la = a.computeLuminance();
        final lb = b.computeLuminance();
        final hi = la > lb ? la : lb;
        final lo = la > lb ? lb : la;
        return (hi + 0.05) / (lo + 0.05);
      }

      for (final accent in AppAccent.presets) {
        // 3.6 is just under the shipped red's own 3.70 against #181818, so no
        // accent is ever less legible than the one the app always had.
        expect(
          ratio(accent.base, const Color(0xFF181818)),
          greaterThan(3.6),
          reason: '${accent.id} disappears into the dark background',
        );
        expect(
          ratio(accent.base, const Color(0xFF000000)),
          greaterThan(3.6),
          reason: '${accent.id} disappears into the AMOLED background',
        );
      }
    });

    test('preset ids are unique and stable', () {
      final ids = AppAccent.presets.map((a) => a.id).toList();
      expect(ids.toSet().length, ids.length);
      expect(ids.first, 'red', reason: 'the default must stay first');
      expect(ids, isNot(contains(AppAccent.customId)));
    });
  });

  group('custom accents', () {
    test('a legible seed is kept as-is', () {
      const seed = Color(0xFF2F7BF6);
      expect(AppAccent.custom(seed).base, seed);
    });

    test('a too-bright seed is darkened until white works on it', () {
      // Pure yellow: 1.07:1 against white — unusable as a button fill.
      final accent = AppAccent.custom(const Color(0xFFFFFF00));
      expect(
        AppAccent.whiteContrast(accent.base),
        greaterThanOrEqualTo(AppAccent.minWhiteContrast),
      );
      // ...but it is still recognisably yellow, not brown mush.
      expect(
        HSLColor.fromColor(accent.base).hue,
        closeTo(60, 1.0),
      );
    });

    test('a too-dark seed is lightened until it shows on the page', () {
      // Near-black would pass the white rule perfectly and then be invisible on
      // the page — most visibly on the splash, which is nothing but the accent.
      final accent = AppAccent.custom(const Color(0xFF060606));
      expect(
        AppAccent.blackContrast(accent.base),
        greaterThanOrEqualTo(AppAccent.minBackgroundContrast),
      );
      expect(
        AppAccent.whiteContrast(accent.base),
        greaterThanOrEqualTo(AppAccent.minWhiteContrast),
      );
    });

    test('white and black seeds both terminate inside the legible band', () {
      for (final seed in const [
        Color(0xFFFFFFFF),
        Color(0xFF000000),
        Color(0xFF7F7F7F),
        Color(0xFF00FF00),
        Color(0xFF0000FF),
      ]) {
        final base = AppAccent.custom(seed).base;
        expect(
          AppAccent.isLegibleAccent(base),
          isTrue,
          reason: 'seed $seed landed outside the legible band at $base',
        );
      }
    });

    test('a translucent seed is forced opaque', () {
      expect(AppAccent.custom(const Color(0x402F7BF6)).base.a, 1.0);
    });

    test('derivation matches the shipped red family rule exactly', () {
      // The dark/light derivation is calibrated so that the default red
      // reproduces its own hand-tuned variants.
      final derived = AppAccent.custom(const Color(0xFFE50914));
      expect(derived.dark, const Color(0xFFB20710));
      expect(derived.light.r * 255, closeTo(0xFF, 1.0));
      expect(derived.light.g * 255, closeTo(0x4B, 1.0));
      expect(derived.light.b * 255, closeTo(0x55, 1.0));
    });

    test('byId rejects unknown and custom ids', () {
      expect(AppAccent.byId('nope'), isNull);
      expect(AppAccent.byId(''), isNull);
      expect(AppAccent.byId(null), isNull);
      expect(AppAccent.byId(AppAccent.customId), isNull);
      expect(AppAccent.byId('violet')?.id, 'violet');
    });
  });

  group('tab-bar tint', () {
    test('resolve() honours what it was asked for, not a policy', () {
      // The stored preference ships ON; the pure resolver still defaults off,
      // so a hand-built palette is exactly what the caller described.
      expect(AppPalette.current.tintNav, isFalse);
      expect(AppColors.isNavTinted, isFalse);
    });

    test('rides the same palette every other colour does', () {
      AppPalette.current = AppPalette.resolve(
        accent: AppAccent.fallback,
        darkness: AppDarkness.dark,
        tintNav: true,
      );
      expect(AppColors.isNavTinted, isTrue);
      // ...and changes nothing else.
      expect(AppColors.primary, const Color(0xFFE50914));
      expect(AppColors.background, const Color(0xFF181818));
    });

    test('counts as a difference, so the tree repaints when it flips', () {
      final off = AppPalette.resolve(
        accent: AppAccent.fallback,
        darkness: AppDarkness.dark,
      );
      final on = AppPalette.resolve(
        accent: AppAccent.fallback,
        darkness: AppDarkness.dark,
        tintNav: true,
      );
      expect(off, isNot(on));
      expect(off.hashCode, isNot(on.hashCode));
    });
  });

  test('palette equality is by accent and darkness', () {
    final a = AppPalette.resolve(
      accent: AppAccent.fallback,
      darkness: AppDarkness.dark,
    );
    final b = AppPalette.resolve(
      accent: AppAccent.fallback,
      darkness: AppDarkness.dark,
    );
    final c = AppPalette.resolve(
      accent: AppAccent.fallback,
      darkness: AppDarkness.black,
    );
    expect(a, b);
    expect(a, isNot(c));
  });
}
