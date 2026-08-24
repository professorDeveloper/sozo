import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:soplay/core/theme/app_colors.dart';

/// A circular countdown ring with the seconds-remaining badge in its centre.
/// The window length comes from [totalSeconds] — never assumed — so the ring
/// follows whatever answer window the round payload declares. The arc drains
/// smoothly between the bloc's 1-second ticks (an implicit tween bridges each
/// tick) and the whole ring flips to brand-red when under 4 seconds remain.
class CountdownRing extends StatelessWidget {
  const CountdownRing({
    super.key,
    required this.secondsRemaining,
    required this.totalSeconds,
    this.size = 54,
  });

  final int secondsRemaining;
  final int totalSeconds;
  final double size;

  bool get _danger => secondsRemaining < 4;

  @override
  Widget build(BuildContext context) {
    // The last four seconds are an alarm state, so they stay red whatever the
    // accent is — a green "hurry up" ring says the opposite of what it means.
    final color = _danger ? AppColors.error : Colors.white;
    final target = totalSeconds <= 0
        ? 0.0
        : (secondsRemaining / totalSeconds).clamp(0.0, 1.0);

    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        // On each tick [target] drops by 1/total; TweenAnimationBuilder tweens
        // from the last painted value to the new end for a continuous sweep.
        tween: Tween<double>(begin: 1, end: target),
        duration: const Duration(milliseconds: 950),
        curve: Curves.linear,
        builder: (context, value, _) {
          return CustomPaint(
            painter: _RingPainter(progress: value, color: color),
            child: Center(
              child: Text(
                '$secondsRemaining',
                style: TextStyle(
                  color: color,
                  fontSize: size * 0.34,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 4.0;
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = AppColors.border;
    canvas.drawCircle(center, radius, track);

    if (progress <= 0) return;

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;

    // Start at 12 o'clock, drain clockwise as time runs out.
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * progress, false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}
