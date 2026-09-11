import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:soplay/core/system/platform_utils.dart';

/// TV focus callback definition.
typedef TvFocusChangeCallback = void Function(bool hasFocus);

/// Wraps any widget with deterministic 10-foot Android TV focus behavior:
/// - Distinctive glowing border ring on focus
/// - Smooth scale magnification transition (1.0 -> 1.05)
/// - Auto-scroll into viewport when receiving focus
/// - Handles D-pad Center / Enter / Space keys for selection
class KaizokuTvFocusable extends StatefulWidget {
  const KaizokuTvFocusable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.onFocusChange,
    this.focusNode,
    this.autofocus = false,
    this.scaleFactor = 1.05,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.focusColor,
    this.glowColor,
    this.padding = EdgeInsets.zero,
    this.canRequestFocus = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final TvFocusChangeCallback? onFocusChange;
  final FocusNode? focusNode;
  final bool autofocus;
  final double scaleFactor;
  final BorderRadius borderRadius;
  final Color? focusColor;
  final Color? glowColor;
  final EdgeInsetsGeometry padding;
  final bool canRequestFocus;

  @override
  State<KaizokuTvFocusable> createState() => _KaizokuTvFocusableState();
}

class _KaizokuTvFocusableState extends State<KaizokuTvFocusable> {
  late FocusNode _effectiveFocusNode;
  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    _effectiveFocusNode = widget.focusNode ?? FocusNode();
    _effectiveFocusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(KaizokuTvFocusable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusNode != oldWidget.focusNode) {
      oldWidget.focusNode?.removeListener(_handleFocusChange);
      _effectiveFocusNode = widget.focusNode ?? FocusNode();
      _effectiveFocusNode.addListener(_handleFocusChange);
    }
  }

  @override
  void dispose() {
    _effectiveFocusNode.removeListener(_handleFocusChange);
    if (widget.focusNode == null) {
      _effectiveFocusNode.dispose();
    }
    super.dispose();
  }

  void _handleFocusChange() {
    final hasFocus = _effectiveFocusNode.hasFocus;
    if (_hasFocus != hasFocus) {
      setState(() {
        _hasFocus = hasFocus;
      });
      widget.onFocusChange?.call(hasFocus);

      if (hasFocus && mounted) {
        // Auto-scroll focused item into view if in a Scrollable
        Scrollable.ensureVisible(
          context,
          alignment: 0.5,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
        );
        if (isTvPlatform) {
          HapticFeedback.selectionClick();
        }
      }
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      if (event.logicalKey == LogicalKeyboardKey.select ||
          event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter ||
          event.logicalKey == LogicalKeyboardKey.gameButtonA) {
        widget.onTap?.call();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeFocusColor = widget.focusColor ?? theme.colorScheme.primary;
    final activeGlowColor = widget.glowColor ?? activeFocusColor.withAlpha(80);

    return Focus(
      focusNode: _effectiveFocusNode,
      autofocus: widget.autofocus,
      canRequestFocus: widget.canRequestFocus,
      onKeyEvent: _handleKeyEvent,
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: _hasFocus ? widget.scaleFactor : 1.0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: widget.padding,
            decoration: BoxDecoration(
              borderRadius: widget.borderRadius,
              boxShadow: _hasFocus
                  ? [
                      BoxShadow(
                        color: activeGlowColor,
                        blurRadius: 14,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
              border: Border.all(
                color: _hasFocus ? activeFocusColor : Colors.transparent,
                width: _hasFocus ? 2.5 : 0.0,
              ),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
