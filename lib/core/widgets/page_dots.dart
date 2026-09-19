import 'package:flutter/material.dart';
import 'package:soplay/core/theme/app_colors.dart';

/// Canonical page indicator, standardised on the desktop hero carousel's dots.
/// Renders nothing for a single page.
class PageDots extends StatelessWidget {
  const PageDots({
    super.key,
    required this.count,
    required this.index,
    this.onTap,
  });

  final int count;
  final int index;
  final ValueChanged<int>? onTap;

  /// The minimum touch target both platforms ask for. Only applied when the
  /// dots are tappable, so a decorative indicator keeps its 8dp row.
  static const double _hitSize = 44;

  @override
  Widget build(BuildContext context) {
    if (count < 2) return const SizedBox.shrink();
    final tappable = onTap != null;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == index;
        final dot = AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          width: active ? 22 : 8,
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: active ? AppColors.textPrimary : AppColors.textHint,
            borderRadius: BorderRadius.circular(99),
          ),
        );
        if (!tappable) return dot;
        return Semantics(
          button: true,
          selected: active,
          child: GestureDetector(
            // Opaque so the transparent box around the dot takes the tap; a
            // bare 8dp dot is a target most thumbs miss.
            behavior: HitTestBehavior.opaque,
            onTap: () => onTap!(i),
            child: SizedBox(
              // Height only. The dots sit 16dp apart, so a 44dp-wide box would
              // overlap its neighbour's and steal taps meant for the next page.
              height: _hitSize,
              child: Center(child: dot),
            ),
          ),
        );
      }),
    );
  }
}
