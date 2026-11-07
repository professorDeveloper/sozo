import 'package:flutter/material.dart';
import 'package:soplay/core/theme/app_colors.dart';

/// A thin strip over the seek bar, brighter where reactions cluster.
class ReactionHeatmap extends StatelessWidget {
  const ReactionHeatmap({super.key, required this.bins});

  /// 0..1 per slice of the episode; see [ReactionTimeline.heatmap].
  final List<double> bins;

  @override
  Widget build(BuildContext context) {
    if (bins.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: CustomPaint(
        painter: _HeatmapPainter(bins, AppColors.primary),
        size: Size.infinite,
      ),
    );
  }
}

class _HeatmapPainter extends CustomPainter {
  _HeatmapPainter(this.bins, this.color);

  final List<double> bins;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width / bins.length;
    final paint = Paint();
    for (var i = 0; i < bins.length; i++) {
      final v = bins[i];
      if (v <= 0.04) continue;
      paint.color = color.withValues(alpha: 0.25 + 0.75 * v);
      final h = size.height * (0.4 + 0.6 * v);
      canvas.drawRect(
        Rect.fromLTWH(i * w, size.height - h, w + 0.5, h),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HeatmapPainter old) =>
      !identical(old.bins, bins) || old.color != color;
}
