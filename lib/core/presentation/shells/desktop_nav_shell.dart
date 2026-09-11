import 'dart:ui';
import 'package:flutter/material.dart';
import '../navigation/navigation_destination.dart';

/// Desktop presentation shell with expandable side rail, keyboard shortcuts, and hover states.
class KaizokuDesktopNavShell extends StatefulWidget {
  const KaizokuDesktopNavShell({
    super.key,
    required this.currentIndex,
    required this.onIndexChanged,
    required this.destinations,
    required this.body,
    this.initialExpanded = true,
    this.backgroundColor = const Color(0xFF0D0F14),
    this.sidebarColor = const Color(0xFF141821),
    this.activeColor = const Color(0xFFFF2A55),
    this.inactiveColor = const Color(0xFF8E95A5),
  });

  final int currentIndex;
  final ValueChanged<int> onIndexChanged;
  final List<KaizokuNavigationDestination> destinations;
  final Widget body;
  final bool initialExpanded;
  final Color backgroundColor;
  final Color sidebarColor;
  final Color activeColor;
  final Color inactiveColor;

  @override
  State<KaizokuDesktopNavShell> createState() => _KaizokuDesktopNavShellState();
}

class _KaizokuDesktopNavShellState extends State<KaizokuDesktopNavShell> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initialExpanded;
  }

  void _toggleExpanded() {
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final railWidth = _expanded ? 240.0 : 72.0;

    return Scaffold(
      backgroundColor: widget.backgroundColor,
      body: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            width: railWidth,
            decoration: BoxDecoration(
              color: widget.sidebarColor,
              border: const Border(
                right: BorderSide(color: Color(0x1AFFFFFF), width: 1),
              ),
            ),
            child: Column(
              children: [
                const SizedBox(height: 16),
                // Brand mark & toggle header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: widget.activeColor,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.local_fire_department_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                      if (_expanded) ...[
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'KAIZOKU',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                      ],
                      IconButton(
                        icon: Icon(
                          _expanded ? Icons.menu_open_rounded : Icons.menu_rounded,
                          color: widget.inactiveColor,
                          size: 20,
                        ),
                        onPressed: _toggleExpanded,
                        tooltip: _expanded ? 'Collapse sidebar' : 'Expand sidebar',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // Destination items
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    itemCount: widget.destinations.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 4),
                    itemBuilder: (context, index) {
                      return _buildDesktopNavItem(index, widget.destinations[index]);
                    },
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: widget.body),
        ],
      ),
    );
  }

  Widget _buildDesktopNavItem(int index, KaizokuNavigationDestination dest) {
    final isSelected = index == widget.currentIndex;

    final item = InkWell(
      onTap: () => widget.onIndexChanged(index),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? widget.activeColor.withAlpha(35) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: isSelected
              ? Border.all(color: widget.activeColor.withAlpha(80), width: 1)
              : null,
        ),
        child: Row(
          children: [
            IconTheme(
              data: IconThemeData(
                color: isSelected ? widget.activeColor : widget.inactiveColor,
                size: 22,
              ),
              child: isSelected ? dest.effectiveSelectedIcon : dest.icon,
            ),
            if (_expanded) ...[
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  dest.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isSelected ? Colors.white : widget.inactiveColor,
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
              if (dest.badgeCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: widget.activeColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    dest.badgeCount > 99 ? '99+' : '${dest.badgeCount}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );

    if (!_expanded && dest.tooltip != null) {
      return Tooltip(
        message: dest.tooltip ?? dest.label,
        waitDuration: const Duration(milliseconds: 300),
        child: item,
      );
    }

    return item;
  }
}
