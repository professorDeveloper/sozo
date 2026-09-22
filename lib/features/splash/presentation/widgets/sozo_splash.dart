import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:soplay/core/brand/sozo_mark_geometry.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/widgets/sozo_mark.dart';

/// The splash: the mark written, filled, and then left stirring.
///
/// ## What was here
///
/// The letters "S" and "OZO" as `Text`, the S scaled up and the rest revealed
/// by an `Align(widthFactor:)` wipe, over 4.3 seconds. Three things wrong with
/// that, in order of how much they cost: the wordmark rendered in whatever
/// font the handset shipped, so the app's first impression was Roboto on one
/// device and Samsung One on the next; a `widthFactor` animation re-lays-out
/// every frame; and it was a logo *appearing*, which is the one thing a brand
/// animation must not be.
///
/// ## Why it needed a new asset
///
/// The shipped mark is a single closed contour traced from the app icon, and
/// that is why every attempt to animate it came out as a neon tube lighting
/// up. There is nothing inside a silhouette. A pen given only an outline can
/// ring the letter; it cannot write it, because writing means travelling the
/// stroke rather than its edge.
///
/// `sozo_mark_animated.svg` carries the same silhouette plus its own
/// centreline, derived from the outline rather than drawn by eye. Everything
/// below follows from having it.
///
/// ## The one geometric fact the fill is built on
///
/// **The ribbon is the spine dilated by half its width.** So the fill is not a
/// gradient sweeping over the shape and it is not a radius guessed as a
/// fraction of the viewBox — it is the same stroke the pen wrote, drawn wider,
/// clipped to the silhouette. It cannot leave a hole in the middle and it
/// cannot finish early at the terminals, because at full width the stroke IS
/// the letter. The previous attempts at this beat produced a black hole at the
/// waist for precisely the reason this avoids: they guessed the radius.
///
/// ## And why it keeps moving
///
/// The outline samples are pushed along their own normals by a wave that
/// travels the contour, and the phase never stops advancing. That is what
/// makes it a body rather than a picture: after the letter has landed it is
/// still breathing, and a highlight is still running the stroke. It also
/// survives a dropped frame, because it is a continuous phase rather than a
/// one-shot with a schedule.
class SozoSplash extends StatefulWidget {
  const SozoSplash({super.key, required this.onSettled, required this.onDone});

  /// The letter has landed and the rest is decoration. The route resolves from
  /// here rather than at the end, so the work overlaps the last 800ms instead
  /// of starting after them.
  final VoidCallback onSettled;

  /// The animation is over and the screen may be replaced.
  final VoidCallback onDone;

  @override
  State<SozoSplash> createState() => _SozoSplashState();
}

