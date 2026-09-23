import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:soplay/core/brand/sozo_mark_geometry.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/widgets/sozo_mark.dart';

/// The splash: the logo drawn by hand, then painted in, then left alone.
///
/// ## What the logo is
///
/// Not a red S. The Sozo logo is an S cut from a relief — a dragon in
/// orange-red on a peach ground, claws and toes and flame reaching into it,
/// with a small "Sozo" in the top arm. A splash that fills the outline with
/// one colour draws the one part of the logo that is not the logo.
///
/// ## What it does
///
/// It draws it. On black, a single pen in the logo's own light traces the
/// letter's edge — down both sides at once from the top terminal to the
/// bottom — and, a moment behind it, the dragon: every edge where the dragon
/// meets the ground, in the order the letter is written, each at the speed a
/// hand would draw it. Then the drawing is painted in: the artwork comes up
/// under the lines, the lines go, and what is left is the logo, still, for
/// most of the time the splash is on screen.
///
/// ## What it does not do
///
/// Move the logo. It is drawn at one size in one place from the first frame
/// to the last. Versions before this pushed the camera in on the dragon until
/// the letter filled the screen, lifted the dragon off the letter with a
/// shadow, bent it through a mesh, stamped the landing with a flash, trailed
/// sparks, flame and embers — and every one of those made a splash about the
/// effect instead of about the mark. Here the only thing that changes is how
/// much of the logo has been drawn.
///
/// ## Colour
///
/// The artwork's own, never the accent the user picked. The accent is
/// theirs; the logo is the brand.
class SozoSplash extends StatefulWidget {
  const SozoSplash({super.key, required this.onSettled, required this.onDone});

  /// The letter is complete and the rest is the hold. The route resolves from
  /// here rather than at the end, so the work overlaps the last second instead
  /// of starting after it.
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
    duration: const Duration(milliseconds: _Beats.total),
  );

  bool _settled = false;
  SozoMarkGeometry? _geometry;

  // TEMPORARY review loop — replays forever so the animation can be judged.
  // Must be false in any commit.
  static const bool _reviewLoop = false;

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
    _play();
  }

  void _play() {
    _c.forward(from: 0).then((_) async {
      if (!mounted) return;
      if (_reviewLoop) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        if (mounted) _play();
        return;
      }
      widget.onDone();
    });
  }

  /// The letter completing, reported once.
  ///
  /// From the listener rather than a timer: a controller that is behind —
  /// which on a cold start it will be — should hand over when the animation
  /// actually gets there, not when a clock says it should have.
  void _watch() {
    if (_settled || _c.value * _Beats.total < _Beats.paintTo) return;
    _settled = true;
    widget.onSettled();
  }

  @override
  void dispose() {
    _c.removeListener(_watch);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final geometry = _geometry;
    // Under half the narrow side: a mark, not a poster. The pen has to be
    // seen drawing the dragon's claws, and at this size it is; much larger and
    // the logo stops being a logo on a screen and becomes the screen.
    final size = math.min(
      MediaQuery.sizeOf(context).shortestSide * 0.46,
      220.0,
    );

    if (geometry == null) {
      return _Stage(
        child: SozoMark(size: size, color: _LogoPainter._deep),
      );
    }

    // Reduce motion gets the logo, not the performance: the finished relief,
    // faded in. An image that blinks into existence reads as a glitch, and
    // that much motion nobody asked to be spared.
    if (MediaQuery.disableAnimationsOf(context)) {
      return _Stage(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 260),
          builder: (context, t, _) => Opacity(
            opacity: t,
            child: CustomPaint(
              size: Size.square(size),
              painter: _LogoPainter(
                geometry: geometry,
                art: SozoMarkGeometry.art,
                background: AppColors.background,
                clock: () => _Beats.holdFrom.toDouble(),
                still: true,
              ),
            ),
          ),
        ),
      );
    }

    return _Stage(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.square(size),
          painter: _LogoPainter(
            repaint: _c,
            geometry: geometry,
            art: SozoMarkGeometry.art,
            background: AppColors.background,
            clock: () => _c.value * _Beats.total,
          ),
        ),
      ),
    );
  }
}

