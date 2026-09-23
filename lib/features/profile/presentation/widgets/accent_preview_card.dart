import 'package:flutter/material.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/theme/app_palette.dart';

/// A theme option previews its own palette, independent of the active theme.
/// One tap target and one semantic label; the miniature is decorative.
class AccentPreviewCard extends StatelessWidget {
  const AccentPreviewCard({
    super.key,
    required this.palette,
    required this.label,
    required this.selected,
    required this.onTap,
    this.custom = false,
  });

  final AppPalette palette;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool custom;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    child: ExcludeSemantics(
      child: Material(
        color: palette.surface,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 150),
            width: 156,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected ? palette.primary : palette.border,
                width: selected ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CustomPaint(
                      painter: _ThemeScene(palette),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                          fontSize: 13,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected ? palette.primary : Colors.transparent,
                        border: Border.all(
                          color: selected ? palette.primary : palette.border,
                        ),
                      ),
                      child: Icon(
                        selected
                            ? Icons.check_rounded
                            : custom
                            ? Icons.add_rounded
                            : null,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _ThemeScene extends CustomPainter {
  const _ThemeScene(this.palette);
  final AppPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 132, size.height / 108);
    void box(
      double x,
      double y,
      double w,
      double h,
      Color color, [
      double radius = 4,
    ]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, w, h),
          Radius.circular(radius),
        ),
        Paint()..color = color,
      );
    }

    box(0, 0, 132, 108, palette.background, 0);
    // App bar: title and an active profile badge.
    box(12, 12, 40, 5, AppColors.textPrimary.withValues(alpha: .65));
    canvas.drawCircle(
      const Offset(115, 15),
      5,
      Paint()..color = palette.primary.withValues(alpha: .35),
    );
    // Raised content surface and contrasting primary action.
    box(8, 29, 116, 49, palette.card, 8);
    box(17, 38, 49, 4, AppColors.textSecondary.withValues(alpha: .6));
    box(17, 49, 62, 18, palette.primary, 9);
    final play = Path()
      ..moveTo(30, 54)
      ..lineTo(30, 62)
      ..lineTo(36, 58)
      ..close();
    canvas.drawPath(play, Paint()..color = palette.onPrimary);
    box(42, 56, 25, 3, palette.onPrimary.withValues(alpha: .85));
    box(87, 49, 27, 18, palette.primary.withValues(alpha: .16), 9);
    box(17, 73, 76, 2, palette.primary.withValues(alpha: .6), 1);
    // Navigation shows the actual tint preference, not a hard-coded accent.
    box(0, 86, 132, 22, palette.navBackground, 0);
    box(
      13,
      92,
      29,
      10,
      (palette.tintNav ? palette.primary : AppColors.textPrimary).withValues(
        alpha: .2,
      ),
      5,
    );
    for (final x in [27.0, 66.0, 105.0]) {
      canvas.drawCircle(
        Offset(x, 97),
        2.5,
        Paint()
          ..color = x == 27
              ? (palette.tintNav ? palette.primary : AppColors.textPrimary)
              : AppColors.textHint,
      );
    }
  }

  @override
  bool shouldRepaint(_ThemeScene old) => old.palette != palette;
}
