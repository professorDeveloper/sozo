import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:soplay/core/brand/sozo_mark_geometry.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/widgets/sozo_mark.dart';

/// The splash: the logo written by a pen that uncovers the dragon as it goes.
///
/// ## What the logo is
///
/// Not a red S. The Sozo logo is an S cut from a relief — a dragon in
/// orange-red on a peach ground, scales and claws and flame carved into it,
/// with a small "Sozo" in the top arm. Every earlier version of this splash
/// drew the outline and filled it with one flat colour, which is to say it
/// drew the one part of the logo that is not the logo. It looked like a
/// letter because that is all it was.
///
/// ## How it is drawn
///
/// The pen travels the letter's spine and the stroke it leaves is painted WITH
/// THE ARTWORK — an [ui.ImageShader] over the registered logo — so what
/// appears under the pen is the dragon itself, a stroke at a time, with a
/// molten edge where the reveal is still hot. Then the stroke widens until it
/// is the whole letter: the ribbon is the spine dilated by half its width, so
/// at full width the stroke IS the logo, with nowhere for a gap to be.
///
/// After it lands, the relief stays alive rather than turning into a picture:
/// a sheen crosses it so the carved scales catch light, embers rise off its
/// upper edges, and a warm glow behind it breathes. The outline itself no
/// longer moves — over a real texture an edge that wobbles reads as a
/// rendering fault, and the life now comes from light, fire and breath, which
/// is what a dragon has.
///
/// ## Colour
///
/// The fire is the artwork's own, sampled from it, not the accent the user
/// picked. The accent is theirs; the logo is the brand, and a blue dragon
/// breathing blue fire because somebody chose a blue theme is not the logo.
class SozoSplash extends StatefulWidget {
  const SozoSplash({super.key, required this.onSettled, required this.onDone});

  /// The letter has landed and the rest is decoration. The route resolves from
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

  /// The landing, reported once.
  ///
  /// From the listener rather than a timer: a controller that is behind —
  /// which on a cold start it will be — should hand over when the animation
  /// actually gets there, not when a clock says it should have.
  void _watch() {
    if (_settled || _c.value * _Beats.total < _Beats.landTo) return;
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
    // Half the narrow side. The logo is the only thing on this screen and
    // carries the frame alone; smaller, it reads as an icon somebody centred.
    final size = math.min(MediaQuery.sizeOf(context).shortestSide * 0.5, 260.0);

    if (geometry == null) {
      return _Stage(
        child: SozoMark(size: size, color: AppColors.primary),
      );
    }

    // Reduce motion gets the logo, not the performance: the finished relief
    // and its glow, faded in. An image that blinks into existence reads as a
    // glitch, and that much motion nobody asked to be spared.
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
                clock: () => _Beats.landTo.toDouble(),
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
/// The write is over a second on purpose. Measured on a device, a debug build
/// paints this at about 30fps and the first frames of any cold start are lost
/// to jank; at 780ms the writing was two dozen frames and nobody saw it.
abstract final class _Beats {
  static const int writeFrom = 160;
  static const int writeTo = 1300;
  static const int fillFrom = 1120;
  static const int fillTo = 1620;
  static const int landFrom = 1560;
  static const int landTo = 1800;
  static const int sheenFrom = 1720;
  static const int sheenTo = 2420;
  static const int embersFrom = 1500;
  static const int fadeFrom = 2560;
  static const int total = 2800;
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
    } else {
      _artPaint.color = _deep;
    }
    // Where embers can leave from: the outline samples that face upward.
    // Fire rises, and an ember leaving the underside of the letter reads as a
    // spark falling out of it.
    for (var i = 0; i < SozoMarkGeometry.outlineSamples; i++) {
      if (geometry.normalY[i] < -0.35) _tops.add(i);
    }
  }

  final SozoMarkGeometry geometry;
  final ui.Image? art;
  final Color background;
  final double Function() clock;

  /// The finished logo, with nothing moving. For reduce motion.
  final bool still;

  /// The artwork's own fire. Sampled from it: the dragon is #F93D0D and the
  /// ground #FBBCA0, and the embers sit between the two.
  static const Color _deep = Color(0xFFF93D0D);
  static const Color _flame = Color(0xFFFF6A2B);
  static const Color _ember = Color(0xFFFFD9A0);
  static const Color _core = Color(0xFFFFF6E8);

  /// Half the ribbon's width, measured off the asset: the stroke that is
  /// exactly the letter along its straight runs.
  static const double _halfRibbon = 30.5;

