import 'dart:ui';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/streak/data/streak_service.dart';
import 'package:soplay/features/streak/domain/entities/streak_state.dart';
import 'package:soplay/features/streak/presentation/widgets/streak_calendar_heatmap.dart';

const Color _ember = Color(0xFFFFA94D);
const Color _emberDeep = Color(0xFFEF7A35);
const Color _emberSoft = Color(0xFFFFC078);
const Color _frost = Color(0xFF8FD4FF);

class StreakPage extends StatefulWidget {
  const StreakPage({super.key});

  @override
  State<StreakPage> createState() => _StreakPageState();
}

class _StreakPageState extends State<StreakPage>
    with SingleTickerProviderStateMixin {
  final StreakService _service = getIt<StreakService>();
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _service.state.addListener(_onChange);
    _service.loading.addListener(_onChange);
    _service.refresh();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _service.state.removeListener(_onChange);
    _service.loading.removeListener(_onChange);
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _service.state.value;
    final hasStreak = state.current > 0;
    final next = state.nextMilestone;
    var prev = 0;
    for (final m in state.milestones) {
      if (m.reached && m.value > prev) prev = m.value;
    }
    final double progress;
    if (next == null) {
      progress = 1.0;
    } else {
      final span = (next - prev).clamp(1, 100000);
      progress = ((state.current - prev) / span).clamp(0.0, 1.0);
    }
    final daysLeft = state.daysToNextMilestone ?? 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.background.withValues(alpha: 0.55),
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white.withValues(alpha: 0.06),
                    width: 0.5,
                  ),
                ),
              ),
            ),
          ),
        ),
        title: Text(
          'streak.section_label'.tr(),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: _service.loading.value
            ? const _StreakSkeleton()
            : RefreshIndicator(
                color: _ember,
                backgroundColor: AppColors.surface,
                edgeOffset: MediaQuery.paddingOf(context).top + kToolbarHeight,
                onRefresh: _service.refresh,
                child: _content(
                  context,
                  state,
                  hasStreak,
                  next,
                  progress,
                  daysLeft,
                ),
              ),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    StreakState state,
    bool hasStreak,
    int? next,
    double progress,
    int daysLeft,
  ) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0, 1),
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 14),
          child: child,
        ),
      ),
      child: SingleChildScrollView(
        // Always scrollable so the pull-to-refresh gesture works even when
        // the content is short enough to fit.
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: MediaQuery.paddingOf(context).top + kToolbarHeight + 20,
            ),
            Center(
              child: _BigFlame(pulse: _pulse, active: hasStreak),
            ),
            const SizedBox(height: 20),
            Center(
              child: Text(
                hasStreak
                    ? 'streak.current_n_days'.tr(args: ['${state.current}'])
                    : 'streak.empty_title'.tr(),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                hasStreak
                    ? (state.pingedToday
                          ? 'streak.locked_today'.tr()
                          : (state.isAtRisk
                                ? 'streak.risk_subtitle'.tr()
                                : 'streak.keep_going'.tr()))
                    : 'streak.empty_subtitle'.tr(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13.5,
                  height: 1.45,
                ),
              ),
            ),
            const SizedBox(height: 28),
            _ProgressBlock(
              current: state.current,
              next: next,
              progress: progress,
              daysLeft: daysLeft,
            ),
            const SizedBox(height: 24),
            _WeekStrip(state: state),
            const SizedBox(height: 24),
            Row(
              children: [
                _StatTile(
                  icon: Icons.emoji_events_rounded,
                  label: 'streak.record_label'.tr(),
                  value: '${state.longest}',
                ),
                const SizedBox(width: 12),
                _StatTile(
                  icon: Icons.calendar_month_rounded,
                  label: 'streak.total_days_label'.tr(),
                  value: '${state.totalDays}',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _StatTile(
                  icon: Icons.date_range_rounded,
                  label: 'streak.this_week_label'.tr(),
                  value: '${state.thisWeekCount}',
                ),
                const SizedBox(width: 12),
                _StatTile(
                  icon: Icons.ac_unit_rounded,
                  iconColor: _frost,
                  label: 'streak.freeze_label'.tr(),
                  value: 'streak.freeze_count'.tr(
                    args: [
                      '${state.freezes.available}',
                      '${state.freezes.max}',
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // What a freeze does is not guessable from a counter, and a
            // banked freeze the user does not know about is a feature that
            // does not exist as far as they are concerned.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(
                    Icons.info_outline_rounded,
                    color: AppColors.textHint,
                    size: 13,
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'streak.freeze_explainer'.tr(),
                    style: const TextStyle(
                      color: AppColors.textHint,
                      fontSize: 11.5,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 26),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                'streak.calendar_label'.tr(),
                style: const TextStyle(
                  color: AppColors.textHint,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            const SizedBox(height: 12),
            StreakCalendarHeatmap(days: state.calendar),
          ],
        ),
      ),
    );
  }
}

/// Placeholder shaped like the real page.
///
/// Deliberately mirrors the finished layout's blocks so the content does not
/// jump when it arrives — and, more importantly, so the page never shows a
/// confident "0 days" before it knows the answer.
class _StreakSkeleton extends StatelessWidget {
  const _StreakSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget block(double height, {double radius = 16, EdgeInsets? margin}) =>
        Container(
          height: height,
          margin: margin ?? const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(radius),
          ),
        );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: MediaQuery.paddingOf(context).top + kToolbarHeight + 20,
          ),
          Center(
            child: Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.04),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Center(child: block(28, radius: 8, margin: EdgeInsets.zero)),
          const SizedBox(height: 28),
          block(86),
          block(64),
          Row(
            children: [
              Expanded(child: block(98)),
              const SizedBox(width: 12),
              Expanded(child: block(98)),
            ],
          ),
          Row(
            children: [
              Expanded(child: block(98)),
              const SizedBox(width: 12),
              Expanded(child: block(98)),
            ],
          ),
        ],
      ),
    );
  }
}

