import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/theme/app_palette.dart';
import 'package:soplay/core/theme/app_theme.dart';

/// What the chosen colours actually do, shown on the app's own controls.
///
/// ## Why this is not a picture of a screen
///
/// The obvious thing to build here is a little phone with the Home page inside
/// it. It was built, twice, and thrown away both times — because it cannot be
/// true. The real Home is a network of blocs, cached artwork and live rows;
/// nothing that paints instantly inside a settings list can be that page. What
/// gets drawn instead is a *guess* at it: invented titles, invented posters, a
/// layout that drifts from the real one the moment anybody touches Home. A
/// preview that misrepresents the app is worse than no preview, and it is what
/// made the earlier versions read as fake.
///
/// So this shows no screen at all. It shows the **real controls** — a real
/// [ElevatedButton], a real switch, a real card on a real background, the real
/// section tick, a real progress bar — at their real size, in the palette being
/// chosen. Every pixel here is something the user will meet again unchanged.
class ThemePreview extends StatelessWidget {
  const ThemePreview({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(kFieldRadius),
        border: Border.all(color: AppColors.border, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SampleSectionHead(),
          const SizedBox(height: 10),
          const _SampleCard(),
          const SizedBox(height: 14),
          const _SampleProgress(),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: SizedBox(
                  height: kButtonHeight,
                  child: ElevatedButton(
                    // Inert on purpose: this is a swatch of the button, not a
                    // button. Disabling it would show the disabled colours.
                    onPressed: () {},
                    child: Text('detail.play'.tr()),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: kButtonHeight,
                  child: OutlinedButton(
                    onPressed: () {},
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, kButtonHeight),
                      padding: EdgeInsets.zero,
                      side: BorderSide(
                        color: AppColors.textPrimary.withValues(alpha: 0.22),
                        width: 1.2,
                      ),
                    ),
                    child: Text(
                      'general.cancel'.tr(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The accent tick every section header on Home and Profile carries.
class _SampleSectionHead extends StatelessWidget {
  const _SampleSectionHead();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 15,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.primary,
                AppColors.primary.withValues(alpha: 0.55),
              ],
            ),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 9),
        Text(
          'home.continue_watching'.tr(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
        ),
        const Spacer(),
        const Icon(
          Icons.chevron_right_rounded,
          color: AppColors.textHint,
          size: 20,
        ),
      ],
    );
  }
}

/// A card on the page background, with the app's own 5%-white hairline — the
/// pair that tells you what AMOLED does. On true black the fill nearly
/// disappears and the hairline becomes the edge.
class _SampleCard extends StatelessWidget {
  const _SampleCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.textPrimary.withValues(alpha: 0.05),
          width: 0.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _SampleRow(
            icon: Icons.palette_outlined,
            title: 'appearance.title'.tr(),
            trailing: _SampleSwitch(),
          ),
          Divider(color: AppColors.divider, height: 1, indent: 60),
          _SampleRow(
            icon: Icons.play_circle_outline_rounded,
            title: 'profile.section_player'.tr(),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'general.done'.tr(),
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Icon(
                  Icons.arrow_drop_down_rounded,
                  color: AppColors.primary,
                  size: 22,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SampleRow extends StatelessWidget {
  const _SampleRow({
    required this.icon,
    required this.title,
    required this.trailing,
  });

  final IconData icon;
  final String title;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // The metrics from settings_tiles.dart, so the sample row and the real
      // rows under it sit on one grid.
      padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.textSecondary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.textSecondary, size: 17),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          trailing,
        ],
      ),
    );
  }
}

/// The app's switch in its on state — accent track, white thumb.
class _SampleSwitch extends StatelessWidget {
  const _SampleSwitch();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Switch.adaptive(
        value: true,
        onChanged: (_) {},
        activeThumbColor: Colors.white,
        activeTrackColor: AppColors.primary,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

/// A watched-progress bar, the accent's most common appearance in the app.
class _SampleProgress extends StatelessWidget {
  const _SampleProgress();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: 0.62,
              minHeight: 4,
              backgroundColor: AppColors.surfaceVariant,
              color: AppColors.primary,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '62%',
          style: TextStyle(
            color: AppColors.primary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// The two darkness levels, side by side, as what they actually are: a stack of
/// surfaces. No pretend screen — just the page colour, a card on it, its
/// hairline, and the accent, in the level being described.
class DarknessSample extends StatelessWidget {
  const DarknessSample({super.key, required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 10,
      child: Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: palette.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: palette.border, width: 0.8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7),
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: AppColors.textPrimary.withValues(alpha: 0.05),
                    width: 0.5,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: palette.primary,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.textPrimary.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 7),
            SizedBox(
              height: 12,
              child: Row(
                children: [
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: palette.card,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: palette.surfaceVariant,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
