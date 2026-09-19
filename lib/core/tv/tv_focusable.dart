import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:soplay/core/system/platform_utils.dart';
import 'package:soplay/core/theme/app_colors.dart';

import 'tv_keys.dart';

/// The focus primitive for the TV build: makes any widget reachable by a
/// D-pad, shows where focus is, and scrolls itself into view when it lands.
///
/// **Inert off TV.** When `isTvPlatform` is false this returns its child with
/// nothing but the caller's own tap handling — no `Focus`, no `AnimatedScale`,
/// no `MouseRegion`, no rebuilding state. It adds no nodes to the widget tree
/// or the focus tree, so it cannot change phone or desktop layout, hit-testing
/// or traversal.
class TvFocusable extends StatefulWidget {
  const TvFocusable({
    super.key,
    required this.child,
    this.onPressed,
    this.onLongPressed,
    this.focusNode,
    this.autofocus = false,
    this.borderRadius = 10,
    this.scale = 1.06,
    this.ringColor,
    this.ringWidth = 3,
    this.ensureVisible = true,
    this.ensureVisibleAlignment = 0.5,
    this.onFocusChange,
    this.enabled = true,
    this.focusChildren = false,
    this.behavior = HitTestBehavior.opaque,
  });

  final Widget child;

  /// Fired on DPAD_CENTER / enter / space, and on tap where a pointer exists.
  final VoidCallback? onPressed;

  /// Fired when DPAD_CENTER is held for [longPressDuration].
  final VoidCallback? onLongPressed;

  final FocusNode? focusNode;
  final bool autofocus;

  /// Matches the radius of whatever it wraps — 10 for artwork cards, 12 for
  /// surface cards — so the ring traces the content instead of boxing it.
  final double borderRadius;
  final double scale;

  /// Defaults to [AppColors.textPrimary]: ~18:1 against the app background,
  /// the strongest signal available without inventing a new colour.
  final Color? ringColor;
  final double ringWidth;

  final bool ensureVisible;

  /// 0.5 centres the item (horizontal rails); 0.3 puts it in the upper third
  /// (vertical lists, so the rows below stay visible).
  final double ensureVisibleAlignment;

  final ValueChanged<bool>? onFocusChange;
  final bool enabled;

  /// Whether the D-pad may stop on focusable widgets *inside* the child. False
  /// by default: an artwork card is one stop, not several.
  final bool focusChildren;

  final HitTestBehavior behavior;

  static const Duration longPressDuration = Duration(milliseconds: 500);

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  FocusNode? _ownNode;
  bool _focused = false;
  Timer? _longPressTimer;
  bool _longPressFired = false;

  FocusNode get _node => widget.focusNode ?? (_ownNode ??= FocusNode());

  bool get _interactive =>
      widget.enabled &&
      (widget.onPressed != null || widget.onLongPressed != null);

  @override
  void dispose() {
    _longPressTimer?.cancel();
    _ownNode?.dispose();
    super.dispose();
  }

  void _handleFocusChange(bool focused) {
    if (!mounted) return;
    if (!focused) {
      _longPressTimer?.cancel();
      _longPressTimer = null;
    }
    setState(() => _focused = focused);
    widget.onFocusChange?.call(focused);
    if (focused && widget.ensureVisible) _scrollIntoView();
  }

  /// Post-frame is required: on the first focus of a lazily-built ListView
  /// child the render object may not have a position yet.
  void _scrollIntoView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_node.hasFocus) return;
      tvEnsureVisible(context, alignment: widget.ensureVisibleAlignment);
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!_interactive) return KeyEventResult.ignored;
    if (!TvKeys.isActivate(event.logicalKey)) return KeyEventResult.ignored;

    if (event is KeyDownEvent) {
      if (widget.onLongPressed == null) {
        widget.onPressed?.call();
        return KeyEventResult.handled;
      }
      _longPressFired = false;
      _longPressTimer?.cancel();
      _longPressTimer = Timer(TvFocusable.longPressDuration, () {
        _longPressFired = true;
        widget.onLongPressed?.call();
      });
      return KeyEventResult.handled;
    }
    // Swallow auto-repeat so holding the centre button cannot fire a burst of
    // activations while the long-press timer is still running.
    if (event is KeyRepeatEvent) return KeyEventResult.handled;
    if (event is KeyUpEvent) {
      _longPressTimer?.cancel();
      _longPressTimer = null;
      if (!_longPressFired) widget.onPressed?.call();
      _longPressFired = false;
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    // Phone and desktop: exactly the caller's own gesture handling, nothing more.
    if (!isTvPlatform) {
      if (widget.onPressed == null && widget.onLongPressed == null) {
        return widget.child;
      }
      return GestureDetector(
        onTap: widget.onPressed,
        onLongPress: widget.onLongPressed,
        behavior: widget.behavior,
        child: widget.child,
      );
    }

    // TV boxes can have a pointer (mouse mode, some remotes), so keep taps too.
    final Widget tappable =
        (widget.onPressed == null && widget.onLongPressed == null)
        ? widget.child
        : GestureDetector(
            onTap: widget.onPressed,
            onLongPress: widget.onLongPressed,
            behavior: widget.behavior,
            child: widget.child,
          );

    return Focus(
      focusNode: _node,
      autofocus: widget.autofocus,
      canRequestFocus: widget.enabled,
      descendantsAreFocusable: widget.focusChildren,
      descendantsAreTraversable: widget.focusChildren,
      onKeyEvent: _onKey,
      onFocusChange: _handleFocusChange,
      child: AnimatedScale(
        scale: _focused ? widget.scale : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          // foregroundDecoration paints the ring OVER the content, so an
          // unfocused card has no permanent inset gap and the grid does not
          // reflow as focus moves. Same reasoning as the desktop hover ring.
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            border: Border.all(
              color: _focused
                  ? (widget.ringColor ?? AppColors.textPrimary)
                  : Colors.transparent,
              width: widget.ringWidth,
            ),
          ),
          child: tappable,
        ),
      ),
    );
  }
}