class _BigFlame extends StatelessWidget {
  const _BigFlame({required this.pulse, required this.active});
  final Animation<double> pulse;
  final bool active;

  @override
  Widget build(BuildContext context) {
    if (!active) {
      return _circle(glow: 0, scale: 1);
    }
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(pulse.value);
        return _circle(glow: 0.22 + t * 0.2, scale: 1 + t * 0.06);
      },
    );
  }

  Widget _circle({required double glow, required double scale}) {
    return Transform.scale(
      scale: scale,
      child: Container(
        width: 104,
        height: 104,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: active
              ? const RadialGradient(colors: [_emberSoft, _emberDeep])
              : RadialGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.08),
                    Colors.white.withValues(alpha: 0.02),
                  ],
                ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: _emberDeep.withValues(alpha: glow),
                    blurRadius: 30,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Icon(
          Icons.local_fire_department_rounded,
          color: active ? Colors.white : Colors.white38,
          size: 56,
        ),
      ),
    );
  }
}

class _ProgressBlock extends StatelessWidget {
  const _ProgressBlock({
    required this.current,
    required this.next,
    required this.progress,
    required this.daysLeft,
  });

  final int current;
  final int? next;
  final double progress;
  final int daysLeft;

  @override
  Widget build(BuildContext context) {
    final goal = next;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.05),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$current',
                style: const TextStyle(
                  color: _emberSoft,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (goal != null)
                Text(
                  '$goal',
                  style: const TextStyle(
                    color: AppColors.textHint,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                )
              else
                const Icon(
                  Icons.emoji_events_rounded,
                  color: _emberSoft,
                  size: 15,
                ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 8,
                backgroundColor: Colors.white.withValues(alpha: 0.06),
                valueColor: const AlwaysStoppedAnimation(_ember),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            goal != null
                ? 'streak.days_to_milestone'.tr(args: ['$daysLeft'])
                : 'streak.milestone_subtitle'.tr(),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.state});
  final StreakState state;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final activity = state.weeklyActivity;
    final cells = List.generate(7, (i) {
      final StreakDay? day = activity.length == 7 ? activity[i] : null;
      final date =
          (day != null ? DateTime.tryParse(day.date) : null) ??
          now.subtract(Duration(days: 6 - i));
      // Derived from the date, not from the index. The server decides what the
      // week contains, and if it ever returns a window that does not end today
      // — a timezone edge, a stale cache — a hardcoded "last cell is today"
      // highlights the wrong day and marks the wrong one as still pending.
      final isToday = DateTime(date.year, date.month, date.day) == today;
      final isActive = day?.active ?? false;
      return _DayCell(
        weekday: _shortDay(date.weekday),
        day: '${date.day}',
        active: isActive,
        isToday: isToday,
        pingedToday: state.pingedToday,
      );
    });
    return Row(
      children: [
        for (var i = 0; i < cells.length; i++) ...[
          Expanded(child: cells[i]),
          if (i < cells.length - 1) const SizedBox(width: 7),
        ],
      ],
    );
  }

  String _shortDay(int weekday) {
    return switch (weekday) {
      DateTime.monday => 'streak.weekday_mon'.tr(),
      DateTime.tuesday => 'streak.weekday_tue'.tr(),
      DateTime.wednesday => 'streak.weekday_wed'.tr(),
      DateTime.thursday => 'streak.weekday_thu'.tr(),
      DateTime.friday => 'streak.weekday_fri'.tr(),
      DateTime.saturday => 'streak.weekday_sat'.tr(),
      _ => 'streak.weekday_sun'.tr(),
    };
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.weekday,
    required this.day,
    required this.active,
    required this.isToday,
    required this.pingedToday,
  });

  final String weekday;
  final String day;
  final bool active;
  final bool isToday;
  final bool pingedToday;

  @override
  Widget build(BuildContext context) {
    final todayPending = isToday && !pingedToday;
    return Column(
      children: [
        Text(
          weekday,
          style: TextStyle(
            color: isToday ? _emberSoft : AppColors.textHint,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 7),
        AspectRatio(
          aspectRatio: 1,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: active
                  ? _ember.withValues(alpha: 0.14)
                  : Colors.white.withValues(alpha: 0.04),
              border: Border.all(
                color: active
                    ? _ember.withValues(alpha: 0.45)
                    : (todayPending
                          ? _emberSoft.withValues(alpha: 0.55)
                          : Colors.white.withValues(alpha: 0.05)),
                width: active || todayPending ? 1 : 0.5,
              ),
            ),
            child: Center(
              child: active
                  ? const Icon(
                      Icons.local_fire_department_rounded,
                      color: _ember,
                      size: 18,
                    )
                  : Text(
                      day,
                      style: TextStyle(
                        color: todayPending
                            ? _emberSoft
                            : AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    this.iconColor = _emberSoft,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.05),
            width: 0.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(height: 10),
            Text(
              value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textHint,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
