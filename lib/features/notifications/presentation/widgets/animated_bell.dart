import 'dart:math' as math;

import 'package:flutter/material.dart';

enum BellState { off, on, muted }

/// The follow bell: an outline that fills when switched on, with a swing and
/// a ring going out from it, and a struck-through bell when muted.
///
/// Rings whenever [ringToken] changes, so a caller can ring it on demand (the
/// priming sheet does, on a loop) without owning an animation of its own.
class AnimatedBell extends StatefulWidget {
  const AnimatedBell({
    super.key,
    required this.state,
    required this.color,
    this.size = 22,
    this.ringToken = 0,
    this.ringColor,
    this.ringOnAppear = false,
  });

  final BellState state;
  final Color color;
  final Color? ringColor;
  final double size;
  final int ringToken;

  /// Rings once when first shown.
  final bool ringOnAppear;

  @override
  State<AnimatedBell> createState() => _AnimatedBellState();
}

class _AnimatedBellState extends State<AnimatedBell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ring = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.ringOnAppear) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _play();
      });
    }
  }

  @override
  void didUpdateWidget(AnimatedBell old) {
    super.didUpdateWidget(old);
    final turnedOn = old.state != BellState.on && widget.state == BellState.on;
    if (turnedOn || old.ringToken != widget.ringToken) _play();
  }

  void _play() {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
    _ring.forward(from: 0);
  }

  @override
  void dispose() {
    _ring.dispose();
    super.dispose();
  }

  IconData get _icon => switch (widget.state) {
    BellState.off => Icons.notifications_none_rounded,
    BellState.on => Icons.notifications_active_rounded,
    BellState.muted => Icons.notifications_off_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return SizedBox.square(
      dimension: size,
      child: AnimatedBuilder(
        animation: _ring,
        builder: (context, child) {
          final t = _ring.value;
          // A damped swing: three and a half beats that die away.
          final swing = _ring.isAnimating
              ? math.sin(t * math.pi * 7) * (1 - t) * 0.42
              : 0.0;
          return Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              if (_ring.isAnimating)
                CustomPaint(
                  size: Size.square(size),
                  painter: _RingPainter(
                    progress: Curves.easeOutCubic.transform(t),
                    color: widget.ringColor ?? widget.color,
                  ),
                ),
              Transform.rotate(
                angle: swing,
                alignment: const Alignment(0, -0.85),
                child: child,
              ),
            ],
          );
        },
        child: AnimatedSwitcher(
          duration: reduce ? Duration.zero : const Duration(milliseconds: 260),
          switchInCurve: const Cubic(0.05, 0.7, 0.1, 1.0),
          transitionBuilder: (child, anim) => ScaleTransition(
            scale: Tween<double>(begin: 0.6, end: 1).animate(anim),
            child: FadeTransition(opacity: anim, child: child),
          ),
          child: Icon(
            _icon,
            key: ValueKey(widget.state),
            size: size,
            color: widget.color,
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final base = size.shortestSide / 2;
    for (final delay in const [0.0, 0.22]) {
      final p = ((progress - delay) / (1 - delay)).clamp(0.0, 1.0);
      if (p <= 0) continue;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * (1 - p) + 0.5
        ..color = color.withValues(alpha: 0.55 * (1 - p));
      canvas.drawCircle(center, base * (0.9 + p * 0.9), paint);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}
