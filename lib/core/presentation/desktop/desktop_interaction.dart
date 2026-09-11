import 'package:flutter/material.dart';

/// Wraps desktop widgets with smooth cursor and elevation hover states.
class KaizokuDesktopHover extends StatefulWidget {
  const KaizokuDesktopHover({
    super.key,
    required this.child,
    this.builder,
    this.cursor = SystemMouseCursors.click,
    this.hoverScale = 1.02,
    this.duration = const Duration(milliseconds: 150),
    this.onHoverChange,
  });

  final Widget child;
  final Widget Function(BuildContext context, bool isHovered, Widget child)? builder;
  final MouseCursor cursor;
  final double hoverScale;
  final Duration duration;
  final ValueChanged<bool>? onHoverChange;

  @override
  State<KaizokuDesktopHover> createState() => _KaizokuDesktopHoverState();
}

class _KaizokuDesktopHoverState extends State<KaizokuDesktopHover> {
  bool _isHovered = false;

  void _setHovered(bool value) {
    if (_isHovered != value) {
      setState(() => _isHovered = value);
      widget.onHoverChange?.call(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = widget.builder != null
        ? widget.builder!(context, _isHovered, widget.child)
        : widget.child;

    return MouseRegion(
      cursor: widget.cursor,
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: AnimatedScale(
        scale: _isHovered ? widget.hoverScale : 1.0,
        duration: widget.duration,
        curve: Curves.easeOutCubic,
        child: content,
      ),
    );
  }
}

/// A desktop multi-column split view (e.g. left sidebar / catalog and right details).
class KaizokuDesktopSplitView extends StatelessWidget {
  const KaizokuDesktopSplitView({
    super.key,
    required this.sidebar,
    required this.content,
    this.sidebarWidth = 320.0,
    this.minSidebarWidth = 240.0,
    this.maxSidebarWidth = 480.0,
    this.divider,
  });

  final Widget sidebar;
  final Widget content;
  final double sidebarWidth;
  final double minSidebarWidth;
  final double maxSidebarWidth;
  final Widget? divider;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: sidebarWidth.clamp(minSidebarWidth, maxSidebarWidth),
          child: sidebar,
        ),
        divider ??
            const VerticalDivider(
              width: 1,
              thickness: 1,
              color: Color(0x1AFFFFFF),
            ),
        Expanded(child: content),
      ],
    );
  }
}
