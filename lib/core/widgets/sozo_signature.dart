import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_parsing/path_parsing.dart';

import 'package:soplay/core/content/catalogue.dart';
import 'package:soplay/core/content/content_mode.dart';
import 'package:soplay/core/content/content_mode_style.dart';
import 'package:soplay/core/widgets/sozo_mark.dart';

/// The Sozo mark, signed.
///
/// The centre of the mode switch was a glyph — a play sign, a page, a book —
/// standing in for the app. This is the app: its own mark, written by the
/// pen in the mode's colour, then filled, with the mode where it belongs —
/// a small badge on the mark's corner, drawn after it. It reads as "Sozo,
/// now in Manga" rather than as a symbol of something.
///
/// [progress] runs 0 → 1: the outline is written over the first three
/// quarters, the fill rises through the last quarter, and the badge draws
/// itself as the fill lands.
class SozoSignature extends StatefulWidget {
  const SozoSignature({
    super.key,
    required this.mode,
    required this.color,
    this.catalogue,
    this.size = 96,
    this.progress = 1,
  });

  final ContentMode mode;
  final Color color;
  final Catalogue? catalogue;
  final double size;
  final double progress;

  /// Read and measure the mark before anything needs to draw it. See
  /// [_SozoSignatureState.precache] for why this exists.
  static Future<void> precache() => _SozoSignatureState.precache();

  @override
  State<SozoSignature> createState() => _SozoSignatureState();
}

class _SozoSignatureState extends State<SozoSignature> {
  static ui.Path? _mark;

  /// The mark measured. Measuring is the expensive half of trimming a path to
  /// a pen position, and this path is parsed once and never mutated, so the
  /// answer is the same on every frame of every switch for the life of the
  /// process. Held beside the path it describes, so the two cannot drift.
  static List<ui.PathMetric>? _marked;
  static Future<void>? _loading;

  /// Read the mark before anything needs to draw it.
  ///
  /// The parse is a bundle read and an SVG path walk — fast, but asynchronous,
  /// and the switch that needs it starts drawing on the next frame. Without
  /// this the FIRST switch of every process falls back to a flat mark fading
  /// in, which is precisely the "an icon just appeared" the signature exists
  /// to replace; every switch after it is signed. One cold start behaving
  /// differently from the rest is the kind of thing that is reported as
  /// "sometimes it doesn't animate".
  ///
  /// Safe to call repeatedly: the work happens once.
  static Future<void> precache() => _loading ??= _read();

  static Future<void> _read() async {
    try {
      final svg = await rootBundle.loadString(SozoMark.asset);
      final m = RegExp(r'\sd="([^"]+)"').firstMatch(svg);
      if (m == null) return;
      final proxy = _PathProxy();
      writeSvgPathDataToPath(m.group(1)!, proxy);
      proxy.path.fillType = ui.PathFillType.evenOdd;
      _marked = proxy.path.computeMetrics().toList();
      _mark = proxy.path;
    } catch (_) {
      // A mark that will not parse is not worth failing a mode switch over —
      // the widget renders the asset itself instead, which is the same shape
      // without the pen. Left null so a later attempt can still succeed.
      _loading = null;
    }
  }