/// Every beat, in milliseconds from the first frame.
///
/// Two and a half seconds, most of it the finished logo.
/// Measured on a device,
/// a debug build paints at about 30fps and the first frames of a cold start are
/// lost to jank, so no stroke here is shorter than about a dozen frames.
abstract final class _Beats {
  /// Black before it, so the first thing seen is the pen starting rather than
  /// a drawing that was already there.
  static const int drawFrom = 150;

  /// The letter's edge, both sides at once, top terminal to bottom.
  static const int drawTo = 950;

  /// How far behind the letter's edge the dragon's lines follow: each starts
  /// this long after the edge has passed its place on the letter.
  static const int dragonLag = 70;

  /// Pen speed for the dragon's lines, in units of the 512 box per
  /// millisecond, and the shortest and longest a line may take — so a claw is
  /// not a flicker and a long contour is finished with the letter rather
  /// than still being drawn when the paint arrives.
  static const double pen = 0.7;
  static const int strokeMin = 160;
  static const int strokeMax = 420;

  /// The drawing painted in: the artwork comes up under the lines, and the
  /// lines go as it arrives, so the last thing seen is the logo alone.
  ///
  /// Quick, and front-loaded. A saturated painting faded up slowly from black
  /// spends its middle as a dark, muddy version of itself; up fast, that
  /// middle is a few frames and what is seen is the colour arriving.
  static const int paintFrom = 1080;
  static const int paintTo = 1400;
  static const int inkOutFrom = 1180;
  static const int inkOutTo = 1460;

  /// From here to the fade nothing changes at all.
  static const int holdFrom = inkOutTo;

  static const int fadeFrom = 2260;
  static const int total = 2500;
}

/// The black field the logo sits on. Separated so both branches share it and
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

class _LogoPainter extends CustomPainter {
  _LogoPainter({
    super.repaint,
    required this.geometry,
    required this.art,
    required this.background,
    required this.clock,
    this.still = false,
  }) {
    final image = art;
    if (image != null) {
      // The artwork is registered to the same 512 box as the paths, at 1024,
      // so one scale maps it on. Built once: a shader per frame is an
      // allocation per frame for something that never changes.
      _artPaint.shader = ui.ImageShader(
        image,
        TileMode.clamp,
        TileMode.clamp,
        Matrix4.diagonal3Values(
          512 / image.width,
          512 / image.height,
          1,
        ).storage,
        filterQuality: FilterQuality.medium,
      );
    }
  }

  final SozoMarkGeometry geometry;
  final ui.Image? art;
  final Color background;
  final double Function() clock;

  /// The finished logo, with nothing moving. For reduce motion.
  final bool still;

  /// The dragon's orange, sampled from the artwork: the paint where the
  /// artwork did not load.
  static const Color _deep = Color(0xFFF93D0D);

  /// The pen's colour: the artwork's peach ground, a shade lighter — the
  /// drawing is in the logo's own light, not a white laid over it.
  static const Color _inkColour = Color(0xFFFBE2D2);

  /// The pen's width on screen, in logical pixels, whatever size the logo is
  /// drawn at. Thin enough to read as drawing, thick enough to survive the
  /// dim of a phone at night.
  static const double _inkWidth = 1.3;

  final Paint _artPaint = Paint()
    ..style = PaintingStyle.fill
    ..isAntiAlias = true
    ..color = _deep;
  final Paint _ink = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;
  final Paint _fade = Paint();

  static double _span(
    double ms,
    int from,
    int to, [
    Curve curve = Curves.linear,
  ]) => curve.transform(((ms - from) / (to - from)).clamp(0.0, 1.0));

