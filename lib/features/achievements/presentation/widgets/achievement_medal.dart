import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:soplay/features/achievements/domain/achievements.dart';

/// A badge: a hexagonal medal in its tier's metal, the achievement's icon
/// struck into it.
///
/// Drawn, not shipped as pictures or models, and drawn to read as a solid
/// object: a bevelled rim whose six facets catch a light from the upper
/// left, a recessed field, the icon embossed into it, and a specular sheen
/// that moves when the medal is tilted ([light]). One shape serves every
/// badge at every size, from a feed chip to the celebration's hero.
///
/// A medal not yet earned is a darker, unstruck blank: the icon only a
/// recessed outline, a small lock under it, and — given [progress] — how far
/// along it is traced round its edge in ember.
class AchievementMedal extends StatelessWidget {
  const AchievementMedal({
    super.key,
    required this.tier,
    required this.icon,
    this.size = 56,
    this.glow = true,
    this.progress,
    this.light = Offset.zero,
    this.showBack = false,
  });

  final MedalTier tier;
  final IconData icon;
  final double size;

  /// The halo around gold and ember. Off where many medals sit together and
  /// the glow would only muddy the row.
  final bool glow;

  /// 0..1 toward earning it, traced round the rim. Locked medals only.
  final double? progress;

  /// Where the light has moved to, -1..1 on each axis, as the medal tilts.
  final Offset light;

  /// The reverse: plain struck metal, for a medal caught mid-turn.
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final metal = _Metal.of(tier);
    final locked = tier == MedalTier.locked;
    final iconSize = size * 0.40;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _MedalPainter(
          metal,
          glow: glow,
          progress: locked ? progress : null,
          light: light,
        ),
        child: showBack
            ? null
            : Stack(
                alignment: Alignment.center,
                children: [
                  // Embossed: a shadow below-right and a highlight above-left
                  // around the ink make the icon sit in the metal rather than
                  // on it. A locked blank is the other way round — pressed in.
                  Transform.translate(
                    offset:
                        Offset(size * 0.012, size * 0.018) * (locked ? -1 : 1),
                    child: Icon(icon, size: iconSize, color: metal.emboss),
                  ),
                  Transform.translate(
                    offset:
                        Offset(-size * 0.010, -size * 0.012) *
                        (locked ? -1 : 1),
                    child: Icon(icon, size: iconSize, color: metal.highlight),
                  ),
                  Icon(icon, size: iconSize, color: metal.ink),
                  if (locked && size >= 34)
                    Positioned(
                      bottom: size * 0.06,
                      child: _LockPip(size: size * 0.26),
                    ),
                ],
              ),
      ),
    );
  }
}

/// Paints a medal straight onto [canvas], for pictures made outside a widget
/// tree — the home-screen widget's. The same metal, bevel and emboss as
/// [AchievementMedal].
///
/// [progress] is traced round the rim at any tier here, not only a locked
/// one: on the home screen it is the way to the next tier.
void paintMedal(
  Canvas canvas,
  Size size, {
  required MedalTier tier,
  required IconData icon,
  double? progress,
  bool glow = true,
}) {
  final metal = _Metal.of(tier);
  _MedalPainter(
    metal,
    glow: glow,
    progress: progress,
    light: Offset.zero,
  ).paint(canvas, size);
  final s = size.shortestSide;
  final locked = tier == MedalTier.locked;
  // Raised: a shadow below-right, a highlight above-left. A locked blank is
  // the other way round — pressed in.
  final down = Offset(s * 0.012, s * 0.018) * (locked ? -1 : 1);
  final up = Offset(-s * 0.010, -s * 0.012) * (locked ? -1 : 1);
  for (final (color, shift) in [
    (metal.emboss, down),
    (metal.highlight, up),
    (metal.ink, Offset.zero),
  ]) {
    final painter = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: s * 0.40,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: color,
          height: 1,
        ),
      ),
    )..layout();
    painter.paint(
      canvas,
      size.center(Offset.zero) +
          shift -
          Offset(painter.width / 2, painter.height / 2),
    );
  }
}

