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
        final share = view == null || view.total == 0
            ? 0.0
            : view.unlockedCount / view.total;
        // The same frame as the streak card above it: the section label, the
        // 16-point gutter, the surface-to-background fall and the edge.
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
                child: Text(
                  'achievements.title'.tr().toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.textHint,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => context.push('/achievements'),
                  child: Ink(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.surface, AppColors.background],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: showcase.isEmpty
                            ? Colors.white.withValues(alpha: 0.05)
                            : const Color(0xFFFFA94D).withValues(alpha: 0.16),
                        width: 0.7,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                      child: Row(
                        children: [
                          if (showcase.isEmpty)
                            const AchievementMedal(
                              tier: MedalTier.locked,
                              icon: Icons.emoji_events_rounded,
                              size: 48,
                            )
                          else
                            _Stack(ids: showcase, view: view!),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  view == null || view.total == 0
                                      ? 'achievements.title'.tr()
                                      : 'achievements.unlocked_n'.tr(
                                          args: [
                                            '${view.unlockedCount}',
                                            '${view.total}',
                                          ],
                                        ),
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 7),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(3),
                                  child: LinearProgressIndicator(
                                    value: share,
                                    minHeight: 5,
                                    backgroundColor: Colors.white.withValues(
                                      alpha: 0.08,
                                    ),
                                    valueColor: const AlwaysStoppedAnimation(
                                      Color(0xFFFFA94D),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'achievements.entry_hint'.tr(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: AppColors.textSecondary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The showcase, side by side with room between them — overlapped, three
/// hexagons read as one blurred shape.
class _Stack extends StatelessWidget {
  const _Stack({required this.ids, required this.view});

  final List<String> ids;
  final AchievementsView view;

  @override
  Widget build(BuildContext context) {
    const size = 38.0;
    final shown = ids.take(3).toList();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          AchievementBadge(
            id: shown[i],
            tier: view.medalOf(shown[i]),
            size: size,
            // A halo on each would run them together again.
            glow: false,
          ),
        ],
      ],
    );
  }
}
