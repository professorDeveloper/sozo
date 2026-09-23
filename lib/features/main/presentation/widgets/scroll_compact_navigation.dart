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

/// Keeps the original navigation mounted and its content viewport unchanged.
class ScrollCompactNavigation extends StatelessWidget {
  const ScrollCompactNavigation({
    super.key,
    required this.compact,
    required this.expanded,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
  });
  final bool compact;
  final Widget expanded;
  final List<NavigationDestination> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedCrossFade(
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 300),
      reverseDuration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 340),
      sizeCurve: Curves.easeInOutCubic,
      firstCurve: Curves.easeInOut,
      secondCurve: Curves.easeInOut,
      alignment: Alignment.bottomCenter,
      crossFadeState: compact
          ? CrossFadeState.showSecond
          : CrossFadeState.showFirst,
      firstChild: IgnorePointer(
        ignoring: compact,
        child: ExcludeSemantics(excluding: compact, child: expanded),
      ),
      secondChild: IgnorePointer(
        ignoring: !compact,
        child: ExcludeSemantics(
          excluding: !compact,
          child: SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Center(
              child: Material(
                elevation: 4,
                color: colors.surfaceContainerHigh,
                shape: StadiumBorder(
                  side: BorderSide(color: colors.outlineVariant),
                ),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < items.length; i++)
                        Semantics(
                          selected: selectedIndex == i,
                          button: true,
                          label: items[i].label,
                          child: Tooltip(
                            message: items[i].label,
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () => onSelected(i),
                              child: AnimatedContainer(
                                duration: reduceMotion
                                    ? Duration.zero
                                    : const Duration(milliseconds: 180),
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: selectedIndex == i
                                      ? colors.primaryContainer
                                      : Colors.transparent,
                                ),
                                child: IconTheme(
                                  data: IconThemeData(
                                    size: 23,
                                    color: selectedIndex == i
                                        ? colors.onPrimaryContainer
                                        : colors.onSurfaceVariant,
                                  ),
                                  child: ExcludeSemantics(
                                    child: selectedIndex == i
                                        ? items[i].selectedIcon ?? items[i].icon
                                        : items[i].icon,
                                  ),
                                ),
                              ),
                            ),
                          ),
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