/// A medal for an achievement id at a tier — the common case.
class AchievementBadge extends StatelessWidget {
  const AchievementBadge({
    super.key,
    required this.id,
    required this.tier,
    this.size = 56,
    this.glow = true,
    this.progress,
    this.light = Offset.zero,
  });

  final String id;
  final MedalTier tier;
  final double size;
  final bool glow;
  final double? progress;
  final Offset light;

  @override
  Widget build(BuildContext context) => AchievementMedal(
    tier: tier,
    icon: AchievementDef.of(id).icon,
    size: size,
    glow: glow,
    progress: progress,
    light: light,
  );
}

/// Lets a medal be tilted with a finger, in perspective, the light sliding
/// across its face — and settle back when let go.
class MedalTilt extends StatefulWidget {
  const MedalTilt({super.key, required this.builder, this.maxAngle = 0.32});

  /// Builds the medal with the light where the tilt puts it.
  final Widget Function(Offset light) builder;
  final double maxAngle;

  @override
  State<MedalTilt> createState() => _MedalTiltState();
}

class _MedalTiltState extends State<MedalTilt>
    with SingleTickerProviderStateMixin {
  Offset _tilt = Offset.zero;
  Offset _from = Offset.zero;
  // Made in initState, not lazily: a medal never touched would otherwise
  // first create its controller in dispose, when there is no ticker to ask.
  late final AnimationController _settle;

  @override
  void initState() {
    super.initState();
    _settle =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 520),
        )..addListener(() {
          final t = Curves.easeOutBack.transform(_settle.value);
          setState(() => _tilt = Offset.lerp(_from, Offset.zero, t)!);
        });
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  void _track(Offset local, Size box) {
    _settle.stop();
    final dx = ((local.dx / box.width) * 2 - 1).clamp(-1.0, 1.0);
    final dy = ((local.dy / box.height) * 2 - 1).clamp(-1.0, 1.0);
    setState(() => _tilt = Offset(dx, dy));
  }

  void _release() {
    _from = _tilt;
    _settle.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final size = Size(box.maxWidth, box.maxHeight);
        return GestureDetector(
          onPanDown: (d) => _track(d.localPosition, size),
          onPanUpdate: (d) => _track(d.localPosition, size),
          onPanEnd: (_) => _release(),
          onPanCancel: _release,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0016)
              ..rotateX(-_tilt.dy * widget.maxAngle)
              ..rotateY(_tilt.dx * widget.maxAngle),
            child: widget.builder(_tilt),
          ),
        );
      },
    );
  }
}

class _LockPip extends StatelessWidget {
  const _LockPip({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF3B4046),
        border: Border.all(color: const Color(0xFF9AA0A8), width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Icon(
        Icons.lock_rounded,
        size: size * 0.62,
        color: const Color(0xFFE3E6EA),
      ),
    );
  }
}

@immutable
class _Metal {
  const _Metal({
    required this.rim,
    required this.bevelLight,
    required this.bevelDark,
    required this.face,
    required this.field,
    required this.ink,
    required this.emboss,
    required this.highlight,
    this.glow,
    this.sparkle = false,
  });

  final Color rim;
  final Color bevelLight;
  final Color bevelDark;
  final List<Color> face;
  final List<Color> field;
  final Color ink;
  final Color emboss;
  final Color highlight;
  final Color? glow;
  final bool sparkle;

