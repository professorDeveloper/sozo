import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:soplay/core/brand/sozo_mark_geometry.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/widgets/sozo_mark.dart';

/// The splash: the logo drawn by hand, painted in, and sealed by the dragon
/// planting its foot.
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
/// under the lines and the lines go.
///
/// Then the dragon moves, once. The raised three-toed foot in the right-hand
/// bend lifts off the letter's wall, holds, and comes down hard — past where
/// it was, and back — the way a seal is pressed. One gesture, inside the
/// logo, by the logo's own dragon; after it the logo is still until it goes.
///
/// ## What it does not do
///
/// Move the logo. It is drawn at one size in one place from the first frame
/// to the last. Versions before this pushed the camera in on the dragon until
/// the letter filled the screen, lifted the dragon off the letter with a
/// shadow, bent it through a mesh, stamped the landing with a flash, trailed
/// sparks, flame and embers, sent a line circling the letter — and every one
/// of those made a splash about the effect instead of about the mark. The
/// foot is none of those: a rigid piece of the painting turning on its own
/// ankle, over the ground the painting would have had under it. Nothing is
/// added to the logo and nothing in it bends.
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
            foot: SozoMarkGeometry.foot,
            footGround: SozoMarkGeometry.footGround,
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
/// Three seconds: the drawing, the paint, the foot, and a still logo either
/// side of the foot so it is seen to be the logo that moved. Measured on a
/// device, a debug build paints at about 30fps and the first frames of a cold
/// start are lost to jank, so no stroke here is shorter than about a dozen
/// frames — the strike alone is shorter, on purpose: it is a blow.
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

  /// The finished logo, before and after the foot. From here to the fade
  /// nothing changes but the foot.
  static const int holdFrom = inkOutTo;

  /// First the weight comes onto the foot: it presses down a couple of
  /// degrees, so the lift that follows reads as effort gathered rather than
  /// as something switched on. A beat after the paint, so the logo is seen
  /// whole and still before any of it moves.
  static const int pressFrom = 1560;

  /// Then up: slowly, and slowest at either end, the way a weight is lifted.
  static const int liftFrom = 1640;
  static const int liftTo = 2000;

  /// Held at the top — still rising, a hair — for the beat before a blow.
  static const int strikeFrom = 2120;

  /// Down, accelerating all the way. Long enough for nine frames at 60Hz and
  /// four or five at 30: any quicker and it is not a blow but a jump.
  static const int strikeTo = 2270;

  /// Through rest and back, and still. Exactly one and a half of the landing's
  /// swings, which is where it crosses rest for the last time: it stops on
  /// rest rather than being snapped to it.
  static const int settleTo = strikeTo + 3 * _landingSwing ~/ 2;
  static const int _landingSwing = 220;

  /// Long enough after the foot is down for the logo to be seen still again —
  /// sealed, not interrupted — and no longer: the payoff lands, then leaves.
  static const int fadeFrom = settleTo + 180;
  static const int total = fadeFrom + 240;
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
    this.foot,
    this.footGround,
    required this.background,
    required this.clock,
    this.still = false,
  }) {
    // Built once: a shader per frame is an allocation per frame for something
    // that never changes.
    _artPaint.shader = _registered(art);
    _groundPaint.shader = _registered(footGround);
  }

  /// [image] through the 512 box. The artwork and its footless ground are
  /// both registered to the same box as the paths, at 1024, so one scale maps
  /// either on.
  static ui.ImageShader? _registered(ui.Image? image) => image == null
      ? null
      : ui.ImageShader(
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

  final SozoMarkGeometry geometry;
  final ui.Image? art;

  /// The foot and what is under it; see [SozoMarkGeometry.foot]. Without both
  /// the foot does not move.
  final ui.Image? foot;
  final ui.Image? footGround;

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

  /// How far the foot lifts, and how far past rest it lands, in radians.
  /// Clockwise is up: the toes swing along the wall of the bend and away from
  /// the top of the letter, which is the way they stay inside it.
  static const double _lift = 14.5 * math.pi / 180;
  static const double _creep = 1.5 * math.pi / 180;
  static const double _landing = 3.8 * math.pi / 180;

  /// How far the weight presses the foot down before it lifts.
  static const double _press = -2 * math.pi / 180;

  /// How quickly the landing's swing dies, in milliseconds: by the second
  /// time it passes rest it is a fraction of a degree.
  static const double _landingDecay = 90;

  final Paint _artPaint = Paint()
    ..style = PaintingStyle.fill
    ..isAntiAlias = true
    ..color = _deep;
  final Paint _groundPaint = Paint()
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;
  final Paint _footPaint = Paint()
    ..filterQuality = FilterQuality.medium
    ..blendMode = BlendMode.srcATop;
  final Paint _layer = Paint();
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
      final turn = still ? 0.0 : _footTurn(ms);
      // Only while it is off rest does the foot come apart from the logo. At
      // rest the frame is the artwork itself, not a reassembly of it.
      final lifting =
          turn != 0 && art != null && foot != null && footGround != null;
      // Faded in by the paint's own opacity, not a layer: an opacity layer is
      // an offscreen pass for every frame of the fade, and this is one fill.
      _artPaint.color = art == null
          ? _deep.withValues(alpha: painted)
          : Color.fromRGBO(0, 0, 0, painted);
      if (lifting) {
        _groundPaint.color = Color.fromRGBO(0, 0, 0, painted);
        _drawLifted(canvas, turn);
      } else {
        canvas.drawPath(geometry.body, _artPaint);
      }
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

  /// How far the foot is turned off rest at [ms], in radians, clockwise.
  ///
  /// A stamp in three parts, after a press of the weight onto the foot. The
  /// lift is the anticipation: slow, eased at
  /// both ends, and held at the top while still creeping up, because a
  /// weight that stops dead at the top of its swing reads as a pause and one
  /// that is still gathering reads as about to fall. The strike accelerates
  /// all the way down and loses most of its speed the instant it reaches rest
  /// — that sudden loss is the impact; nothing is flashed to say so. And the
  /// landing carries it on past rest and back, a swing that dies within two
  /// crossings, which is the difference between a foot planted and a
  /// picture of a foot put back.
  static double _footTurn(double ms) {
    if (ms <= _Beats.pressFrom || ms >= _Beats.settleTo) return 0;
    if (ms < _Beats.liftFrom) {
      return _press *
          _span(ms, _Beats.pressFrom, _Beats.liftFrom, Curves.easeOut);
    }
    if (ms < _Beats.liftTo) {
      return _press +
          (_lift - _press) *
              _span(ms, _Beats.liftFrom, _Beats.liftTo, Curves.easeInOutCubic);
    }
    final top =
        _lift +
        _creep * _span(ms, _Beats.liftTo, _Beats.strikeFrom, Curves.easeOut);
    if (ms < _Beats.strikeFrom) return top;
    if (ms < _Beats.strikeTo) {
      return top *
          (1 -
              _span(
                ms,
                _Beats.strikeFrom,
                _Beats.strikeTo,
                Curves.easeInCubic,
              ));
    }
    final t = ms - _Beats.strikeTo;
    return -_landing *
        math.sin(2 * math.pi * t / _Beats._landingSwing) *
        math.exp(-t / _landingDecay);
  }

  /// The logo with its foot turned about the ankle, over the ground the foot
  /// has uncovered.
  ///
  /// The ground stands in for the artwork whole rather than being patched
  /// over it, and the foot is laid onto it source-atop in a layer of their
  /// own rather than clipped to the letter. Both for the same reason: the
  /// letter's edge is anti-aliased, and whatever is blended across it twice
  /// comes out lighter — the toes where they touch the wall would pale on
  /// the very frame they start to move. Source-atop, the foot takes the
  /// letter's coverage from the ground beneath it, once; and it still cannot
  /// leave the letter, so a toe that grazes the wall is cut by it, the way it
  /// would be by the edge of the relief.
  void _drawLifted(Canvas canvas, double turn) {
    final image = foot!;
    final pivot = SozoMarkGeometry.footPivot;
    canvas.saveLayer(geometry.bounds.inflate(2), _layer);
    canvas.drawPath(geometry.body, _groundPaint);
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(turn);
    canvas.translate(-pivot.dx, -pivot.dy);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      SozoMarkGeometry.footBox,
      _footPaint,
    );
    canvas.restore();
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