  @override
  void initState() {
    super.initState();
    if (_mark == null) {
      precache().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final path = _mark;
    final t = widget.progress.clamp(0.0, 1.0);
    // Large enough that a catalogue's own mark is recognisable inside it. The
    // badge is the only thing on the cover that says which of AniList's three
    // shelves you asked for, and an unreadable logo says nothing.
    final badge = widget.size * 0.42;
    final c = widget.catalogue;
    return SizedBox.square(
      dimension: widget.size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          if (path == null)
            // Before the path is read (the first switch of a cold start):
            // the mark as it is, fading in, rather than nothing.
            Opacity(
              opacity: t,
              child: SozoMark(size: widget.size, color: widget.color),
            )
          else
            CustomPaint(
              size: Size.square(widget.size),
              painter: _SignaturePainter(
                path: path,
                metrics: _marked,
                color: widget.color,
                t: t,
              ),
            ),
          // The badge: a dark disc on the corner, the mode's own glyph or
          // the catalogue's mark inside it, drawn once the fill has landed.
          Positioned(
            right: -badge * 0.18,
            bottom: -badge * 0.12,
            child: Opacity(
              opacity: ((t - 0.72) / 0.14).clamp(0.0, 1.0),
              child: Container(
                width: badge,
                height: badge,
                decoration: BoxDecoration(
                  color: const Color(0xFF141414),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: widget.color.withValues(alpha: 0.55),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.35),
                      blurRadius: 12,
                    ),
                  ],
                ),
                alignment: Alignment.center,
                // A catalogue keeps the drawn beat the mode glyphs have: the
                // pen rounds the disc and the mark is wiped in behind it, so
                // the badge is made rather than pasted on.
                child: ModeGlyph(
                  mode: widget.mode,
                  catalogue: c,
                  color: widget.color,
                  size: badge * (c != null ? 0.94 : 0.62),
                  progress: ((t - 0.74) / 0.26).clamp(0.0, 1.0),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  const _SignaturePainter({
    required this.path,
    required this.metrics,
    required this.color,
    required this.t,
  });

  final ui.Path path;
  final List<ui.PathMetric>? metrics;
  final Color color;
  final double t;

  /// The SVG is drawn in a 512 box.
  static const double _box = 512;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0) return;
    final scale = size.width / _box;
    canvas.save();
    canvas.scale(scale);
    // The outline is written over the first three quarters; the fill
    // rises through the last, so the mark goes from a line to a thing.
    final pen = (t / 0.76).clamp(0.0, 1.0);
    final fill = ((t - 0.66) / 0.34).clamp(0.0, 1.0);
    if (fill > 0) _fill(canvas, fill);
    paintPenStrokes(
      canvas,
      path,
      pen,
      color,
      // Pen widths are in glyph-box units (a 24 box); the mark is a 512 box,
      // so the same visual weight needs them scaled up by the ratio.
      scale: _box / 24 / 4,
      metrics: metrics,
    );
    canvas.restore();
  }

  /// The fill, arriving as light across the mark rather than as opacity.
  ///
  /// A flat alpha ramp is the mark getting less transparent, which is what a
  /// loading image does. A band of light travelling across it while the alpha
  /// rises is the mark being *inked*, and it costs one shader on the frames
  /// where the band is actually on screen.
  void _fill(Canvas canvas, double fill) {
    final paint = Paint();
    if (fill >= 1) {
      paint.color = color.withValues(alpha: 0.92);
    } else {
      // The band runs ahead of the alpha, from the top-left corner the pen
      // started in to the opposite one, and leaves the mark solid behind it.
      final head = (fill * 1.6) - 0.3;
      paint.shader = ui.Gradient.linear(
        Offset.zero,
        const Offset(_box, _box),
        [
          color.withValues(alpha: 0.92 * fill),
          color.withValues(alpha: 0.92),
          color.withValues(alpha: 0.30 * fill),
        ],
        [
          (head - 0.22).clamp(0.0, 1.0),
          head.clamp(0.0, 1.0),
          (head + 0.26).clamp(0.0, 1.0),
        ],
      );
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SignaturePainter old) =>
      old.t != t || old.color != color || old.path != path;
}

/// Feeds the SVG path commands into a [ui.Path].
class _PathProxy extends PathProxy {
  final ui.Path path = ui.Path();

  @override
  void close() => path.close();

  @override
  void cubicTo(
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
  ) => path.cubicTo(x1, y1, x2, y2, x3, y3);

  @override
  void lineTo(double x, double y) => path.lineTo(x, y);

  @override
  void moveTo(double x, double y) => path.moveTo(x, y);
}
