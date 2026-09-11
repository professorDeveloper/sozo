import 'dart:ui';
import 'package:flutter/material.dart';
import '../navigation/navigation_destination.dart';

/// Mobile presentation shell with ergonomic bottom navigation and safe-area padding.
class KaizokuMobileNavShell extends StatelessWidget {
  const KaizokuMobileNavShell({
    super.key,
    required this.currentIndex,
    required this.onIndexChanged,
    required this.destinations,
    required this.body,
    this.backgroundColor = const Color(0xFF0D0F14),
    this.bottomBarColor = const Color(0xE6141821),
    this.activeColor = const Color(0xFFFF2A55),
    this.inactiveColor = const Color(0xFF8E95A5),
  });

  final int currentIndex;
  final ValueChanged<int> onIndexChanged;
  final List<KaizokuNavigationDestination> destinations;
  final Widget body;
  final Color backgroundColor;
  final Color bottomBarColor;
  final Color activeColor;
  final Color inactiveColor;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: body,
      bottomNavigationBar: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            decoration: BoxDecoration(
              color: bottomBarColor,
              border: const Border(
                top: BorderSide(color: Color(0x1AFFFFFF), width: 1),
              ),
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: 64,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    for (int i = 0; i < destinations.length; i++)
                      _buildNavItem(context, i, destinations[i]),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context,
    int index,
    KaizokuNavigationDestination dest,
  ) {
    final isSelected = index == currentIndex;
    final color = isSelected ? activeColor : inactiveColor;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onIndexChanged(index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                IconTheme(
                  data: IconThemeData(color: color, size: 24),
                  child: isSelected ? dest.effectiveSelectedIcon : dest.icon,
                ),
                if (dest.badgeCount > 0)
                  Positioned(
                    top: -4,
                    right: -6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: activeColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                      child: Text(
                        dest.badgeCount > 99 ? '99+' : '${dest.badgeCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              dest.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
