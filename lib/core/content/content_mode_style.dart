import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'package:soplay/core/content/catalogue.dart';
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
    this.catalogue,
    this.size = 64,
    this.progress = 1,
  });

  final ContentMode mode;

  /// Drawn instead of the mode's glyph when the switch is to a catalogue.
  final Catalogue? catalogue;
  final Color color;
  final double size;
  final double progress;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: _GlyphPainter(
        mode: mode,
        catalogue: catalogue,
        color: color,
        progress: progress,
      ),
      isComplex: false,
    ),
  );
}

class _GlyphPainter extends CustomPainter {
  const _GlyphPainter({
    required this.mode,
    required this.color,
    required this.progress,
    this.catalogue,
  });

  final ContentMode mode;
  final Catalogue? catalogue;
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

    final t = progress.clamp(0.0, 1.0);
    final path = catalogue != null ? _cataloguePath() : _pathFor(mode);
    final drawn = _trim(path, t);

    // Three passes. A soft wide stroke underneath is what makes a line on a
    // dark ground read as lit rather than printed; the crisp stroke is the
    // line itself; and while the pen is still moving, a bright dot sits at
    // its tip, so the eye follows the drawing rather than watching a shape
    // fill in.
    canvas.drawPath(
      drawn,
      Paint()
        ..color = color.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.2),
    );
    canvas.drawPath(
      drawn,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    if (t > 0 && t < 1) {
      final tip = _tipOf(path, t);
      if (tip != null) {
        canvas.drawCircle(
          tip,
          1.9,
          Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.95),
        );
      }
    }
    canvas.restore();
  }

  /// Where the pen is at [t] along the combined length.
  static Offset? _tipOf(Path path, double t) {
    final metrics = path.computeMetrics().toList();
    final total = metrics.fold<double>(0, (sum, m) => sum + m.length);
    if (total == 0) return null;
    var remaining = total * t;
    for (final m in metrics) {
      if (remaining <= m.length) {
        return m.getTangentForOffset(remaining)?.position;
      }
      remaining -= m.length;
    }
    return null;
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
    // A ring first, then the triangle inside it: the pen travels the whole
    // circle before it draws the play sign, which is the longest single line
    // of the three and the one that reads most as "being drawn".
    ContentMode.video =>
      Path()
        ..addOval(Rect.fromCircle(center: const Offset(12, 12), radius: 9.5))
        ..moveTo(9.6, 8.2)
        ..lineTo(16.2, 12)
        ..lineTo(9.6, 15.8)
        ..close(),

    // A manga page: the frame, then the diagonal cut that manga panels are
    // known for, then a small speech balloon in the upper panel. The
    // straight grid it replaced could have been any comic; this cannot.
    ContentMode.manga =>
      Path()
        ..addRRect(RRect.fromLTRBR(4, 3.5, 20, 20.5, const Radius.circular(2)))
        ..moveTo(4, 14.5)
        ..lineTo(20, 9)
        ..moveTo(11.5, 12)
        ..lineTo(20, 20.5)
        ..addOval(Rect.fromLTWH(6.5, 5.6, 5.4, 3.8))
        ..moveTo(7.6, 9.2)
        ..lineTo(7, 10.6)
        ..lineTo(8.8, 9.4),

    // An open book: spine, two pages with their outer edges curling up, and
    // a line of text on each page. Reads as a novel at a glance where four
    // bare lines read as a settings menu.
    ContentMode.novel =>
      Path()
        ..moveTo(12, 6.5)
        ..lineTo(12, 19.5)
        ..moveTo(12, 6.5)
        ..quadraticBezierTo(8.5, 4.2, 3.5, 5.5)
        ..lineTo(3.5, 18.2)
        ..quadraticBezierTo(8.5, 17, 12, 19.5)
        ..moveTo(12, 6.5)
        ..quadraticBezierTo(15.5, 4.2, 20.5, 5.5)
        ..lineTo(20.5, 18.2)
        ..quadraticBezierTo(15.5, 17, 12, 19.5)
        ..moveTo(6, 9.5)
        ..lineTo(9.6, 9)
        ..moveTo(6, 12.5)
        ..lineTo(9.6, 12)
        ..moveTo(14.4, 9)
        ..lineTo(18, 9.5)
        ..moveTo(14.4, 12)
        ..lineTo(18, 12.5),
  };

  /// A four-pointed star — the same sign the catalogue chips carry, drawn as
  /// one continuous stroke so the pen runs round it.
  static Path _cataloguePath() => Path()
    ..moveTo(12, 3.5)
    ..quadraticBezierTo(13.2, 10.8, 20.5, 12)
    ..quadraticBezierTo(13.2, 13.2, 12, 20.5)
    ..quadraticBezierTo(10.8, 13.2, 3.5, 12)
    ..quadraticBezierTo(10.8, 10.8, 12, 3.5)
    ..close();

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.mode != mode ||
      old.catalogue != catalogue;
}
