import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/theme/app_palette.dart';
import 'package:soplay/core/widgets/app_buttons.dart';
import 'package:soplay/core/widgets/app_chip.dart';

/// A compact media surface using the app's shared controls and current palette.
/// Artwork is bundled: changing colours never starts a request or a decoder.
/// Interactions stay local to this sample and never change viewing history.
class ThemePreview extends StatefulWidget {
  const ThemePreview({super.key});

  @override
  State<ThemePreview> createState() => _ThemePreviewState();
}

class _ThemePreviewState extends State<ThemePreview> {
  bool _playing = false;
  bool _saved = false;
  String _quality = '1080p';

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 156,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  'assets/onboarding/anime_01.webp',
                  fit: BoxFit.cover,
                  alignment: const Alignment(0, -0.65),
                  cacheWidth: 720,
                  excludeFromSemantics: true,
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black26, AppColors.background],
                    ),
                  ),
                ),
                PositionedDirectional(
                  start: 16,
                  top: 12,
                  child: Text(
                    'SOZO',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 3,
                    ),
                  ),
                ),
                PositionedDirectional(
                  start: 16,
                  end: 16,
                  bottom: 12,
                  child: Text(
                    'Attack on Titan',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'home.continue_watching'.tr(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      '14:52 / 24:00',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: 0.62,
                    minHeight: 4,
                    color: AppColors.primary,
                    backgroundColor: AppColors.surfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: AppPrimaryButton(
                        label: (_playing ? 'player.pause' : 'player.resume')
                            .tr(),
                        icon: _playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        onPressed: () => setState(() => _playing = !_playing),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Material(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      child: IconButton(
                        isSelected: _saved,
                        tooltip: 'profile.favorites'.tr(),
                        color: AppColors.textSecondary,
                        selectedIcon: Icon(
                          Icons.bookmark_rounded,
                          color: AppColors.primary,
                        ),
                        icon: const Icon(Icons.bookmark_border_rounded),
                        onPressed: () => setState(() => _saved = !_saved),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final quality in ['720p', '1080p'])
                      AppChip(
                        label: quality,
                        selected: _quality == quality,
                        onTap: () => setState(() => _quality = quality),
                      ),
                  ],
                ),
              ],
            ),
          ),
          // Uses the same nav palette contract as the app, including tint off.
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.navBackground,
              border: Border(top: BorderSide(color: AppColors.divider)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Icon(
                  Icons.home_rounded,
                  color: AppPalette.current.tintNav
                      ? AppColors.primary
                      : AppColors.textPrimary,
                ),
                const Icon(Icons.search_rounded, color: AppColors.textHint),
                const Icon(
                  Icons.video_library_outlined,
                  color: AppColors.textHint,
                ),
                const Icon(
                  Icons.person_outline_rounded,
                  color: AppColors.textHint,
                ),
              ],
            ),
          ),
        ],
      ),
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