class _SozoSplashState extends State<SozoSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _total),
  );

  /// Every beat, in milliseconds from the first frame.
  ///
  /// The write used to take 780ms and nobody saw it. Measured on the device
  /// rather than guessed at: a debug build on an emulator paints this at about
  /// 30fps, so 780ms of writing is two dozen frames — and the first few of
  /// those are lost to the jank every Flutter cold start has. What was left
  /// was a letter that appeared to be there already.
  ///
  /// It is a second now, and the dead stretch after the landing is gone: the
  /// mark used to sit unchanged from 1320ms to 1900ms, which is the part
  /// everybody DID see, and seeing only that is what makes an animation read
  /// as a static logo.
  static const int _writeFrom = 100;
  static const int _writeTo = 1180;
  static const int _fillFrom = 980;
  static const int _fillTo = 1520;
  static const int _landFrom = 1480;
  static const int _landTo = 1700;
  static const int _fadeFrom = 2120;
  static const int _total = 2380;

  bool _settled = false;
  SozoMarkGeometry? _geometry;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        // Not a constant: the background is a runtime choice now, like the
        // accent, so a const style here would paint the AMOLED theme's nav bar
        // the default theme's grey.
        systemNavigationBarColor: AppColors.background,
      ),
    );
    _geometry = SozoMarkGeometry.value;
    if (_geometry == null) {
      SozoMarkGeometry.precache().then((_) {
        if (mounted) setState(() => _geometry = SozoMarkGeometry.value);
      });
    }
    _c.addListener(_watch);
    _c.forward().then((_) {
      if (mounted) widget.onDone();
    });
  }

  /// The landing, reported once.
  ///
  /// From the listener rather than from a timer: a controller that is behind —
  /// which on a cold start it will be — should hand over when the animation
  /// actually gets there, not when a clock says it should have.
  void _watch() {
    if (_settled || _c.value * _total < _landTo) return;
    _settled = true;
    widget.onSettled();
  }

  @override
  void dispose() {
    _c.removeListener(_watch);
    _c.dispose();
    super.dispose();
  }

  static double _span(
    double ms,
    int from,
    int to, {
    Curve curve = Curves.linear,
  }) {
    final t = ((ms - from) / (to - from)).clamp(0.0, 1.0);
    return curve.transform(t);
  }

  @override
  Widget build(BuildContext context) {
    final geometry = _geometry;
    final size = math.min(
      MediaQuery.sizeOf(context).shortestSide * 0.42,
      210.0,
    );

    // Reduce motion gets the mark, not the performance. Still a fade rather
    // than a cut, because an image that blinks into existence reads as a
    // glitch — that much is motion nobody asked to be spared.
    if (MediaQuery.disableAnimationsOf(context) || geometry == null) {
      return _Stage(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 260),
          builder: (context, t, _) => Opacity(
            opacity: t,
            child: SozoMark(size: size, color: AppColors.primary),
          ),
        ),
      );
    }

    return _Stage(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.square(size),
          painter: _MarkPainter(
            repaint: _c,
            geometry: geometry,
            accent: AppColors.primary,
            highlight: AppColors.primaryLight,
            read: () {
              final ms = _c.value * _total;
              return _Beat(
                write: _span(ms, _writeFrom, _writeTo, curve: _writeCurve),
                fill: _span(
                  ms,
                  _fillFrom,
                  _fillTo,
                  curve: Curves.easeInOutCubic,
                ),
                land: _span(ms, _landFrom, _landTo, curve: Curves.easeOutBack),
                // Time, not progress: the stir is a clock, so that it is still
                // running when everything scheduled has finished.
                phase: ms / 1000,
                // Loudest while the letter is being written, then down to the
                // idle breath it keeps forever.
                stir: ui.lerpDouble(
                  7.0,
                  3.0,
                  _span(ms, _writeTo - 200, _landTo),
                )!,
                glint: _span(ms, _landFrom + 60, _fadeFrom - 220),
                dim: 1 - _span(ms, _fadeFrom, _total, curve: Curves.easeIn),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Leaves from rest and arrives without a stall.
  ///
  /// Not the house emphasized-decelerate: stretched over 780ms that curve is
  /// four-fifths done by 380ms, and the rest of the write reads as the pen
  /// running out of ink.
  static const Curve _writeCurve = Cubic(0.30, 0.02, 0.18, 1.0);
}

/// The black field the mark sits on. Separated so both branches share it and
/// neither can drift from the window's own background colour.
class _Stage extends StatelessWidget {
  const _Stage({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    body: Center(child: child),
  );
}

/// Where every beat stands, this frame.
class _Beat {
  const _Beat({
    required this.write,
    required this.fill,
    required this.land,
    required this.phase,
    required this.stir,
    required this.glint,
    required this.dim,
  });

  final double write;
  final double fill;
  final double land;
  final double phase;
  final double stir;
  final double glint;
  final double dim;
}

class _MarkPainter extends CustomPainter {
  _MarkPainter({
    required Listenable repaint,
    required this.geometry,
    required this.accent,
    required this.highlight,
    required this.read,
  }) : super(repaint: repaint);

  final SozoMarkGeometry geometry;
  final Color accent;
  final Color highlight;
  final _Beat Function() read;

  /// Rebuilt every frame and reused every frame. `reset` keeps the buffers the
  /// path has already grown, so a deforming silhouette costs arithmetic rather
  /// than an allocation sixty times a second.
  final ui.Path _stirred = ui.Path();

  final Paint _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;
  final Paint _fill = Paint()..isAntiAlias = true;

  /// Half the ribbon's width, measured off the asset: the stroke that is
  /// exactly the letter. Past this the stroke would spill, which is what the
  /// clip is for.
  static const double _halfRibbon = 30.5;

  /// How far around the contour one wave runs, and how fast it travels.
  static const double _waves = 3.0;
  static const double _hz = 0.42;

  @override
  void paint(Canvas canvas, Size size) {
    final b = read();
    if (b.dim <= 0.001) return;

    final scale = size.width / 512;
    canvas.save();
    // The mark does not fill its own viewBox, so it is centred on its bounds
    // rather than on the box. Centring on the box leaves it visibly high and
    // left, which on a splash is the one frame everybody sees.
    final bounds = geometry.bounds;
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale * (0.94 + 0.06 * b.land));
    canvas.translate(-bounds.center.dx, -bounds.center.dy);

    _buildStirred(b);

    canvas.save();
    canvas.clipPath(_stirred);

    // The letter, as far as the pen has written it. The ribbon IS this stroke
    // at half-ribbon width, so widening it past that fills the silhouette
    // exactly — corners, terminals and all — with nowhere for a hole to be.
    final written = geometry.spineMetric.extractPath(
      0,
      geometry.spineLength * b.write,
    );
    // Written in light and settling into the accent as the fill takes over.
    // A thin line in the fill colour on a black field is the one thing on this
    // screen nobody can see: it has the least contrast at the moment it is the
    // only thing moving.
    _stroke
      ..color = Color.lerp(highlight, accent, b.fill)!.withValues(alpha: b.dim)
      ..strokeWidth = ui.lerpDouble(13.0, _halfRibbon * 2.6, b.fill)!;
    canvas.drawPath(written, _stroke);

    // The pen's own light, at its tip, while it is still moving.
    if (b.write < 1) {
      final tip = geometry.spineMetric.getTangentForOffset(
        geometry.spineLength * b.write,
      );
      if (tip != null) {
        // A halo and a core. One flat dot at the tip reads as a bullet point
        // travelling a line; the halo is what makes it a pen putting something
        // down.
        _fill.color = highlight.withValues(alpha: 0.22 * b.dim);
        canvas.drawCircle(tip.position, 22, _fill);
        _fill.color = Colors.white.withValues(alpha: 0.92 * b.dim);
        canvas.drawCircle(tip.position, 8, _fill);
      }
    }

    // The highlight that runs the stroke after it has landed. This is the
    // detail that is still moving when everything else has stopped.
    if (b.glint > 0 && b.glint < 1) {
      final head = geometry.spineLength * b.glint;
      final tail = math.max(0.0, head - geometry.spineLength * 0.26);
      // Bright enough to read against a filled letter in the accent colour.
      // At a third of that it was a highlight nobody saw, which is the same as
      // not having one.
      _stroke
        ..color = highlight.withValues(
          alpha: 0.62 * b.dim * math.sin(b.glint * math.pi),
        )
        ..strokeWidth = _halfRibbon * 1.1;
      canvas.drawPath(geometry.spineMetric.extractPath(tail, head), _stroke);
    }
    canvas.restore();
    canvas.restore();
  }

  /// The silhouette with a wave travelling its outline.
  ///
  /// Each sample is pushed along its own outward normal, so the shape thickens
  /// and thins rather than sliding — a body flexing, not a picture wobbling.
  /// The amplitude is small on purpose: at more than about eight units the
  /// two legs of the top terminal's corner close on each other and the corner
  /// folds into a spike.
  void _buildStirred(_Beat b) {
    _stirred.reset();
    final n = SozoMarkGeometry.outlineSamples;
    final travel = b.phase * _hz * 2 * math.pi;
    for (var i = 0; i < n; i++) {
      final u = i / n;
      final push = math.sin(u * _waves * 2 * math.pi - travel) * b.stir;
      final x = geometry.outlineX[i] + geometry.normalX[i] * push;
      final y = geometry.outlineY[i] + geometry.normalY[i] * push;
      if (i == 0) {
        _stirred.moveTo(x, y);
      } else {
        _stirred.lineTo(x, y);
      }
    }
    _stirred.close();
  }

  @override
  bool shouldRepaint(_MarkPainter old) => false;
}
