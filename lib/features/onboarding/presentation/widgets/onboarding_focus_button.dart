import 'package:flutter/material.dart';
import 'package:soplay/core/system/platform_utils.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/theme/app_theme.dart';

/// Rings a Material button while it holds keyboard or remote focus.
///
/// A button's own focus overlay is a faint tint that reads fine at arm's
/// length and not at all from a sofa. [autofocus] focuses the first focusable
/// thing inside, for buttons that do not expose it.
class OnboardingFocusButton extends StatefulWidget {
  const OnboardingFocusButton({
    super.key,
    required this.child,
    this.autofocus = false,
    this.radius = kButtonRadius,
  });

  final Widget child;
  final bool autofocus;
  final double radius;

  @override
  State<OnboardingFocusButton> createState() => _OnboardingFocusButtonState();
}

class _OnboardingFocusButtonState extends State<OnboardingFocusButton> {
  final FocusNode _node = FocusNode(
    canRequestFocus: false,
    skipTraversal: true,
  );
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final target = _node.traversalDescendants.firstOrNull;
        target?.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyed =
        isTvPlatform ||
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    final ring = _focused && keyed;
    return Focus(
      focusNode: _node,
      onFocusChange: (f) => setState(() => _focused = f),
      child: AnimatedScale(
        scale: ring && isTvPlatform ? 1.03 : 1,
        duration: const Duration(milliseconds: 150),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius + 3),
            border: Border.all(
              color: ring ? AppColors.textPrimary : Colors.transparent,
              width: 2.5,
            ),
          ),
          padding: const EdgeInsets.all(3),
          child: widget.child,
        ),
      ),
    );
  }
}
