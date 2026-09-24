import 'package:flutter/material.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/tv/tv.dart';

/// A tappable surface that also works from a remote and a keyboard.
///
/// On a television it is a [TvFocusable]. Everywhere else it takes focus from
/// Tab and arrow keys, answers Enter and Space, and draws a ring only when
/// focus came from a key — never under a finger.
class OnboardingTappable extends StatefulWidget {
  const OnboardingTappable({
    super.key,
    required this.child,
    required this.onTap,
    this.borderRadius = 16,
    this.autofocus = false,
    this.selected,
    this.semanticLabel,
    this.focusNode,
    this.ringColor,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double borderRadius;
  final bool autofocus;
  final bool? selected;
  final String? semanticLabel;
  final FocusNode? focusNode;
  final Color? ringColor;

  @override
  State<OnboardingTappable> createState() => _OnboardingTappableState();
}

class _OnboardingTappableState extends State<OnboardingTappable> {
  bool _highlight = false;

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (isTvPlatform) {
      body = TvFocusable(
        autofocus: widget.autofocus,
        focusNode: widget.focusNode,
        borderRadius: widget.borderRadius,
        ringColor: widget.ringColor,
        onPressed: widget.onTap,
        child: widget.child,
      );
    } else {
      body = FocusableActionDetector(
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        enabled: widget.onTap != null,
        mouseCursor: widget.onTap == null
            ? MouseCursor.defer
            : SystemMouseCursors.click,
        onShowFocusHighlight: (v) => setState(() => _highlight = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap?.call();
              return null;
            },
          ),
        },
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              border: Border.all(
                color: _highlight
                    ? (widget.ringColor ?? AppColors.textPrimary)
                    : Colors.transparent,
                width: 2.5,
              ),
            ),
            child: widget.child,
          ),
        ),
      );
    }
    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.semanticLabel,
      onTap: widget.onTap,
      excludeSemantics: widget.semanticLabel != null,
      child: body,
    );
  }
}