  /// Wide enough that the dragon is legible while it is being written, narrow
  /// enough that what is happening still reads as writing.
  static const double _writeWidth = 46;

  static const Curve _writeCurve = Cubic(0.30, 0.02, 0.18, 1.0);

  final List<int> _tops = [];

  final Paint _artPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;
  final Paint _rim = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final Paint _glow = Paint()
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22);
  final Paint _halo = Paint()
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9);
  final Paint _dot = Paint()..blendMode = BlendMode.plus;
  final Paint _fade = Paint();

  /// A band of light along the diagonal, built once and moved by translating
  /// the canvas. Overlay rather than plain white: over the relief it lifts the
  /// light faces of the carving and deepens the dark ones, which is what a
  /// raking light does to something embossed — plain white would just wash it.
  late final Paint _sheen = Paint()
    ..blendMode = BlendMode.overlay
    ..shader = ui.Gradient.linear(
      const Offset(-70, -70),
      const Offset(70, 70),
      const [Color(0x00FFFFFF), Color(0x7AFFFFFF), Color(0x00FFFFFF)],
      const [0.0, 0.5, 1.0],
    );

  static double _span(
    double ms,
    int from,
    int to, [
    Curve curve = Curves.linear,
  ]) => curve.transform(((ms - from) / (to - from)).clamp(0.0, 1.0));

  /// Stable noise in 0..1 for particle [i], channel [k]. Stateless on purpose:
  /// every particle's whole life is a function of the clock, so a dropped
  /// frame costs nothing and the loop replays exactly.
  static double _hash(int i, int k) {
    final v = math.sin(i * 12.9898 + k * 78.233) * 43758.5453;
    return v - v.floorToDouble();
  }

  /// A point on the spine at [u], from the sampled table — no contour walk.
  Offset _spineAt(double u) {
    final n = SozoMarkGeometry.spineSamples;
    final f = u.clamp(0.0, 1.0) * (n - 1);
    final i = f.floor().clamp(0, n - 2);
    final t = f - i;
    return Offset(
      geometry.spineX[i] + (geometry.spineX[i + 1] - geometry.spineX[i]) * t,
      geometry.spineY[i] + (geometry.spineY[i + 1] - geometry.spineY[i]) * t,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final ms = still ? _Beats.landTo.toDouble() : clock();
    final dim = still
        ? 1.0
        : 1 - _span(ms, _Beats.fadeFrom, _Beats.total, Curves.easeIn);
    if (dim <= 0.001) return;

    final write = still
        ? 1.0
        : _span(ms, _Beats.writeFrom, _Beats.writeTo, _writeCurve);
    final fill = still
        ? 1.0
        : _span(ms, _Beats.fillFrom, _Beats.fillTo, Curves.easeInOutCubic);
    final land = still
        ? 1.0
        : _span(ms, _Beats.landFrom, _Beats.landTo, Curves.easeOutBack);
    // One slow breath after landing, eased in so it does not start with a jolt.
    final breathing = still
        ? 0.0
        : _span(ms, _Beats.landTo, _Beats.landTo + 400);
    final breath = math.sin((ms - _Beats.landTo) / 1000 * 2 * math.pi * 0.5);

    final bounds = geometry.bounds;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(
      size.width /
          512 *
          (0.94 + 0.06 * land) *
          (1 + 0.012 * breath * breathing),
    );
    canvas.translate(-bounds.center.dx, -bounds.center.dy);

    // The warmth behind it. Arrives with the fill and then breathes.
    final glowIn = still
        ? 1.0
        : _span(ms, _Beats.fillFrom, _Beats.fillTo + 200);
    if (glowIn > 0) {
      _glow.color = _flame.withValues(
        alpha: glowIn * (0.26 + 0.09 * breath * breathing) * dim,
      );
      canvas.drawPath(geometry.body, _glow);
    }

    canvas.save();
    canvas.clipPath(geometry.body);
    if (write > 0) {
      final written = geometry.spineMetric.extractPath(
        0,
        geometry.spineLength * write,
      );
      final width = ui.lerpDouble(_writeWidth, _halfRibbon * 2.6, fill)!;
      // The molten edge: a hot rim just outside the uncovered artwork, still
      // glowing where the reveal has just happened, and gone once it is all
      // uncovered.
      if (fill < 1) {
        _rim
          ..color = _flame.withValues(alpha: 0.8 * (1 - fill))
          ..strokeWidth = width + 12;
        canvas.drawPath(written, _rim);
      }
      _artPaint.strokeWidth = width;
      canvas.drawPath(written, _artPaint);
    }

    // The sheen, crossing the relief once so the carving catches light.
    final sheen = still
        ? 0.0
        : _span(ms, _Beats.sheenFrom, _Beats.sheenTo, Curves.easeInOutSine);
    if (sheen > 0 && sheen < 1) {
      final d = ui.lerpDouble(-340, 340, sheen)!;
      canvas.save();
      canvas.translate(
        bounds.center.dx + d * 0.7071,
        bounds.center.dy + d * 0.7071,
      );
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: 900, height: 900),
        _sheen,
      );
      canvas.restore();
    }
    canvas.restore();

    if (!still) {
      _drawPen(canvas, write, dim);
      _drawSparks(canvas, ms, dim);
      _drawEmbers(canvas, ms, dim);
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

  /// The pen: a white-hot core with a halo, where the dragon is being uncovered.
  void _drawPen(Canvas canvas, double write, double dim) {
    if (write <= 0 || write >= 1) return;
    // Faded in and out at the ends, so the pen neither pops on nor lingers.
    final a = math.min(1.0, math.min(write * 12, (1 - write) * 12)) * dim;
    final tip = _spineAt(write);
    _halo.color = _flame.withValues(alpha: 0.6 * a);
    canvas.drawCircle(tip, 24, _halo);
    _dot.color = _ember.withValues(alpha: 0.95 * a);
    canvas.drawCircle(tip, 8, _dot);
    _dot.color = _core.withValues(alpha: a);
    canvas.drawCircle(tip, 4, _dot);
  }

  /// Sparks thrown off the pen while it writes.
  void _drawSparks(Canvas canvas, double ms, double dim) {
    const count = 30;
    const span = _Beats.writeTo - _Beats.writeFrom;
    for (var i = 0; i < count; i++) {
      final birth = _Beats.writeFrom + span * (i + _hash(i, 0) * 0.6) / count;
      final life = 380 + 240 * _hash(i, 1);
      final age = ms - birth;
      if (age < 0 || age > life) continue;
      final k = age / life;
      // Where the pen was when this spark left it.
      final origin = _spineAt(
        _writeCurve.transform(
          ((birth - _Beats.writeFrom) / span).clamp(0.0, 1.0),
        ),
      );
      final angle = _hash(i, 2) * 2 * math.pi;
      final speed = 60 + 120 * _hash(i, 3);
      final s = age / 1000;
      final p =
          origin +
          Offset(math.cos(angle), math.sin(angle)) * speed * s +
          // A little gravity, so they arc rather than fly in straight lines.
          Offset(0, 90 * s * s);
      final alpha = math.pow(1 - k, 1.4).toDouble() * dim;
      final colour = Color.lerp(_ember, _flame, k)!;
      _dot.color = colour.withValues(alpha: 0.28 * alpha);
      canvas.drawCircle(p, 6.5 * (1 - k) + 1.5, _dot);
      _dot.color = colour.withValues(alpha: alpha);
      canvas.drawCircle(p, 2.6 * (1 - k) + 0.8, _dot);
    }
  }

  /// Embers rising off the finished letter.
  void _drawEmbers(Canvas canvas, double ms, double dim) {
    if (_tops.isEmpty || ms < _Beats.embersFrom) return;
    const count = 20;
    const window = _Beats.total - _Beats.embersFrom - 500;
    for (var i = 0; i < count; i++) {
      final birth = _Beats.embersFrom + window * _hash(i, 4);
      final life = 850 + 550 * _hash(i, 5);
      final age = ms - birth;
      if (age < 0 || age > life) continue;
      final k = age / life;
      final at = _tops[(_hash(i, 6) * _tops.length).floor() % _tops.length];
      final origin = Offset(geometry.outlineX[at], geometry.outlineY[at]);
      final s = age / 1000;
      final rise = (40 + 55 * _hash(i, 7)) * s;
      final sway = math.sin(s * 2 * math.pi * (0.7 + _hash(i, 8))) * 7;
      final p = origin + Offset(sway, -rise);
      // Brightens as it leaves, then burns out.
      final alpha = (k < 0.15 ? k / 0.15 : 1 - (k - 0.15) / 0.85) * 0.9 * dim;
      final colour = Color.lerp(_ember, _flame, k)!;
      _dot.color = colour.withValues(alpha: 0.25 * alpha);
      canvas.drawCircle(p, 6 * (1 - 0.5 * k), _dot);
      _dot.color = colour.withValues(alpha: alpha);
      canvas.drawCircle(p, 2.2 * (1 - 0.5 * k), _dot);
    }
  }

  @override
  bool shouldRepaint(_LogoPainter old) => still != old.still;
}
