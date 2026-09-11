import 'package:flutter/material.dart';
import 'package:soplay/core/theme/kaizoku_colors.dart';

/// The 1…N clip progress indicator shown at the top of the game. Answered clips
/// read as solid dots, the clip in play is a stretched brand-red pill, and
/// upcoming clips are faint.
///
/// The row shares its line with a 54px countdown ring and a 38px close button,
/// so past [_kCompactFrom] clips the dots shrink instead of overflowing: at the
/// full size a 15-clip round would need 15 × 16 = 240px of dots alone.
class ProgressDots extends StatelessWidget {
  const ProgressDots({
    super.key,
    required this.total,
    required this.currentIndex,
  });

  /// Above this many clips the dots switch to their compact geometry.
  static const int _kCompactFrom = 12;

  final int total;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    final compact = total > _kCompactFrom;
    final dot = compact ? 6.0 : 8.0;
    final currentWidth = compact ? 16.0 : 22.0;
    final gap = compact ? 2.0 : 4.0;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(total, (i) {
        final isCurrent = i == currentIndex;
        final isDone = i < currentIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
          margin: EdgeInsets.symmetric(horizontal: gap),
          height: dot,
          width: isCurrent ? currentWidth : dot,
          decoration: BoxDecoration(
            color: isCurrent
                ? KaizokuColors.primary
                : isDone
                    ? KaizokuColors.textPrimary
                    : KaizokuColors.textHint,
            borderRadius: BorderRadius.circular(99),
          ),
        );
      }),
    );
  }
}
