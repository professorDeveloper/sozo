import 'package:flutter/material.dart';

/// Trakt's red.
const Color kTraktRed = Color(0xFFED1C24);

/// A small Trakt mark: the red disc with the white ring and tick, drawn so
/// no brand asset has to ship.
class TraktLogo extends StatelessWidget {
  const TraktLogo({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _TraktMarkPainter()),
  );
}

class _TraktMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    canvas.drawCircle(c, r, Paint()..color = kTraktRed);
    canvas.drawCircle(
      c,
      r * 0.68,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.12,
    );
    final tick = Path()
      ..moveTo(c.dx - r * 0.32, c.dy + r * 0.02)
      ..lineTo(c.dx - r * 0.08, c.dy + r * 0.26)
      ..lineTo(c.dx + r * 0.36, c.dy - r * 0.24);
    canvas.drawPath(
      tick,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.14
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_TraktMarkPainter old) => false;
}
