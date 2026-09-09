import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/streak/data/streak_service.dart';
import 'package:soplay/features/streak/domain/entities/streak_state.dart';

const Color _ember = Color(0xFFFFA94D);
const Color _emberDeep = Color(0xFFEF7A35);
const Color _emberSoft = Color(0xFFFFC078);
const Color _frost = Color(0xFF8FD4FF);

class StreakCard extends StatefulWidget {
  const StreakCard({super.key});

  @override
  State<StreakCard> createState() => _StreakCardState();
}

class _StreakCardState extends State<StreakCard> {
  final StreakService _service = getIt<StreakService>();
  final HiveService _hive = getIt<HiveService>();

  @override
  void initState() {
    super.initState();
    _service.state.addListener(_onChange);
    if (_hive.isLoggedIn) _service.refresh();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _service.state.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_hive.isLoggedIn) return const SizedBox.shrink();
    final state = _service.state.value;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
            child: Text(
              'streak.section_label'.tr(),
              style: const TextStyle(
                color: AppColors.textHint,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
          _CompactStreakRow(state: state),
        ],
      ),
    );
  }
}

class _CompactStreakRow extends StatelessWidget {
  const _CompactStreakRow({required this.state});
  final StreakState state;

  @override
  Widget build(BuildContext context) {
    final hasStreak = state.current > 0;
    final subtitle = hasStreak
        ? (state.pingedToday
            ? 'streak.locked_today'.tr()
            : (state.isAtRisk
                ? 'streak.risk_subtitle'.tr()
                : 'streak.keep_going'.tr()))
        : 'streak.empty_subtitle'.tr();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/streak'),
        child: Ink(
          decoration: BoxDecoration(
            // surface -> background, which is #242424 -> #181818 on the
            // default theme: the same top-left-lighter fall the literals
            // #222222 -> #1A1A1A gave, but it follows AMOLED.
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.surface, AppColors.background],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: hasStreak
                  ? _ember.withValues(alpha: 0.16)
                  : Colors.white.withValues(alpha: 0.05),
              width: 0.7,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                _MiniFlame(active: hasStreak),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasStreak
                            ? 'streak.current_n_days'
                                .tr(args: ['${state.current}'])
                            : 'streak.empty_title'.tr(),
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (state.freezes.available > 0)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.ac_unit_rounded,
                          color: _frost,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${state.freezes.available}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (state.longest > 0)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.emoji_events_rounded,
                          color: _emberSoft,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${state.longest}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textHint,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniFlame extends StatelessWidget {
  const _MiniFlame({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
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
                  color: _emberDeep.withValues(alpha: 0.28),
                  blurRadius: 12,
                  spreadRadius: 0.5,
                ),
              ]
            : null,
      ),
      child: Icon(
        Icons.local_fire_department_rounded,
        color: active ? Colors.white : Colors.white38,
        size: 22,
      ),
    );
  }
}
