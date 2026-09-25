import 'dart:math' as math;

import 'package:flutter/material.dart';

/// One burst of confetti from the top, falling under gravity and tumbling.
/// With animations off it is a still scatter of a few pieces.
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({super.key, required this.colors, this.count = 90});

  final List<Color> colors;
  final int count;

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );
  late final List<_Piece> _pieces = _make();

  List<_Piece> _make() {
    final r = math.Random(7);
    return [
      for (var i = 0; i < widget.count; i++)
        _Piece(
          angle: -math.pi / 2 + (r.nextDouble() - 0.5) * math.pi * 0.9,
          speed: 0.7 + r.nextDouble() * 0.8,
          spin: (r.nextDouble() - 0.5) * 18,
          size: 5 + r.nextDouble() * 6,
          color: widget.colors[i % widget.colors.length],
          round: r.nextDouble() < 0.3,
          delay: r.nextDouble() * 0.15,
          sway: r.nextDouble() * math.pi * 2,
        ),
    ];
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _t.value = 0.55;
    } else if (_t.value == 0 && !_t.isAnimating) {
      _t.forward();
    }
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: CustomPaint(
            size: Size.infinite,
            painter: _ConfettiPainter(_t, _pieces),
          ),
        ),
      ),
    );
  }
}

class _Piece {
  const _Piece({
    required this.angle,
    required this.speed,
    required this.spin,
    required this.size,
    required this.color,
    required this.round,
    required this.delay,
    required this.sway,
  });

  final double angle;
  final double speed;
  final double spin;
  final double size;
  final Color color;
  final bool round;
  final double delay;
  final double sway;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.t, this.pieces) : super(repaint: t);

  final Animation<double> t;
  final List<_Piece> pieces;

  @override
  void paint(Canvas canvas, Size size) {
    if (t.value == 0) return;
    final origin = Offset(size.width / 2, size.height * 0.34);
    final reach = size.shortestSide * 0.9;
    final paint = Paint();
    for (final p in pieces) {
      final local = ((t.value - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (local <= 0) continue;
      // Launched up and out, then gravity takes over.
      final v = reach * p.speed;
      final x =
          math.cos(p.angle) * v * local +
          math.sin(p.sway + local * 9) * 10 * local;
      final y =
          math.sin(p.angle) * v * local + 0.5 * 2.4 * reach * local * local;
      final fade = local > 0.75 ? 1 - (local - 0.75) / 0.25 : 1.0;
      paint.color = p.color.withValues(alpha: fade.clamp(0.0, 1.0));
      canvas.save();
      canvas.translate(origin.dx + x, origin.dy + y);
      canvas.rotate(p.spin * local);
      if (p.round) {
        canvas.drawCircle(Offset.zero, p.size / 2, paint);
      } else {
        // A flat strip seen edge-on as it flips.
        final flip = math.cos(local * p.spin).abs().clamp(0.2, 1.0);
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset.zero,
            width: p.size,
            height: p.size * 0.5 * flip,
          ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => false;
}
