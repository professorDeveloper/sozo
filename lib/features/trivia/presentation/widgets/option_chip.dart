import 'package:flutter/material.dart';
import 'package:soplay/core/theme/app_colors.dart';

/// Visual state of a single answer chip during a clip.
///
/// - [idle]     tappable, nothing chosen yet
/// - [selected] optimistically locked while the submit is in flight
/// - [correct]  reveal: this was the right answer (green)
/// - [wrong]    reveal: the player picked this and it was wrong (red)
/// - [dimmed]   reveal: a non-picked, non-correct option (faded out)
enum OptionChipStatus { idle, selected, correct, wrong, dimmed }

/// One of the 2×2 answer options. Pure/`const`-friendly and stateless — all
/// transitions are driven by [status] so the parent can rebuild it cheaply.
class OptionChip extends StatelessWidget {
  const OptionChip({
    super.key,
    required this.label,
    required this.status,
    this.onTap,
  });

  final String label;
  final OptionChipStatus status;
  final VoidCallback? onTap;

  bool get _tappable => status == OptionChipStatus.idle && onTap != null;

  @override
  Widget build(BuildContext context) {
    final palette = _palette(status);

    final chip = AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.fill,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.border, width: 1.4),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.text,
                fontSize: 13.5,
                height: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (palette.icon != null) ...[
            const SizedBox(width: 6),
            Icon(palette.icon, color: palette.text, size: 18),
          ],
        ],
      ),
    );

    return Opacity(
      opacity: status == OptionChipStatus.dimmed ? 0.4 : 1.0,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: _tappable ? onTap : null,
          child: chip,
        ),
      ),
    );
  }

  _ChipPalette _palette(OptionChipStatus status) {
    switch (status) {
      case OptionChipStatus.correct:
        return _ChipPalette(
          fill: AppColors.success.withValues(alpha: 0.92),
          border: AppColors.success,
          text: Colors.white,
          icon: Icons.check_rounded,
        );
      case OptionChipStatus.wrong:
        // error, not primary. These two chips are shown side by side and the
        // whole point is that they read as opposites; under a green accent
        // "wrong" and "correct" would both have been green.
        return _ChipPalette(
          fill: AppColors.error.withValues(alpha: 0.9),
          // Lifted off the fill so the 1.4px rim still reads as a rim. This is
          // the exact colour the chip had before the accent became a setting.
          border: AppColors.errorLight,
          text: Colors.white,
          icon: Icons.close_rounded,
        );
      case OptionChipStatus.selected:
        return _ChipPalette(
          fill: AppColors.primary.withValues(alpha: 0.18),
          border: AppColors.primaryLight,
          text: Colors.white,
        );
      case OptionChipStatus.idle:
      case OptionChipStatus.dimmed:
        return _ChipPalette(
          fill: Colors.white.withValues(alpha: 0.08),
          border: Colors.white.withValues(alpha: 0.16),
          text: Colors.white,
        );
    }
  }
}

class _ChipPalette {
  const _ChipPalette({
    required this.fill,
    required this.border,
    required this.text,
    this.icon,
  });

  final Color fill;
  final Color border;
  final Color text;
  final IconData? icon;
}
