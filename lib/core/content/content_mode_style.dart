import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'package:soplay/core/content/content_mode.dart';

/// How a mode looks: the colour it is recognised by and the glyph that stands
/// for it.
///
/// Kept out of [ContentMode] deliberately. That enum answers "what kind of
/// thing is this source", and it is read by code — the provider bloc, the
/// source hub, Hive — that has no business importing a painting library. This
/// is the other half of the same idea and belongs to the two places that draw
/// it: the switch animation and the chip that starts it.
///
/// ## Why three colours in a one-colour app
///
/// Sozo is teal on black everywhere, and three brand colours competing across
/// every screen would be a different app. These are not that. They appear in
/// the half-second where the whole catalogue is replaced underneath you, and on
/// the chip that caused it — nowhere else. In that half-second a colour says
/// which way you went faster than a word can be read, which is the entire job.
extension ContentModeStyle on ContentMode {
  Color get accent => switch (this) {
    // The existing brand teal. Watch is the mode most people are in most of
    // the time, so it is the one that should feel like "home" rather than like
    // somewhere they have travelled to.
    ContentMode.video => const Color(0xFF0FB3A6),
    ContentMode.manga => const Color(0xFF6D4AFF),
    ContentMode.novel => const Color(0xFFE0A23C),
  };
}

/// The mode's glyph, drawing itself.
///
/// [progress] runs 0 → 1 and moves a single pen along every stroke in turn, so
/// the shape is written rather than faded in. That is the difference the eye
/// reads as craft: a fade says an image appeared, a stroke says something drew
/// it.
class ModeGlyph extends StatelessWidget {
  const ModeGlyph({
    super.key,
    required this.mode,
    required this.color,
    this.size = 64,
    this.progress = 1,
  });

  final ContentMode mode;
  final Color color;
  final double size;
  final double progress;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: _GlyphPainter(mode: mode, color: color, progress: progress),
      isComplex: false,
    ),
  );
}

class _GlyphPainter extends CustomPainter {
  const _GlyphPainter({
    required this.mode,
    required this.color,
    required this.progress,
  });

  final ContentMode mode;
  final Color color;
  final double progress;

  /// Every glyph is drawn in a 24×24 box and scaled, so the stroke weight and
  /// the proportions hold at any size.
  static const double _box = 24;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final scale = size.width / _box;
    canvas.save();
    canvas.scale(scale);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.1
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = _pathFor(mode);
    canvas.drawPath(_trim(path, progress.clamp(0, 1)), paint);
    canvas.restore();
  }

  /// One pen across the whole glyph.
  ///
  /// The strokes are trimmed against the COMBINED length rather than each
  /// against its own, so four panels are drawn one after another the way a
  /// hand would, instead of four boxes growing at once.
  static Path _trim(Path path, double t) {
    if (t >= 1) return path;
    final metrics = path.computeMetrics().toList();
    final total = metrics.fold<double>(0, (sum, m) => sum + m.length);
    if (total == 0) return Path();
    var remaining = total * t;
    final out = Path();
    for (final m in metrics) {
      if (remaining <= 0) break;
      final take = math.min(remaining, m.length);
      out.addPath(m.extractPath(0, take), Offset.zero);
      remaining -= take;
    }
    return out;
  }

  static Path _pathFor(ContentMode mode) => switch (mode) {
    // A play triangle, drawn as three strokes from its point of rest.
    ContentMode.video => Path()
      ..moveTo(7.5, 4.5)
      ..lineTo(19, 12)
      ..lineTo(7.5, 19.5)
      ..close(),

    // Four panels in the arrangement a comic page actually uses — one tall on
    // the left, two stacked on the right, one wide underneath.
    ContentMode.manga => Path()
      ..addRRect(
        RRect.fromLTRBR(4, 4, 11, 14, const Radius.circular(1.4)),
      )
      ..addRRect(
        RRect.fromLTRBR(13, 4, 20, 9.5, const Radius.circular(1.4)),
      )
      ..addRRect(
        RRect.fromLTRBR(13, 11.5, 20, 20, const Radius.circular(1.4)),
      )
      ..addRRect(
        RRect.fromLTRBR(4, 16, 11, 20, const Radius.circular(1.4)),
      ),

    // Lines of text, left to right, the last one short the way a paragraph
    // ends.
    ContentMode.novel => Path()
      ..moveTo(4.5, 6)
      ..lineTo(19.5, 6)
      ..moveTo(4.5, 10.5)
      ..lineTo(19.5, 10.5)
      ..moveTo(4.5, 15)
      ..lineTo(17, 15)
      ..moveTo(4.5, 19.5)
      ..lineTo(12, 19.5),
  };

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.progress != progress || old.color != color || old.mode != mode;
}