  static _Metal of(MedalTier tier) => switch (tier) {
    // Unpolished pewter rather than black: still plainly not won, but metal
    // waiting to be struck — a black blank read as a hole in the page.
    MedalTier.locked => const _Metal(
      rim: Color(0xFF2B2F34),
      bevelLight: Color(0xFFA3A9B1),
      bevelDark: Color(0xFF41464D),
      face: [Color(0xFF7E858E), Color(0xFF626870), Color(0xFF4D5259)],
      field: [Color(0xFF52575E), Color(0xFF686E76)],
      ink: Color(0xFF3B4046),
      emboss: Color(0x33000000),
      highlight: Color(0x40FFFFFF),
    ),
    MedalTier.bronze => const _Metal(
      rim: Color(0xFF4A2A10),
      bevelLight: Color(0xFFF6C597),
      bevelDark: Color(0xFF6A3D18),
      face: [Color(0xFFE9A566), Color(0xFFB8702F), Color(0xFF8A5022)],
      field: [Color(0xFF9E5C27), Color(0xFFC9854A)],
      ink: Color(0xFFFFE9D2),
      emboss: Color(0x99401E05),
      highlight: Color(0x66FFFFFF),
    ),
    MedalTier.silver => const _Metal(
      rim: Color(0xFF454B52),
      bevelLight: Color(0xFFFFFFFF),
      bevelDark: Color(0xFF7C848D),
      face: [Color(0xFFF4F6F8), Color(0xFFC3CAD2), Color(0xFF959DA6)],
      field: [Color(0xFFA7AFB8), Color(0xFFD7DCE1)],
      ink: Color(0xFF2B3036),
      emboss: Color(0x55000000),
      highlight: Color(0xAAFFFFFF),
    ),
    MedalTier.gold => const _Metal(
      rim: Color(0xFF5C3F06),
      bevelLight: Color(0xFFFFF3C4),
      bevelDark: Color(0xFFA2710B),
      face: [Color(0xFFFFE89A), Color(0xFFF2BD3A), Color(0xFFC4880C)],
      field: [Color(0xFFD99D16), Color(0xFFF8D067)],
      ink: Color(0xFF4A3000),
      emboss: Color(0x66402800),
      highlight: Color(0x99FFFBE6),
      glow: Color(0x59F4C443),
      sparkle: true,
    ),
    MedalTier.ember => const _Metal(
      rim: Color(0xFF7A2A0C),
      bevelLight: Color(0xFFFFE2B8),
      bevelDark: Color(0xFFB8471C),
      face: [Color(0xFFFFD49A), Color(0xFFFFA94D), Color(0xFFE8672A)],
      field: [Color(0xFFD9582A), Color(0xFFFFB566)],
      ink: Color(0xFFFFFFFF),
      emboss: Color(0x88601800),
      highlight: Color(0x66FFF3E0),
      glow: Color(0xA6FF9646),
      sparkle: true,
    ),
  };
}

class _MedalPainter extends CustomPainter {
  _MedalPainter(
    this.metal, {
    required this.glow,
    required this.progress,
    required this.light,
  });

  final _Metal metal;
  final bool glow;
  final double? progress;
  final Offset light;

  static List<Offset> _corners(Size box, double r) {
    final c = box.center(Offset.zero);
    return [
      for (var i = 0; i < 6; i++)
        c +
            Offset(
              r * math.cos(-math.pi / 2 + i * math.pi / 3),
              r * math.sin(-math.pi / 2 + i * math.pi / 3),
            ),
    ];
  }

  static Path _hex(List<Offset> pts) {
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (final p in pts.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final r = s / 2;
    final outer = _corners(size, r * 0.97);
    final bevelOut = _corners(size, r * 0.90);
    final bevelIn = _corners(size, r * 0.74);
    final fieldPts = _corners(size, r * 0.62);
    final rect = Offset.zero & size;

    // Halo.
    final halo = metal.glow;
    if (glow && halo != null) {
      canvas.drawPath(
        _hex(outer),
        Paint()
          ..color = halo
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.13),
      );
    }

    // Drop shadow, so the medal sits above the card.
    canvas.drawPath(
      _hex(outer).shift(Offset(0, s * 0.03)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.45)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.04),
    );

    // Rim.
    canvas.drawPath(_hex(outer), Paint()..color = metal.rim);

