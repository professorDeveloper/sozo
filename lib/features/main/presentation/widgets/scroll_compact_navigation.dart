import 'package:flutter/material.dart';

/// Tracks a deliberate vertical gesture, ignoring carousels and short lists.
class NavigationScrollState extends ValueNotifier<bool> {
  NavigationScrollState() : super(false);
  double _distance = 0;
  bool _gesture = false;

  void expand() {
    _distance = 0;
    _gesture = false;
    value = false;
  }

  bool onScroll(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    final metrics = notification.metrics;
    if (metrics.extentBefore <= 16 || metrics.maxScrollExtent < 120) {
      // Do not cancel the gesture: it may have just started at the top.
      _distance = 0;
      value = false;
    }
    if (notification is ScrollStartNotification) {
      _gesture = notification.dragDetails != null;
      _distance = 0;
    } else if (notification is ScrollEndNotification) {
      _gesture = false;
      _distance = 0;
    } else if (notification is ScrollUpdateNotification &&
        _gesture &&
        !metrics.outOfRange &&
        metrics.maxScrollExtent >= 120) {
      final delta = notification.scrollDelta ?? 0;
      if (delta == 0) return false;
      if (_distance.sign != delta.sign) _distance = 0;
      _distance += delta;
      if (!value && metrics.extentBefore > 80 && _distance >= 56) {
        value = true;
        _distance = 0;
      } else if (value && _distance <= -24) {
        value = false;
        _distance = 0;
      }
    }
    return false;
  }
}

/// Gently contracts the existing bar without replacing its style or controls.
/// Keeping layout dimensions stable avoids moving the scrolling content, and
/// Transform's hit testing follows the visible controls throughout the motion.
class ScrollCompactNavigation extends StatelessWidget {
  const ScrollCompactNavigation({
    super.key,
    required this.compact,
    required this.expanded,
  });
  final bool compact;
  final Widget expanded;

  @override
  Widget build(BuildContext context) => AnimatedScale(
    scale: compact ? .82 : 1,
    alignment: Alignment.bottomCenter,
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 300),
    curve: Curves.easeInOutCubic,
    child: expanded,
  );
}
