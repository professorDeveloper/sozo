import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:soplay/features/achievements/domain/achievements.dart';

/// A badge: a hexagonal medal in its tier's metal, the achievement's icon
/// struck into it.
///
/// Drawn rather than shipped as pictures, so one shape serves every badge at
/// every size, from a 20-point feed chip to the celebration's hero, and stays
/// sharp on any screen. The palette is the streak flame's: ember is the same
/// orange the flame burns in.
class AchievementMedal extends StatelessWidget {
  const AchievementMedal({
    super.key,
    required this.tier,
    required this.icon,
    this.size = 56,
    this.glow = true,
  });

  final MedalTier tier;
  final IconData icon;
  final double size;

  /// The halo around gold and ember. Off where many medals sit together and
  /// the glow would only muddy the row.
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final metal = _Metal.of(tier);
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _MedalPainter(metal, glow: glow),
        child: Center(
          child: Icon(icon, size: size * 0.42, color: metal.ink),
        ),
      ),
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
  });

  final String id;
  final MedalTier tier;
  final double size;
  final bool glow;

  @override
  Widget build(BuildContext context) => AchievementMedal(
    tier: tier,
    icon: AchievementDef.of(id).icon,
    size: size,
    glow: glow,
  );
}

@immutable
class _Metal {
  const _Metal({
    required this.rim,
    required this.face,
    required this.ink,
    this.glow,
    this.flat = false,
  });

  final Color rim;
  final List<Color> face;
  final Color ink;
  final Color? glow;
  final bool flat;

  static _Metal of(MedalTier tier) => switch (tier) {
    MedalTier.locked => const _Metal(
      rim: Color(0xFF3A3A3A),
      face: [Color(0xFF2C2C2C), Color(0xFF262626)],
      ink: Color(0xFF6A6A6A),
      flat: true,
    ),
    MedalTier.bronze => const _Metal(
      rim: Color(0xFF6E4119),
      face: [Color(0xFFF0B27A), Color(0xFFC27B38), Color(0xFF8E5424)],
      ink: Color(0xFFFFF4E8),
    ),
    MedalTier.silver => const _Metal(
      rim: Color(0xFF5F666E),
      face: [Color(0xFFFBFCFD), Color(0xFFC3CAD2), Color(0xFF8B939C)],
      ink: Color(0xFF262B31),
    ),
    MedalTier.gold => const _Metal(
      rim: Color(0xFF7D5A0E),
      face: [Color(0xFFFFEBA0), Color(0xFFF4C443), Color(0xFFC9900F)],
      ink: Color(0xFF442D00),
      glow: Color(0x59F4C443),
    ),
    MedalTier.ember => const _Metal(
      rim: Color(0xFF9C3D14),
      face: [Color(0xFFFFD9A0), Color(0xFFFFA94D), Color(0xFFEF7A35)],
      ink: Color(0xFFFFFFFF),
      glow: Color(0x99FF9646),
    ),
  };
}

class _MedalPainter extends CustomPainter {
  _MedalPainter(this.metal, {required this.glow});

  final _Metal metal;
  final bool glow;

  /// A pointy-topped hexagon filling [box] shrunk by [inset] on every side.
  static Path hex(Size box, double inset) {
    final cx = box.width / 2;
    final cy = box.height / 2;
    final r = math.min(box.width, box.height) / 2 - inset;
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final a = -math.pi / 2 + i * math.pi / 3;
      final p = Offset(cx + r * math.cos(a), cy + r * math.sin(a));
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final outer = hex(size, s * 0.02);

    final halo = metal.glow;
    if (glow && halo != null) {
      canvas.drawPath(
        outer,
        Paint()
          ..color = halo
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.12),
      );
    }

    canvas.drawPath(outer, Paint()..color = metal.rim);

    final face = hex(size, s * 0.065);
    final rect = Offset.zero & size;
    canvas.drawPath(
      face,
      Paint()
        ..shader = metal.flat
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: metal.face,
              ).createShader(rect)
        ..color = metal.face.first,
    );

    if (metal.flat) return;

    // The struck centre: a slightly darker, lit-from-above hexagon that
    // gives the face depth without a second colour.
    final inner = hex(size, s * 0.19);
    canvas.drawPath(
      inner,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.45),
          radius: 0.9,
          colors: [
            Colors.white.withValues(alpha: 0.30),
            Colors.black.withValues(alpha: 0.14),
          ],
        ).createShader(rect),
    );

    // A sheen across the upper half, as polished metal catches light.
    canvas.save();
    canvas.clipPath(face);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height * 0.46),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.22),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MedalPainter old) =>
      old.metal != metal || old.glow != glow;
}
