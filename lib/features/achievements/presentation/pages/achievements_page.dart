import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/achievements/data/achievements_service.dart';
import 'package:soplay/features/achievements/domain/achievements.dart';
import 'package:soplay/features/achievements/presentation/widgets/achievement_medal.dart';
import 'package:soplay/features/achievements/presentation/widgets/achievement_sheets.dart';
import 'package:soplay/features/streak/data/streak_service.dart';
import 'package:soplay/features/streak/domain/entities/streak_state.dart';

const Color _ember = Color(0xFFFFA94D);
const Color _emberDeep = Color(0xFFEF7A35);
const Color _emberSoft = Color(0xFFFFC078);

/// Every badge the active profile has, and how far it is from the next.
///
/// The streak leads: it is the habit the rest hang off and the one people
/// show off, so its badges sit at the top with the days still to go.
class AchievementsPage extends StatefulWidget {
  const AchievementsPage({super.key});

  @override
  State<AchievementsPage> createState() => _AchievementsPageState();
}

class _AchievementsPageState extends State<AchievementsPage> {
  final AchievementsService _service = getIt<AchievementsService>();
  final bool _signedIn = getIt<HiveService>().isLoggedIn;

  @override
  void initState() {
    super.initState();
    _service.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        title: Text('achievements.title'.tr()),
      ),
      body: !_signedIn
          ? const _SignedOut()
          : ValueListenableBuilder<AchievementsView?>(
              valueListenable: _service.state,
              builder: (context, view, _) {
                if (view == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                return RefreshIndicator(
                  color: _ember,
                  onRefresh: _service.refresh,
                  child: _Body(view: view),
                );
              },
            ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.view});

  final AchievementsView view;

  @override
  Widget build(BuildContext context) {
    final families = [
      for (final f in view.families)
        if (f.id != 'streak') f,
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        _StreakHero(view: view),
        const SizedBox(height: 14),
        _Summary(view: view),
        const SizedBox(height: 22),
        _Showcase(view: view),
        const SizedBox(height: 22),
        _SectionTitle('achievements.next_tiers'.tr()),
        const SizedBox(height: 10),
        _FamilyList(families: families, view: view),
        const SizedBox(height: 22),
        _SectionTitle('achievements.singles'.tr()),
        const SizedBox(height: 10),
        _SinglesGrid(view: view),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: Colors.white,
      fontSize: 16.5,
      fontWeight: FontWeight.w800,
    ),
  );
}

/// The streak: days in a row now, the four streak badges, and Iron will.
class _StreakHero extends StatelessWidget {
  const _StreakHero({required this.view});

  final AchievementsView view;