    // Six bevel facets, each lit by how squarely it faces the light — from
    // the upper left, moving as the medal tilts.
    final lightDir = Offset(-0.62 + light.dx * 0.5, -0.78 + light.dy * 0.5);
    final lightLen = lightDir.distance;
    for (var i = 0; i < 6; i++) {
      final a = bevelOut[i], b = bevelOut[(i + 1) % 6];
      final c = bevelIn[(i + 1) % 6], d = bevelIn[i];
      final mid = (a + b) / 2 - size.center(Offset.zero);
      final normal = mid / mid.distance;
      final lit =
          ((normal.dx * lightDir.dx + normal.dy * lightDir.dy) / lightLen + 1) /
          2;
      final facet = Path()
        ..moveTo(a.dx, a.dy)
        ..lineTo(b.dx, b.dy)
        ..lineTo(c.dx, c.dy)
        ..lineTo(d.dx, d.dy)
        ..close();
      canvas.drawPath(
        facet,
        Paint()..color = Color.lerp(metal.bevelDark, metal.bevelLight, lit)!,
      );
    }

    // The face, and the recessed field it frames.
    final facePath = _hex(bevelIn);
    canvas.drawPath(
      facePath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment(-0.8 + light.dx * 0.4, -1 + light.dy * 0.4),
          end: Alignment(0.8 + light.dx * 0.4, 1 + light.dy * 0.4),
          colors: metal.face,
        ).createShader(rect),
    );
    final field = _hex(fieldPts);
    canvas.drawPath(
      field,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: metal.field,
        ).createShader(rect),
    );
    // The field's edge: dark above-left, light below-right, as a hollow is.
    canvas.drawPath(
      field,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, s * 0.022)
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.black.withValues(alpha: 0.35),
            Colors.white.withValues(alpha: 0.28),
          ],
        ).createShader(rect),
    );

    // A specular band across the face, following the light.
    canvas.save();
    canvas.clipPath(facePath);
    final band = s * 0.34;
    final cx = size.width * (0.30 - light.dx * 0.25);
    final shine = Path()
      ..moveTo(cx - band, 0)
      ..lineTo(cx, 0)
      ..lineTo(cx - band * 1.6, size.height)
      ..lineTo(cx - band * 2.6, size.height)
      ..close();
    canvas.drawPath(
      shine,
      Paint()
        ..color = Colors.white.withValues(
          alpha: metal.glow == null && progress != null ? 0.05 : 0.16,
        )
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.03),
    );
    canvas.restore();

    // A glint on the upper-right edge of the precious metals.
    if (metal.sparkle && s >= 30) {
      final at = bevelOut[1] + Offset(-s * 0.06, s * 0.04);
      _sparkle(canvas, at, s * 0.075);
    }

    // How far along a locked badge is, traced round its edge.
    final p = progress;
    if (p != null && p > 0) {
      final ring = _hex(_corners(size, r * 0.935));
      final metric = ring.computeMetrics().first;
      // From the top point, clockwise.
      final part = metric.extractPath(0, metric.length * p.clamp(0.0, 1.0));
      canvas.drawPath(
        part,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.6, s * 0.05)
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFFFFA94D),
      );
    }
  }

  void _sparkle(Canvas canvas, Offset at, double r) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.6);
    final star = Path()
      ..moveTo(at.dx, at.dy - r)
      ..quadraticBezierTo(at.dx, at.dy, at.dx + r, at.dy)
      ..quadraticBezierTo(at.dx, at.dy, at.dx, at.dy + r)
      ..quadraticBezierTo(at.dx, at.dy, at.dx - r, at.dy)
      ..quadraticBezierTo(at.dx, at.dy, at.dx, at.dy - r)
      ..close();
    canvas.drawPath(star, paint);
    canvas.drawCircle(
      at,
      r * 0.9,
      Paint()
        ..shader = ui.Gradient.radial(at, r * 0.9, [
          Colors.white.withValues(alpha: 0.35),
          Colors.white.withValues(alpha: 0),
        ]),
    );
  }

  @override
  bool shouldRepaint(_MedalPainter old) =>
      old.metal != metal ||
      old.glow != glow ||
      old.progress != progress ||
      old.light != light;
}
