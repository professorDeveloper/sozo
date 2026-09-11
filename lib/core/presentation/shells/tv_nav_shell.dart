import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../navigation/navigation_destination.dart';
import '../tv/tv_focus_node.dart';

/// 10-foot UI TV presentation shell with D-pad focus restoration and directional traversal.
class KaizokuTvNavShell extends StatefulWidget {
  const KaizokuTvNavShell({
    super.key,
    required this.currentIndex,
    required this.onIndexChanged,
    required this.destinations,
    required this.body,
    this.backgroundColor = const Color(0xFF090A0F),
    this.railColor = const Color(0xFF10121A),
    this.activeColor = const Color(0xFFFF2A55),
    this.inactiveColor = const Color(0xFF8E95A5),
  });

  final int currentIndex;
  final ValueChanged<int> onIndexChanged;
  final List<KaizokuNavigationDestination> destinations;
  final Widget body;
  final Color backgroundColor;
  final Color railColor;
  final Color activeColor;
  final Color inactiveColor;

  @override
  State<KaizokuTvNavShell> createState() => _KaizokuTvNavShellState();
}

class _KaizokuTvNavShellState extends State<KaizokuTvNavShell> {
  final FocusScopeNode _railScope = FocusScopeNode(debugLabel: 'KaizokuTvRailScope');
  final FocusScopeNode _contentScope = FocusScopeNode(debugLabel: 'KaizokuTvContentScope');
  late final List<FocusNode> _itemNodes;
  bool _isContentFocused = false;

  @override
  void initState() {
    super.initState();
    _itemNodes = List.generate(
      widget.destinations.length,
      (i) => FocusNode(debugLabel: 'tvRailItem_$i'),
    );
    _contentScope.addListener(_handleContentFocusChange);
  }

  @override
  void dispose() {
    _contentScope.removeListener(_handleContentFocusChange);
    _railScope.dispose();
    _contentScope.dispose();
    for (final node in _itemNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _handleContentFocusChange() {
    final hasFocus = _contentScope.hasFocus;
    if (_isContentFocused != hasFocus) {
      setState(() => _isContentFocused = hasFocus);
    }
  }

  void _restoreRailFocus() {
    if (widget.currentIndex >= 0 && widget.currentIndex < _itemNodes.length) {
      _itemNodes[widget.currentIndex].requestFocus();
    } else {
      _railScope.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isContentFocused,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isContentFocused) {
          // BACK pressed while browsing content: return focus to rail
          _restoreRailFocus();
        }
      },
      child: Scaffold(
        backgroundColor: widget.backgroundColor,
        body: Row(
          children: [
            // TV Left Navigation Rail
            FocusScope(
              node: _railScope,
              child: Container(
                width: 220,
                decoration: BoxDecoration(
                  color: widget.railColor,
                  border: const Border(
                    right: BorderSide(color: Color(0x1AFFFFFF), width: 1.5),
                  ),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 32),
                    // TV App Logo
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: widget.activeColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.local_fire_department_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'KAIZOKU',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2.0,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 36),
                    // TV Navigation Destinations (10-foot scale)
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        itemCount: widget.destinations.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          return _buildTvRailItem(index, widget.destinations[index]);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // TV Main Content Area
            Expanded(
              child: FocusScope(
                node: _contentScope,
                child: widget.body,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTvRailItem(int index, KaizokuNavigationDestination dest) {
    final isSelected = index == widget.currentIndex;

    return KaizokuTvFocusable(
      focusNode: _itemNodes[index],
      autofocus: index == 0,
      scaleFactor: 1.04,
      borderRadius: BorderRadius.circular(12),
      focusColor: widget.activeColor,
      onTap: () {
        widget.onIndexChanged(index);
      },
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: isSelected ? widget.activeColor.withAlpha(40) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            IconTheme(
              data: IconThemeData(
                color: isSelected ? widget.activeColor : widget.inactiveColor,
                size: 26,
              ),
              child: isSelected ? dest.effectiveSelectedIcon : dest.icon,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                dest.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isSelected ? Colors.white : widget.inactiveColor,
                  fontSize: 16,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                ),
              ),
            ),
            if (dest.badgeCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: widget.activeColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${dest.badgeCount}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
