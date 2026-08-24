import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/theme/app_theme.dart';

const Color _ember = Color(0xFFFFA94D);
const Color _emberDeep = Color(0xFFEF7A35);
const Color _emberSoft = Color(0xFFFFC078);
const Color _frost = Color(0xFF8FD4FF);
const Color _frostDeep = Color(0xFF4FA3E0);

class StreakMilestoneDialog extends StatefulWidget {
  const StreakMilestoneDialog({
    super.key,
    required this.days,
    this.freezeAwarded = false,
  });

  final int days;
  final bool freezeAwarded;

  static Future<void> show(
    BuildContext context,
    int days, {
    bool freezeAwarded = false,
  }) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Streak milestone',
      barrierColor: Colors.black.withValues(alpha: 0.78),
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (_, _, _) =>
          StreakMilestoneDialog(days: days, freezeAwarded: freezeAwarded),
      transitionBuilder: (_, anim, _, child) {
        final scale = Curves.easeOutBack.transform(anim.value.clamp(0, 1));
        return Opacity(
          opacity: anim.value,
          child: Transform.scale(scale: 0.85 + 0.15 * scale, child: child),
        );
      },
    );
  }

  @override
  State<StreakMilestoneDialog> createState() => _StreakMilestoneDialogState();
}

class _StreakMilestoneDialogState extends State<StreakMilestoneDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _confettiCtl;

  @override
  void initState() {
    super.initState();
    _confettiCtl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..forward();
  }

  @override
  void dispose() {
    _confettiCtl.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    final text = 'streak.share_text'.tr(args: ['${widget.days}']);
    await Share.share(text);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _confettiCtl,
                    builder: (_, _) => CustomPaint(
                      painter: _ConfettiPainter(_confettiCtl.value),
                    ),
                  ),
                ),
              ),
              Container(
                constraints: const BoxConstraints(maxWidth: 360),
                padding: const EdgeInsets.fromLTRB(24, 30, 24, 22),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.surface, AppColors.background],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: _ember.withValues(alpha: 0.22),
                    width: 0.8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _emberDeep.withValues(alpha: 0.16),
                      blurRadius: 34,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Flame(),
                    const SizedBox(height: 18),
                    Text(
                      'streak.milestone_title'
                          .tr(args: ['${widget.days}']),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'streak.milestone_subtitle'.tr(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                    if (widget.freezeAwarded) ...[
                      const SizedBox(height: 16),
                      const _FreezeAwardedChip(),
                    ],
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.18),
                              ),
                              foregroundColor: AppColors.textPrimary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(kButtonRadius),
                              ),
                            ),
                            child: Text(
                              'streak.cta_continue'.tr(),
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _share,
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              backgroundColor: AppColors.primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(kButtonRadius),
                              ),
                            ),
                            icon: const Icon(Icons.ios_share_rounded, size: 16),
                            label: Text(
                              'streak.cta_share'.tr(),
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Flame extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 84,
      height: 84,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [_emberSoft, _emberDeep],
          stops: [0, 1],
        ),
        boxShadow: [
          BoxShadow(
            color: _emberDeep.withValues(alpha: 0.4),
            blurRadius: 28,
            spreadRadius: 2,
          ),
        ],
      ),
      child: const Icon(
        Icons.local_fire_department_rounded,
        color: Colors.white,
        size: 50,
      ),
    );
  }
}

class _FreezeAwardedChip extends StatelessWidget {
  const _FreezeAwardedChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _frost.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: _frost.withValues(alpha: 0.35),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.ac_unit_rounded, color: _frost, size: 16),
          const SizedBox(width: 6),
          Text(
            'streak.freeze_awarded_title'.tr(),
            style: const TextStyle(
              color: _frost,
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// Celebration shown when a streak-freeze automatically covered a missed day.
class StreakFreezeSavedDialog extends StatelessWidget {
  const StreakFreezeSavedDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Streak freeze saved',
      barrierColor: Colors.black.withValues(alpha: 0.78),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, _, _) => const StreakFreezeSavedDialog(),
      transitionBuilder: (_, anim, _, child) {
        final scale = Curves.easeOutBack.transform(anim.value.clamp(0, 1));
        return Opacity(
          opacity: anim.value,
          child: Transform.scale(scale: 0.85 + 0.15 * scale, child: child),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 360),
            padding: const EdgeInsets.fromLTRB(24, 30, 24, 22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF20262B), Color(0xFF15181B)],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: _frost.withValues(alpha: 0.24),
                width: 0.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: _frostDeep.withValues(alpha: 0.18),
                  blurRadius: 34,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const RadialGradient(
                      colors: [_frost, _frostDeep],
                      stops: [0, 1],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _frostDeep.withValues(alpha: 0.4),
                        blurRadius: 28,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.ac_unit_rounded,
                    color: Colors.white,
                    size: 46,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'streak.freeze_saved_title'.tr(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'streak.freeze_saved_subtitle'.tr(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      backgroundColor: _frostDeep,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(kButtonRadius),
                      ),
                    ),
                    child: Text(
                      'streak.cta_continue'.tr(),
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.progress);
  final double progress;

  static const _seedCount = 36;
  static const _palette = <Color>[
    Color(0xFFFFA94D),
    Color(0xFFFFC078),
    Color(0xFFFFD86B),
    Color(0xFFFFFFFF),
    Color(0xFFEF7A35),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(7);
    final cx = size.width / 2;
    final cy = size.height / 2;
    for (var i = 0; i < _seedCount; i++) {
      final angle = (i / _seedCount) * math.pi * 2 +
          rng.nextDouble() * 0.4;
      final dist = 40 + rng.nextDouble() * 180 * progress;
      final dx = cx + math.cos(angle) * dist;
      final dy = cy + math.sin(angle) * dist + progress * 60;
      final color = _palette[i % _palette.length].withValues(
        alpha: (1.0 - progress).clamp(0, 1),
      );
      final paint = Paint()..color = color;
      final w = 5.0 + rng.nextDouble() * 4;
      final h = 8.0 + rng.nextDouble() * 6;
      canvas.save();
      canvas.translate(dx, dy);
      canvas.rotate(progress * math.pi * 2 + i.toDouble());
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: w, height: h),
          const Radius.circular(1.5),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