  @override
  void paint(Canvas canvas, Size size) {
    final ms = still ? _Beats.holdFrom.toDouble() : clock();
    final leaving = _span(ms, _Beats.fadeFrom, _Beats.total, Curves.easeIn);
    final dim = 1 - leaving;
    if (dim <= 0.001) return;

    final scale = size.width / 512;
    final bounds = geometry.bounds;
    canvas.save();
    // The logo stays where it is and the size it is, the whole time: nothing
    // here is a camera. What changes is only how much of it is drawn.
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    canvas.translate(-bounds.center.dx, -bounds.center.dy);

    final painted = _span(
      ms,
      _Beats.paintFrom,
      _Beats.paintTo,
      Curves.easeOutCubic,
    );
    if (painted > 0) {
      // Faded in by the paint's own opacity, not a layer: an opacity layer is
      // an offscreen pass for every frame of the fade, and this is one fill.
      _artPaint.color = art == null
          ? _deep.withValues(alpha: painted)
          : Color.fromRGBO(0, 0, 0, painted);
      canvas.drawPath(geometry.body, _artPaint);
    }

    final ink =
        1 - _span(ms, _Beats.inkOutFrom, _Beats.inkOutTo, Curves.easeInOut);
    if (!still && ink > 0) {
      _ink
        ..strokeWidth = _inkWidth / scale
        ..color = _inkColour.withValues(alpha: ink);
      _drawEdge(canvas, ms);
      _drawDragon(canvas, ms);
    }
    canvas.restore();

    // The fade, as the background drawn over the logo rather than an Opacity
    // around it: an opacity layer is an offscreen pass for every frame of the
    // fade, and this is one rectangle.
    if (dim < 1) {
      _fade.color = background.withValues(alpha: 1 - dim);
      canvas.drawRect(
        Rect.fromLTWH(
          -size.width,
          -size.height,
          size.width * 3,
          size.height * 3,
        ),
        _fade,
      );
    }
  }

  /// The letter's edge, drawn from the middle of the top terminal down both
  /// sides at once, meeting at the bottom one — the way a letter's outline is
  /// drawn by hand, and so the whole S is on its way from the first frame
  /// rather than one side of it arriving after the other.
  void _drawEdge(Canvas canvas, double ms) {
    final p = _span(ms, _Beats.drawFrom, _Beats.drawTo, _edgeCurve);
    if (p <= 0) return;
    final edge = geometry.edge;
    final length = edge.length;
    final top = geometry.edgeTop;
    // The two sides, measured from the top terminal round to the bottom one.
    final forward = (geometry.edgeBottom - top) % length;
    final back = length - forward;
    _arc(canvas, edge, top, top + forward * p);
    _arc(canvas, edge, top - back * p, top);
  }

  /// The dragon's lines, each starting as the letter's edge passes it and
  /// drawn at the pen's own speed, so the long contours take longer than the
  /// claws the way they would by hand.
  void _drawDragon(Canvas canvas, double ms) {
    for (final stroke in geometry.strokes) {
      final length = stroke.metric.length;
      // When the edge reaches this line's place: the inverse of the edge's
      // own easing, or a line would appear ahead of the pen drawing the letter
      // around it.
      final from =
          _Beats.drawFrom +
          _edgeCurveInverse(stroke.along) * (_Beats.drawTo - _Beats.drawFrom) +
          _Beats.dragonLag;
      final takes = (length / _Beats.pen).clamp(
        _Beats.strokeMin.toDouble(),
        _Beats.strokeMax.toDouble(),
      );
      final p = Curves.easeInOutSine.transform(
        ((ms - from) / takes).clamp(0.0, 1.0),
      );
      if (p <= 0) continue;
      canvas.drawPath(stroke.metric.extractPath(0, length * p), _ink);
    }
  }

  static const Curve _edgeCurve = Curves.easeInOutCubic;

  /// The time, as a fraction, at which [_edgeCurve] reaches [value].
  static double _edgeCurveInverse(double value) {
    var lo = 0.0;
    var hi = 1.0;
    for (var i = 0; i < 20; i++) {
      final mid = (lo + hi) / 2;
      if (_edgeCurve.transform(mid) < value) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return (lo + hi) / 2;
  }

  /// [from]..[to] along the closed [edge], across its start if it has to.
  void _arc(Canvas canvas, ui.PathMetric edge, double from, double to) {
    final length = edge.length;
    var a = from % length;
    var b = a + (to - from);
    if (b <= length) {
      canvas.drawPath(edge.extractPath(a, b), _ink);
      return;
    }
    canvas.drawPath(edge.extractPath(a, length), _ink);
    canvas.drawPath(edge.extractPath(0, b - length), _ink);
  }

  @override
  bool shouldRepaint(_LogoPainter old) => still != old.still;
}
