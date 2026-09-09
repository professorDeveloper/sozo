import 'package:flutter/material.dart';
import 'package:soplay/core/theme/app_colors.dart';

/// Canonical tab strip. Styling lifted verbatim from the detail page's
/// tab bar so every feature reads the same.
///
/// Dual-mode: pass a [controller] to drive it yourself (detail keeps its own
/// controller for swipe paging), or leave it null and the widget builds an
/// internal one seeded from [selectedIndex].
class AppTabBar extends StatefulWidget implements PreferredSizeWidget {
  const AppTabBar({
    super.key,
    required this.labels,
    this.selectedIndex,
    this.onChanged,
    this.controller,
    this.isScrollable = true,
    this.showDivider = true,
    this.background,
    this.padding = const EdgeInsetsDirectional.only(start: 8),
  });

  final List<String> labels;
  final int? selectedIndex;
  final ValueChanged<int>? onChanged;
  final TabController? controller;
  final bool isScrollable;
  final bool showDivider;
  /// Defaults to [AppColors.background]. Nullable rather than defaulted in the
  /// constructor because the palette is a runtime value now, and a default
  /// parameter has to be a compile-time constant.
  final Color? background;
  /// Geometry rather than [EdgeInsets] so a caller — and the default below —
  /// can express a leading inset that mirrors in Arabic instead of clinging to
  /// the left edge.
  final EdgeInsetsGeometry padding;

  /// Public because a pinned sliver header and two skeleton placeholders all
  /// have to agree with this strip to the pixel, and each of them previously
  /// carried its own copy of the arithmetic — one of them wrong.
  static const double dividerHeight = 0.5;

  /// TabBar.preferredSize is `_kTabHeight (46) + indicatorWeight`, not
  /// kTextTabBarHeight (48) — using the latter compresses the indicator strip
  /// by 0.5px and shifts every sliver below a pinned header. Keep in sync with
  /// the [indicatorWeight] passed to the TabBar below.
  static const double indicatorWeight = 2.5;

  /// `TabBar.preferredSize` is `_kTabHeight (46) + indicatorWeight`, NOT
  /// `kTextTabBarHeight (48)`.
  static const double stripHeight = 46.0 + indicatorWeight;

  @override
  Size get preferredSize => Size.fromHeight(
    stripHeight + padding.vertical + (showDivider ? dividerHeight : 0),
  );

  @override
  State<AppTabBar> createState() => _AppTabBarState();
}

class _AppTabBarState extends State<AppTabBar>
    with SingleTickerProviderStateMixin {
  TabController? _internal;

  TabController get _c => widget.controller ?? _internal!;

  @override
  void initState() {
    super.initState();
    _ensureInternal();
    _c.addListener(_onTabChanged);
  }

  @override
  void didUpdateWidget(AppTabBar old) {
    super.didUpdateWidget(old);
    // Detach before _ensureInternal, which may dispose the old controller.
    _c.removeListener(_onTabChanged);
    _ensureInternal();
    _c.addListener(_onTabChanged);
    if (widget.controller == null &&
        widget.selectedIndex != null &&
        widget.selectedIndex != _c.index) {
      _c.index = widget.selectedIndex!;
    }
  }

  /// Builds (or rebuilds) the internal controller. A length change needs a
  /// fresh controller — TabController's length is final.
  void _ensureInternal() {
    if (widget.controller != null) {
      _internal?.dispose();
      _internal = null;
      return;
    }
    if (_internal != null && _internal!.length == widget.labels.length) return;
    final index = (widget.selectedIndex ?? _internal?.index ?? 0)
        .clamp(0, widget.labels.length - 1);
    _internal?.dispose();
    _internal = TabController(
      length: widget.labels.length,
      initialIndex: index,
      vsync: this,
    );
  }

  /// `indexIsChanging` alone is the correct guard. Adding
  /// `index != previousIndex` double-dispatches: previousIndex still holds the
  /// old value once the animation settles, so both clauses fire.
  void _onTabChanged() {
    if (!_c.indexIsChanging) widget.onChanged?.call(_c.index);
  }

  @override
  void dispose() {
    _c.removeListener(_onTabChanged);
    _internal?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: widget.background ?? AppColors.background,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: AppTabBar.stripHeight + widget.padding.vertical,
            child: Padding(
              padding: widget.padding,
              child: TabBar(
                controller: _c,
                isScrollable: widget.isScrollable,
                // TabAlignment.start asserts under isScrollable: false.
                tabAlignment: widget.isScrollable
                    ? TabAlignment.start
                    : TabAlignment.fill,
                indicatorColor: AppColors.primary,
                indicatorWeight: AppTabBar.indicatorWeight,
                indicatorSize: TabBarIndicatorSize.label,
                labelColor: AppColors.textPrimary,
                unselectedLabelColor: AppColors.textHint,
                dividerColor: Colors.transparent,
                overlayColor: WidgetStateProperty.all(Colors.transparent),
                labelPadding: const EdgeInsets.symmetric(horizontal: 14),
                padding: EdgeInsets.zero,
                labelStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
                tabs: widget.labels.map((l) => Tab(text: l)).toList(),
              ),
            ),
          ),
          if (widget.showDivider)
            Container(
              height: AppTabBar.dividerHeight,
              color: AppColors.divider.withValues(alpha: 0.55),
            ),
        ],
      ),
    );
  }
}

/// Pins an [AppTabBar] (or any [PreferredSizeWidget]) inside a CustomScrollView.
class AppTabBarHeaderDelegate extends SliverPersistentHeaderDelegate {
  const AppTabBarHeaderDelegate(this.child);

  final PreferredSizeWidget child;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      SizedBox(height: child.preferredSize.height, child: child);

  @override
  double get maxExtent => child.preferredSize.height;

  @override
  double get minExtent => child.preferredSize.height;

  /// `||` is required. With `&&` and a constant extent this is permanently
  /// false, the pinned header never rebuilds, and labels go stale on locale
  /// switch.
  @override
  bool shouldRebuild(AppTabBarHeaderDelegate old) =>
      child != old.child ||
      child.preferredSize != old.child.preferredSize;
}
