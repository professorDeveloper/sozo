import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:soplay/core/brand/sozo_mark_geometry.dart';
import 'package:soplay/core/widgets/sozo_mark.dart';

/// The splash's original relief, condensed into a short mode-switch beat.
/// Geometry and decoded artwork are shared with the splash, never reloaded per
/// frame. The brand stays orange; destination colours belong to the badge.
class SozoDragonTransition extends StatefulWidget {
  const SozoDragonTransition({
    super.key,
    required this.progress,
    this.size = 156,
  });

  final double progress;
  final double size;

  @override
  State<SozoDragonTransition> createState() => _SozoDragonTransitionState();
}

class _SozoDragonTransitionState extends State<SozoDragonTransition> {
  @override
  void initState() {
    super.initState();
    if (SozoMarkGeometry.value == null) {
      SozoMarkGeometry.precache().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final geometry = SozoMarkGeometry.value;
    if (geometry == null) {
      return SozoMark(size: widget.size, color: const Color(0xFFEB7848));
    }
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: _DragonPainter(geometry, widget.progress.clamp(0, 1)),
      ),
    );
  }
}

class _DragonPainter extends CustomPainter {
  const _DragonPainter(this.geometry, this.progress);
  final SozoMarkGeometry geometry;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 512, size.height / 512);
    final ink = Paint()
      ..color = const Color(0xFFFFB77F)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 2.5;
    final draw = (progress / 0.55).clamp(0.0, 1.0);
    final fill = ((progress - 0.25) / 0.45).clamp(0.0, 1.0);
    canvas.drawPath(
      geometry.edge.extractPath(0, geometry.edge.length * draw),
      ink..color = const Color(0xFFFFB77F).withValues(alpha: 1 - fill),
    );
    if (fill < 1) {
      for (final stroke in geometry.strokes) {
        final t = ((draw - stroke.along * 0.35) / 0.65).clamp(0.0, 1.0);
        if (t > 0) {
          canvas.drawPath(
            stroke.metric.extractPath(0, stroke.metric.length * t),
            ink,
          );
        }
      }
    }
    final art = SozoMarkGeometry.art;
    if (art != null && fill > 0) {
      // One small layer contains the relief and its foot. No screen-sized
      // blur, particle simulation, or additional video decoder.
      canvas.saveLayer(
        geometry.bounds.inflate(2),
        Paint()..color = Colors.white.withValues(alpha: fill),
      );
      canvas.clipPath(geometry.body);
      final foot = SozoMarkGeometry.foot;
      final ground = SozoMarkGeometry.footGround;
      final stamp = ((progress - 0.65) / 0.35).clamp(0.0, 1.0);
      final turn = -0.12 * math.sin(stamp * math.pi);
      final lifted = foot != null && ground != null && turn.abs() > 0.0001;
      final base = lifted ? ground : art;
      canvas.drawImageRect(
        base,
        Rect.fromLTWH(0, 0, base.width.toDouble(), base.height.toDouble()),
        const Rect.fromLTWH(0, 0, 512, 512),
        Paint()..filterQuality = FilterQuality.medium,
      );
      if (lifted) {
        final pivot = SozoMarkGeometry.footPivot;
        canvas.save();
        canvas.translate(pivot.dx, pivot.dy);
        canvas.rotate(turn);
        canvas.translate(-pivot.dx, -pivot.dy);
        canvas.drawImageRect(
          foot,
          Rect.fromLTWH(0, 0, foot.width.toDouble(), foot.height.toDouble()),
          SozoMarkGeometry.footBox,
          Paint()
            ..filterQuality = FilterQuality.medium
            ..blendMode = ui.BlendMode.srcATop,
        );
        canvas.restore();
      }
      canvas.restore();
    } else if (art == null) {
      canvas.drawPath(
        geometry.body,
        Paint()..color = const Color(0xFFEB7848).withValues(alpha: fill),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DragonPainter old) =>
      old.progress != progress || old.geometry != geometry;
}
