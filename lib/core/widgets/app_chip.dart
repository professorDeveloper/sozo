import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:soplay/core/system/platform_utils.dart';
import 'package:soplay/core/theme/app_colors.dart';

/// Canonical selectable chip: tint fill + tinted border when selected,
/// lifted from the player page's quality/track chips.
///
/// Selection crossfades rather than cutting. A chip row is the one place in the
/// app where the thing the user just touched and the thing that changed are two
/// different widgets — you tap "1080p" and "720p" has to let go — and a hard
/// swap of both makes it ambiguous which of them moved.
class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final EdgeInsets padding;

  /// Long enough to be seen as a transition, short enough that a chip row does
  /// not feel like it lags behind the finger.
  static const Duration _duration = Duration(milliseconds: 150);

  void _handleTap() {
    // Chips are a picker, not a command: selectionClick is the detent, not the
    // thud of a confirmed action. Mobile only — on desktop it is a no-op
    // channel message, and a TV remote should not buzz for a menu move.
    if (isMobilePlatform) HapticFeedback.selectionClick();
    onTap();
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(10);
    final foreground = selected ? Colors.white : Colors.white70;
    return Semantics(
      button: true,
      selected: selected,
      child: AnimatedContainer(
        duration: _duration,
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.18)
              : Colors.white10,
          borderRadius: radius,
        ),
        // The border rides on the foreground so the ink splash, which paints on
        // the Material above the fill, cannot wash over it.
        foregroundDecoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(
            color: selected ? AppColors.primary : Colors.white12,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Material(
          // Transparent because the fill is the AnimatedContainer's now; the
          // Material is here for the ink and for the tap target's clip.
          color: Colors.transparent,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _handleTap,
            child: Padding(
              padding: padding,
              child: AnimatedDefaultTextStyle(
                duration: _duration,
                curve: Curves.easeOut,
                style: TextStyle(
                  color: foreground,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        // Reads the colour back out of the animated style so
                        // the icon interpolates with the label instead of
                        // snapping a frame ahead of it.
                        Builder(
                          builder: (ctx) => Icon(
                            icon,
                            size: 15,
                            color: DefaultTextStyle.of(ctx).style.color,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: Text(label, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
