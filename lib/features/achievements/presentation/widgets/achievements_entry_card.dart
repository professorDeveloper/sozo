import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/achievements/data/achievements_service.dart';
import 'package:soplay/features/achievements/domain/achievements.dart';
import 'package:soplay/features/achievements/presentation/widgets/achievement_medal.dart';

/// The way into the achievements, on the profile: the showcase and how many
/// of the whole set are earned.
class AchievementsEntryCard extends StatefulWidget {
  const AchievementsEntryCard({super.key});

  @override
  State<AchievementsEntryCard> createState() => _AchievementsEntryCardState();
}

class _AchievementsEntryCardState extends State<AchievementsEntryCard> {
  final AchievementsService? _service =
      getIt.isRegistered<AchievementsService>()
      ? getIt<AchievementsService>()
      : null;

  @override
  void initState() {
    super.initState();
    if (_service?.state.value == null) _service?.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final service = _service;
    if (service == null) return const SizedBox.shrink();
    return ValueListenableBuilder<AchievementsView?>(
      valueListenable: service.state,
      builder: (context, view, _) {
        final showcase = view?.showcase ?? const <String>[];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => context.push('/achievements'),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                child: Row(
                  children: [
                    if (showcase.isEmpty)
                      const AchievementMedal(
                        tier: MedalTier.locked,
                        icon: Icons.emoji_events_rounded,
                        size: 44,
                      )
                    else
                      _Stack(ids: showcase, view: view!),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'achievements.title'.tr(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            view == null || view.total == 0
                                ? 'achievements.entry_hint'.tr()
                                : 'achievements.unlocked_n'.tr(
                                    args: [
                                      '${view.unlockedCount}',
                                      '${view.total}',
                                    ],
                                  ),
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The showcase as overlapping medals, the first in front.
class _Stack extends StatelessWidget {
  const _Stack({required this.ids, required this.view});

  final List<String> ids;
  final AchievementsView view;

  @override
  Widget build(BuildContext context) {
    const size = 44.0;
    const step = 26.0;
    final shown = ids.take(3).toList();
    return SizedBox(
      width: size + step * (shown.length - 1),
      height: size,
      child: Stack(
        children: [
          for (var i = shown.length - 1; i >= 0; i--)
            Positioned(
              left: step * i,
              child: AchievementBadge(
                id: shown[i],
                tier: view.medalOf(shown[i]),
                size: size,
                glow: i == 0,
              ),
            ),
        ],
      ),
    );
  }
}
