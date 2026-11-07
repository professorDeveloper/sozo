import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/system/platform_utils.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/progress/data/progress_service.dart';
import 'package:soplay/features/progress/presentation/widgets/level_ring.dart';
import 'package:soplay/features/progress/presentation/widgets/user_badge_line.dart';

/// "Level 12": the new level, and what it opened in the locker.
class LevelUpDialog extends StatelessWidget {
  const LevelUpDialog({super.key, required this.levelUp, this.onOpen});

  final LevelUp levelUp;
  final VoidCallback? onOpen;

  static Future<void> show(
    BuildContext context,
    LevelUp levelUp, {
    VoidCallback? onOpen,
  }) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black.withValues(alpha: 0.8),
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (_, _, _) => LevelUpDialog(levelUp: levelUp, onOpen: onOpen),
      transitionBuilder: (_, anim, _, child) {
        final t = Curves.easeOutBack.transform(anim.value.clamp(0.0, 1.0));
        return Opacity(
          opacity: anim.value,
          child: Transform.scale(scale: 0.85 + 0.15 * t, child: child),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final unlocked = levelUp.unlocked
        .where((c) => Cosmetics.isKnown(c.slot, c.id))
        .take(4)
        .toList();
    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 28),
            constraints: const BoxConstraints(maxWidth: 360),
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.surface, AppColors.background],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.3),
                width: 0.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.18),
                  blurRadius: 34,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'progress.level_up'.tr().toUpperCase(),
                  style: TextStyle(
                    color: AppColors.primaryLight,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.8,
                  ),
                ),
                const SizedBox(height: 18),
                LevelRing(level: levelUp.to, fraction: 1, size: 132),
                const SizedBox(height: 16),
                Text(
                  'progress.level_reached'.tr(args: ['${levelUp.to}']),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (unlocked.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    'progress.unlocked_new'.tr(),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final c in unlocked)
                        Chip(
                          label: Text(Cosmetics.label(c.slot, c.id)),
                          visualDensity: VisualDensity.compact,
                          backgroundColor: Colors.white.withValues(alpha: 0.06),
                          side: BorderSide.none,
                          labelStyle: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    if (onOpen != null)
                      Expanded(
                        child: TextButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            onOpen!();
                          },
                          child: Text('progress.open_locker'.tr()),
                        ),
                      ),
                    if (onOpen != null) const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        autofocus: isTvPlatform,
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text('achievements.great'.tr()),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