  @override
  Widget build(BuildContext context) {
    final family = view.family('streak');
    final iron = view.single('iron_will');
    return ValueListenableBuilder<StreakState>(
      valueListenable: getIt<StreakService>().state,
      builder: (context, streak, _) {
        final tiers = family?.tiers ?? const [7, 30, 100, 365];
        // Two different numbers, kept apart. A flame badge is earned by the
        // best streak ever and never taken back, so the medals light from
        // the longest. What to aim for next is the streak running now: a
        // broken 30-day streak keeps its badge, but the next target for a
        // 2-day run is the 7-day mark, not "all yours".
        final best = math.max(streak.longest, streak.current);
        final nextAt = tiers.indexWhere((t) => t > streak.current);
        final next = nextAt < 0 ? null : tiers[nextAt];
        final toGo = next == null ? 0 : next - streak.current;
        return InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: family == null
              ? null
              : () => openAchievement(context, view: view, id: 'streak'),
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [const Color(0xFF3A2410), AppColors.surface],
              ),
              border: Border.all(color: _ember.withValues(alpha: 0.28)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.local_fire_department_rounded,
                      color: _ember,
                      size: 38,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'achievements.streak_days'.tr(
                              args: ['${streak.current}'],
                            ),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            'achievements.streak_best'.tr(
                              args: ['${streak.longest}'],
                            ),
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (var i = 0; i < tiers.length; i++)
                      _StreakStep(
                        days: tiers[i],
                        tier: best >= tiers[i]
                            ? MedalTier.ofLevel(i + 1)
                            : MedalTier.locked,
                        progress: i == nextAt
                            ? (streak.current / tiers[i]).clamp(0.0, 1.0)
                            : null,
                        current: i == nextAt,
                      ),
                    _StreakStep(
                      days: 100,
                      id: 'iron_will',
                      tier: iron?.medal ?? MedalTier.locked,
                      label: 'achievements.name_iron_will'.tr(),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (next != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      // The streak running now, toward the next badge: a badge is
                      // kept when a streak breaks, but the next one needs a new run.
                      value: (streak.current / next).clamp(0.0, 1.0),
                      minHeight: 6,
                      backgroundColor: Colors.white.withValues(alpha: 0.1),
                      valueColor: const AlwaysStoppedAnimation(_emberSoft),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'achievements.streak_to_go'.tr(
                      args: [
                        '$toGo',
                        MedalTier.ofLevel(nextAt + 1).labelKey.tr(),
                      ],
                    ),
                    style: const TextStyle(color: _emberSoft, fontSize: 12.5),
                  ),
                ] else
                  Text(
                    'achievements.streak_maxed'.tr(),
                    style: const TextStyle(color: _emberSoft, fontSize: 12.5),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StreakStep extends StatelessWidget {
  const _StreakStep({
    required this.days,
    required this.tier,
    this.id = 'streak',
    this.label,
    this.progress,
    this.current = false,
  });

  final int days;
  final MedalTier tier;
  final String id;
  final String? label;

  /// The mark the running streak is heading for.
  final bool current;

  /// For the next badge still locked: how far the running streak has got.
  final double? progress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 60,
      child: Column(
        children: [
          AchievementBadge(id: id, tier: tier, size: 46, progress: progress),
          const SizedBox(height: 4),
          Text(
            label ?? 'achievements.days_short'.tr(args: ['$days']),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: current
                  ? _emberSoft
                  : tier == MedalTier.locked
                  ? AppColors.textHint
                  : tier.labelColor,
              fontSize: 11,
              fontWeight: current ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.view});

  final AchievementsView view;

  @override
  Widget build(BuildContext context) {
    final share = view.total == 0 ? 0.0 : view.unlockedCount / view.total;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'achievements.unlocked_n'.tr(
                  args: ['${view.unlockedCount}', '${view.total}'],
                ),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: share,
                  minHeight: 6,
                  backgroundColor: AppColors.border,
                  valueColor: const AlwaysStoppedAnimation(_emberDeep),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Showcase extends StatelessWidget {
  const _Showcase({required this.view});

  final AchievementsView view;

  @override
  Widget build(BuildContext context) {
    final ids = view.showcase;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _SectionTitle('achievements.showcase'.tr())),
            TextButton(
              onPressed: view.earnedIds.isEmpty
                  ? null
                  : () => showShowcasePicker(context, view: view),
              child: Text('achievements.showcase_edit'.tr()),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (ids.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              'achievements.showcase_empty'.tr(),
              style: TextStyle(color: AppColors.textSecondary, height: 1.4),
            ),
          )
        else
          // Three to a row, up to two rows.
          Column(
            children: [
              for (var row = 0; row * 3 < ids.length; row++) ...[
                if (row > 0) const SizedBox(height: 10),
                Row(
                  children: [
                    for (var i = row * 3; i < row * 3 + 3; i++) ...[
                      if (i > row * 3) const SizedBox(width: 10),
                      Expanded(
                        child: i < ids.length
                            ? _ShowcaseTile(id: ids[i], view: view)
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
      ],
    );
  }
}

class _ShowcaseTile extends StatelessWidget {
  const _ShowcaseTile({required this.id, required this.view});

  final String id;
  final AchievementsView view;

  @override
  Widget build(BuildContext context) {
    final tier = view.medalOf(id);
    final single = view.single(id);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => openAchievement(context, view: view, id: id),
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 14, 6, 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            SizedBox.square(
              dimension: 62,
              child: MedalTilt(
                builder: (light) => AchievementBadge(
                  id: id,
                  tier: tier,
                  size: 62,
                  light: light,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              AchievementDef.of(id).nameKey.tr(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              single != null ? 'achievements.rare'.tr() : tier.labelKey.tr(),
              style: TextStyle(
                color: tier.labelColor,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FamilyList extends StatelessWidget {
  const _FamilyList({required this.families, required this.view});

  final List<AchievementFamily> families;
  final AchievementsView view;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          for (var i = 0; i < families.length; i++) ...[
            if (i > 0) Divider(height: 1, color: AppColors.divider),
            _FamilyRow(family: families[i], view: view),
          ],
        ],
      ),
    );
  }
}

class _FamilyRow extends StatelessWidget {
  const _FamilyRow({required this.family, required this.view});

  final AchievementFamily family;
  final AchievementsView view;

  @override
  Widget build(BuildContext context) {
    final def = AchievementDef.of(family.id);
    final next = family.isMaxed ? null : family.tiers[family.tier];
    final value = family.value ?? 0;
    return InkWell(
      onTap: () => openAchievement(context, view: view, id: family.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            AchievementBadge(
              id: family.id,
              tier: family.medal,
              size: 46,
              glow: false,
              progress: family.tier == 0 ? family.progress : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          def.nameKey.tr(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        next == null
                            ? NumberFormat.decimalPattern().format(value)
                            : '${NumberFormat.decimalPattern().format(value)} / ${NumberFormat.decimalPattern().format(next)}',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: family.progress,
                      minHeight: 5,
                      backgroundColor: AppColors.border,
                      valueColor: AlwaysStoppedAnimation(
                        next == null
                            ? MedalTier.ember.labelColor
                            : MedalTier.ofLevel(family.tier + 1).labelColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    next == null
                        ? 'achievements.maxed'.tr()
                        : 'achievements.to_next'.tr(
                            args: [
                              MedalTier.ofLevel(family.tier + 1).labelKey.tr(),
                              def.unitKey.tr(args: ['${next - value}']),
                            ],
                          ),
                    style: TextStyle(color: AppColors.textHint, fontSize: 11.5),
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

class _SinglesGrid extends StatelessWidget {
  const _SinglesGrid({required this.view});

  final AchievementsView view;

  @override
  Widget build(BuildContext context) {
    final singles = [
      for (final s in view.singles)
        if (s.id != 'iron_will') s,
    ];
    return LayoutBuilder(
      builder: (context, box) {
        final columns = box.maxWidth > 560 ? 5 : 3;
        final width = (box.maxWidth - (columns - 1) * 10) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final s in singles)
              SizedBox(
                width: width,
                child: _SingleTile(single: s, view: view),
              ),
          ],
        );
      },
    );
  }
}

class _SingleTile extends StatelessWidget {
  const _SingleTile({required this.single, required this.view});

  final AchievementSingle single;
  final AchievementsView view;

  @override
  Widget build(BuildContext context) {
    final def = AchievementDef.of(single.id);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => openAchievement(context, view: view, id: single.id),
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 14, 8, 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            AchievementBadge(
              id: single.id,
              tier: single.medal,
              size: 52,
              progress: single.unlocked || single.value == null
                  ? null
                  : (single.value! / single.need).clamp(0.0, 1.0),
            ),
            const SizedBox(height: 8),
            Text(
              def.nameKey.tr(),
              maxLines: 2,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: single.unlocked ? Colors.white : AppColors.textSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignedOut extends StatelessWidget {
  const _SignedOut();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AchievementMedal(
              tier: MedalTier.locked,
              icon: Icons.emoji_events_rounded,
              size: 96,
            ),
            const SizedBox(height: 18),
            Text(
              'achievements.signed_out'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, height: 1.45),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.push('/login'),
              child: Text('achievements.sign_in'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}
