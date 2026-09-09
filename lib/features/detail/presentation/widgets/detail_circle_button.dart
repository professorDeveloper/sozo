import 'package:flutter/material.dart';

import 'package:soplay/core/system/responsive.dart';

/// The round chrome button over the detail header — back, add-to-list, more.
///
/// ## Why one widget
///
/// There were three, and they disagreed on every number: 36pt at black-42%
/// behind an 8-sigma blur in the loaded top bar, 38pt at black-45% with no
/// blur on the skeleton, and 38pt at black-38% with blur in the hero overlay.
/// The skeleton's is the one somebody looks at first, so the back button
/// visibly changed size and tint the moment the page finished loading — a
/// two-pixel jump in the one control that was on screen the whole time.
///
/// The blur went with them. Once the collapsing bar's fill passes about 90%
/// opacity it is sampling an almost-flat surface, so the `BackdropFilter` was
/// buying nothing for the cost of an offscreen pass per button per frame.
class DetailCircleButton extends StatelessWidget {
  const DetailCircleButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
    this.onLongPress,
    this.iconColor = Colors.white,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color iconColor;

  /// Read aloud, and shown as the desktop tooltip.
  ///
  /// Back, the add-to-list icon and the three-dot menu were all announced as
  /// unlabelled buttons — a screen reader had nothing to say about any of
  /// them, and the icon-only design gives a sighted first-time user nothing
  /// either.
  final String semanticLabel;

  static const double size = 38;
  static const double _iconSize = 18;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;

    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel,
      child: Tooltip(
        message: semanticLabel,
        // A tooltip on touch needs a long-press, which this button already
        // uses for its own action where one is set.
        triggerMode: isDesktopPlatform
            ? TooltipTriggerMode.longPress
            : TooltipTriggerMode.manual,
        child: HoverTap(
          onTap: onTap,
          onLongPress: onLongPress,
          onSecondaryTap: onLongPress,
          scale: enabled ? 1.04 : 1.0,
          child: Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: 0.42),
            ),
            child: Icon(
              icon,
              color: enabled ? iconColor : iconColor.withValues(alpha: 0.38),
              size: _iconSize,
            ),
          ),
        ),
      ),
    );
  }
}
