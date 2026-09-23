import 'package:flutter/material.dart';
import 'package:soplay/core/content/content_mode.dart';

/// Purpose-drawn destination artwork, in the same 112px tile as catalogues.
/// No icon-font dependency: panels, paper and film retain crisp edges at any DPR.
class ModeDestinationArtwork extends StatelessWidget {
  const ModeDestinationArtwork({
    super.key,
    required this.mode,
    required this.color,
    this.progress = 1,
  });
  final ContentMode mode;
  final Color color;
  final double progress;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size.square(112),
    painter: _Artwork(
      mode,
      color,
      MediaQuery.disableAnimationsOf(context) ? 1 : progress,
    ),
  );
}

class _Artwork extends CustomPainter {
  const _Artwork(this.mode, this.color, this.progress);
  final double progress;
  final ContentMode mode;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 112, size.height / 112);
    final paint = Paint()..isAntiAlias = true;
    void rect(Rect rect, Color c, [double radius = 3]) => canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      paint
        ..color = c
        ..shader = null
        ..style = PaintingStyle.fill,
    );
    void line(Offset a, Offset b, Color c, [double width = 2]) =>
        canvas.drawLine(
          a,
          Offset.lerp(
            a,
            b,
            Curves.easeOutCubic.transform(((progress - .45) / .5).clamp(0, 1)),
          )!,
          paint
            ..shader = null
            ..color = c
            ..style = PaintingStyle.stroke
            ..strokeWidth = width
            ..strokeCap = StrokeCap.round,
        );
    final pale = Color.lerp(color, Colors.white, .86)!;
    rect(const Rect.fromLTWH(0, 0, 112, 112), const Color(0xFF20232C), 24);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(1, 1, 110, 110),
        const Radius.circular(23),
      ),
      Paint()
        ..color = color.withValues(alpha: .25)
        ..style = PaintingStyle.stroke,
    );
    // Reveal film across its frame, manga down its panels, and book pages
    // out from the binding. Text strokes then write on inside that reveal.
    final reveal = Curves.easeInOutCubic.transform(
      ((progress - .10) / .68).clamp(0, 1),
    );
    canvas.save();
    canvas.clipRect(switch (mode) {
      ContentMode.video => Rect.fromLTWH(0, 0, 112 * reveal, 112),
      ContentMode.manga => Rect.fromLTWH(0, 0, 112, 112 * reveal),
      ContentMode.novel => Rect.fromCenter(
        center: const Offset(56, 56),
        width: 112 * reveal,
        height: 112,
      ),
    });
    switch (mode) {
      case ContentMode.video:
        rect(const Rect.fromLTWH(17, 27, 78, 61), Colors.black26, 10);
        rect(const Rect.fromLTWH(14, 23, 84, 62), color, 8);
        rect(const Rect.fromLTWH(20, 35, 72, 38), const Color(0xFF101A26), 4);
        for (final x in [24.0, 38.0, 52.0, 66.0, 80.0]) {
          rect(Rect.fromLTWH(x, 27, 7, 4), pale, 1);
          rect(Rect.fromLTWH(x, 77, 7, 4), pale, 1);
        }
        canvas.drawPath(
          Path()
            ..moveTo(48, 44)
            ..lineTo(48, 65)
            ..lineTo(66, 54.5)
            ..close(),
          Paint()..color = pale,
        );
        line(
          const Offset(30, 94),
          const Offset(82, 94),
          color.withValues(alpha: .4),
          2,
        );
      case ContentMode.manga:
        rect(
          const Rect.fromLTWH(27, 16, 65, 84),
          color.withValues(alpha: .3),
          5,
        );
        rect(const Rect.fromLTWH(20, 12, 66, 84), pale, 5);
        rect(const Rect.fromLTWH(26, 19, 54, 27), const Color(0xFF292335), 2);
        // An inked landscape panel, a dialogue balloon, then a speed-line panel.
        canvas.drawPath(
          Path()
            ..moveTo(26, 43)
            ..lineTo(39, 30)
            ..lineTo(50, 39)
            ..lineTo(61, 26)
            ..lineTo(80, 43)
            ..close(),
          Paint()..color = color,
        );
        rect(const Rect.fromLTWH(26, 51, 23, 37), color, 2);
        canvas.drawOval(
          const Rect.fromLTWH(30, 57, 15, 12),
          Paint()..color = pale,
        );
        line(const Offset(37, 69), const Offset(33, 73), pale, 2);
        rect(const Rect.fromLTWH(54, 51, 26, 37), const Color(0xFF292335), 2);
        for (var i = 0; i < 5; i++) {
          line(
            Offset(58, 57 + i * 6),
            Offset(75, 54 + i * 6),
            pale.withValues(alpha: .75),
            1.3,
          );
        }
      case ContentMode.novel:
        // Two separate curved pages and a visible binding, not a book glyph.
        final left = Path()
          ..moveTo(17, 27)
          ..quadraticBezierTo(36, 20, 56, 32)
          ..lineTo(56, 88)
          ..quadraticBezierTo(35, 76, 17, 83)
          ..close();
        final right = Path()
          ..moveTo(56, 32)
          ..quadraticBezierTo(76, 20, 95, 27)
          ..lineTo(95, 83)
          ..quadraticBezierTo(76, 76, 56, 88)
          ..close();
        canvas.drawPath(
          left.shift(const Offset(-3, 4)),
          Paint()..color = color,
        );
        canvas.drawPath(
          right.shift(const Offset(3, 4)),
          Paint()..color = color,
        );
        canvas.drawPath(left, Paint()..color = pale);
        canvas.drawPath(right, Paint()..color = Color.lerp(pale, color, .14)!);
        line(
          const Offset(56, 33),
          const Offset(56, 88),
          color.withValues(alpha: .6),
          2,
        );
        for (var i = 0; i < 5; i++) {
          line(
            Offset(25, 39 + i * 7),
            Offset(48, 43 + i * 7),
            const Color(0xFF69625A),
            1.6,
          );
          line(
            Offset(64, 43 + i * 7),
            Offset(86, 39 + i * 7),
            const Color(0xFF69625A),
            1.6,
          );
        }
        canvas.drawPath(
          Path()
            ..moveTo(78, 25)
            ..lineTo(85, 24)
            ..lineTo(85, 49)
            ..lineTo(81.5, 46)
            ..lineTo(78, 50)
            ..close(),
          Paint()..color = color,
        );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Artwork old) =>
      old.mode != mode || old.color != color || old.progress != progress;
}
