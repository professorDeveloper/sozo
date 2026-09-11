import 'package:flutter/widgets.dart';

/// Common navigation destination descriptor across all Kaizoku navigation shells
/// (Mobile bottom bar, Desktop navigation rail, Android TV 10-foot rail).
@immutable
class KaizokuNavigationDestination {
  const KaizokuNavigationDestination({
    required this.id,
    required this.label,
    required this.icon,
    this.selectedIcon,
    this.badgeCount = 0,
    this.tooltip,
  });

  /// Unique identifier of the tab or route.
  final String id;

  /// User-facing label.
  final String label;

  /// Standard unselected icon.
  final Widget icon;

  /// Highlighted selected icon.
  final Widget? selectedIcon;

  /// Optional unread/update badge count (0 hides badge).
  final int badgeCount;

  /// Tooltip text for desktop hover.
  final String? tooltip;

  Widget get effectiveSelectedIcon => selectedIcon ?? icon;
}
