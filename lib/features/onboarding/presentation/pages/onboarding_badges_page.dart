import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/widgets/app_buttons.dart';
import 'package:soplay/features/achievements/domain/achievements.dart';
import 'package:soplay/features/achievements/presentation/widgets/achievement_medal.dart';
import 'package:soplay/features/onboarding/domain/onboarding_flow.dart';
import 'package:soplay/features/onboarding/presentation/onboarding_navigation.dart';
import 'package:soplay/features/onboarding/presentation/widgets/onboarding_focus_button.dart';
import 'package:soplay/features/onboarding/presentation/widgets/onboarding_scaffold.dart';

/// Streaks and badges, shown rather than described: the flame medal with the
/// light moving across it, the other tiers around it, and a week filling in
/// toward the first badge.
class OnboardingBadgesPage extends StatelessWidget {
  const OnboardingBadgesPage({super.key});

  static const Color _ember = Color(0xFFFF8A3D);

  @override
  Widget build(BuildContext context) {
    return OnboardingScaffold(
      step: OnboardingStep.badges,
      glow: _ember,
      maxBodyWidth: 520,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Column(
          children: [
            const SizedBox(height: 250, child: _MedalStage()),
            const SizedBox(height: 18),
            const _WeekToBadge(),
            const SizedBox(height: 26),
            OnboardingHeading(
              center: true,
              title: 'onboarding.badges_title'.tr(),
              subtitle: 'onboarding.badges_body'.tr(),
            ),
          ],
        ),
      ),
      footer: OnboardingFocusButton(
        autofocus: true,
        child: AppPrimaryButton(
          label: 'onboarding.continue'.tr(),
          onPressed: () => onboardingNext(context),
        ),
      ),
    );
  }
}

/// The flame medal in the middle, the tiers above it around it — each struck
/// in on arrival, then drifting — and the light circling the lot.
class _MedalStage extends StatefulWidget {
  const _MedalStage();

  @override
  State<_MedalStage> createState() => _MedalStageState();
}

class _MedalStageState extends State<_MedalStage>
    with TickerProviderStateMixin {
  late final AnimationController _arrive = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 7),
  );

  // (id, tier, where round the middle, size)
  static const _around = [
    ('episodes', MedalTier.bronze, Alignment(-0.78, -0.62), 62.0),
    ('series_done', MedalTier.silver, Alignment(0.80, -0.58), 66.0),
    ('binge', MedalTier.gold, Alignment(-0.86, 0.66), 58.0),
    ('manga_done', MedalTier.silver, Alignment(0.84, 0.70), 56.0),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _arrive.value = 1;
      _drift.stop();
    } else {
      if (_arrive.value == 0) _arrive.forward();
      if (!_drift.isAnimating) _drift.repeat();
    }
  }

  @override
  void dispose() {
    _arrive.dispose();
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: Listenable.merge([_arrive, _drift]),
        builder: (context, _) {
          final t = _drift.value * 2 * math.pi;
          final light = Offset(math.cos(t) * 0.8, math.sin(t) * 0.6);
          double struck(int i) => Curves.easeOutBack.transform(
            ((_arrive.value - 0.12 * i) / 0.5).clamp(0.0, 1.0),
          );
          return Stack(
            alignment: Alignment.center,
            children: [
              // The flame's warmth behind the middle medal.
              Container(
                width: 230,
                height: 230,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      OnboardingBadgesPage._ember.withValues(
                        alpha: 0.28 * _arrive.value,
                      ),
                      OnboardingBadgesPage._ember.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
              for (final (i, (id, tier, at, size)) in _around.indexed)
                Align(
                  alignment: at,
                  child: Transform.translate(
                    offset: Offset(0, math.sin(t + i * 1.7) * 5),
                    child: Transform.scale(
                      scale: struck(i + 1),
                      child: Opacity(
                        opacity: 0.92,
                        child: AchievementBadge(
                          id: id,
                          tier: tier,
                          size: size,
                          light: light,
                        ),
                      ),
                    ),
                  ),
                ),
              Transform.translate(
                offset: Offset(0, math.sin(t) * 3),
                child: Transform.scale(
                  scale: struck(0),
                  child: Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.0012)
                      ..rotateY(math.sin(t) * 0.22)
                      ..rotateX(math.cos(t) * 0.10),
                    child: AchievementBadge(
                      id: 'streak',
                      tier: MedalTier.ember,
                      size: 136,
                      light: light,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Seven days lighting up one by one, and the first badge struck when the
/// last is lit.
class _WeekToBadge extends StatefulWidget {
  const _WeekToBadge();

  @override
  State<_WeekToBadge> createState() => _WeekToBadgeState();
}

class _WeekToBadgeState extends State<_WeekToBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 5200),
  );

  static const _days = [
    'streak.weekday_mon',
    'streak.weekday_tue',
    'streak.weekday_wed',
    'streak.weekday_thu',
    'streak.weekday_fri',
    'streak.weekday_sat',
    'streak.weekday_sun',
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _t.value = 1;
      _t.stop();
    } else if (!_t.isAnimating) {
      _t.repeat();
    }
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const ember = OnboardingBadgesPage._ember;
    return Column(
      children: [
        AnimatedBuilder(
          animation: _t,
          builder: (context, _) {
            // Seven steps over the first 70%, then the badge holds.
            final lit = (_t.value / 0.7 * 7).floor().clamp(0, 7);
            final won = lit == 7;
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < 7; i++) ...[
                  _Day(
                    label: _days[i].tr().characters.first,
                    lit: i < lit,
                    color: ember,
                  ),
                  const SizedBox(width: 8),
                ],
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 16,
                  color: Colors.white.withValues(alpha: 0.35),
                ),
                const SizedBox(width: 8),
                AnimatedScale(
                  scale: won ? 1.12 : 1,
                  duration: const Duration(milliseconds: 380),
                  curve: Curves.easeOutBack,
                  child: AchievementBadge(
                    id: 'streak',
                    tier: won ? MedalTier.bronze : MedalTier.locked,
                    size: 40,
                    glow: won,
                    progress: won ? null : lit / 7,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 10),
        Text(
          'onboarding.badges_week'.tr(),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: ember.withValues(alpha: 0.9),
            fontSize: OnbType.small,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _Day extends StatelessWidget {
  const _Day({required this.label, required this.lit, required this.color});

  final String label;
  final bool lit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: lit
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFFC078), Color(0xFFEF7A35)],
                  )
                : null,
            color: lit ? null : Colors.white.withValues(alpha: 0.08),
            boxShadow: lit
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.45),
                      blurRadius: 10,
                    ),
                  ]
                : null,
          ),
          child: lit
              ? const Icon(
                  Icons.local_fire_department_rounded,
                  size: 14,
                  color: Colors.white,
                )
              : null,
        ),
        const SizedBox(height: 5),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: lit ? 0.85 : 0.4),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
