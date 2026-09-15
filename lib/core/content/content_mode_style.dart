import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'package:soplay/core/content/catalogue.dart';
import 'package:soplay/core/content/catalogue_logo.dart';
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
///
/// A catalogue has a mark of its own that cannot be traced as strokes, so for
/// one the pen draws a ring and the logo is wiped in behind it, clockwise from
/// the top — the same beat, with the actual mark in it.
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
  Widget build(BuildContext context) {
    final c = catalogue;
    if (c == null) {
      return SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _GlyphPainter(mode: mode, color: color, progress: progress),
          isComplex: false,
        ),
      );
    }
    final t = progress.clamp(0.0, 1.0);
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.square(size),
            painter: _RingPainter(color: color, progress: t),
          ),
          ClipPath(
            clipper: _SweepClipper(t),
            child: CatalogueLogo(catalogue: c, size: size * 0.58),
          ),
        ],
      ),
    );
  }
}

/// The ring the pen draws round a catalogue's mark: the glyph strokes' three
/// passes on one circle, from the top.
class _RingPainter extends CustomPainter {
  const _RingPainter({required this.color, required this.progress});

  final Color color;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final inset = size.width * 0.08;
    final ring = Path()
      ..addArc(
        Rect.fromLTWH(
          inset,
          inset,
          size.width - 2 * inset,
          size.height - 2 * inset,
        ),
        -math.pi / 2,
        2 * math.pi,
      );
    _GlyphPainter.strokes(
      canvas,
      ring,
      progress,
      color,
      scale: size.width / _GlyphPainter._box,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}

/// A pie wedge from the top, clockwise: what the pen has passed is shown.
class _SweepClipper extends CustomClipper<Path> {
  const _SweepClipper(this.progress);

  final double progress;

  @override
  Path getClip(Size size) {
    if (progress >= 1) return Path()..addRect(Offset.zero & size);
    if (progress <= 0) return Path();
    final c = size.center(Offset.zero);
    final r = size.longestSide;
    return Path()
      ..moveTo(c.dx, c.dy)
      ..lineTo(c.dx, c.dy - r)
      ..arcTo(
        Rect.fromCircle(center: c, radius: r),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
      )
      ..close();
  }

  @override
  bool shouldReclip(_SweepClipper old) => old.progress != progress;
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
    strokes(canvas, _pathFor(mode), progress.clamp(0.0, 1.0), color);
    canvas.restore();
  }

  /// Three passes over [path] up to [t]. A soft wide stroke underneath is
  /// what makes a line on a dark ground read as lit rather than printed; the
  /// crisp stroke is the line itself; and while the pen is still moving, a
  /// bright dot sits at its tip, so the eye follows the drawing rather than
  /// watching a shape fill in.
  ///
  /// Widths are in glyph-box units; [scale] converts them when the path is
  /// already in pixels.
  static void strokes(
    Canvas canvas,
    Path path,
    double t,
    Color color, {
    double scale = 1,
  }) {
    final drawn = _trim(path, t);
    canvas.drawPath(
      drawn,
      Paint()
        ..color = color.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5.5 * scale
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2.2 * scale),
    );
    canvas.drawPath(
      drawn,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0 * scale
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    if (t > 0 && t < 1) {
      final tip = _tipOf(path, t);
      if (tip != null) {
        canvas.drawCircle(
          tip,
          1.9 * scale,
          Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.95),
        );
      }
    }
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

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.progress != progress || old.color != color || old.mode != mode;
}
