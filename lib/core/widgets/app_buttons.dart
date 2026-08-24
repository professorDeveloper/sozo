import 'package:flutter/material.dart';

import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/theme/app_theme.dart';

/// The app's primary call to action.
///
/// This is the button the onboarding and auth screens always used, lifted out
/// of `features/auth` so the rest of the app can use the same one instead of
/// hand-rolling a container with a colour and a radius. Its metrics come from
/// [kButtonHeight] / [kButtonRadius] and the shared `elevatedButtonTheme`, so
/// it and every plain `ElevatedButton` in the app are the same object.
///
/// [loading] swaps the label for a spinner *without* changing the button's size,
/// so a form does not jump when it is submitted.
class AppPrimaryButton extends StatelessWidget {
  const AppPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;

  /// Full width (a form's submit) vs. hugging its label (a row of actions).
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final glyph = icon;
    final child = loading
        ? SizedBox(
            width: 21,
            height: 21,
            child: CircularProgressIndicator(
              color: AppColors.onPrimary,
              strokeWidth: 2.2,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (glyph != null) ...[
                Icon(glyph, size: 19),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );

    return SizedBox(
      height: kButtonHeight,
      width: expand ? double.infinity : null,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: expand
            ? null
            : ElevatedButton.styleFrom(
                minimumSize: const Size(0, kButtonHeight),
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
        child: child,
      ),
    );
  }
}

/// The quieter partner to [AppPrimaryButton] — same height and radius, an
/// outline instead of a fill. For the "not now" beside a "continue".
class AppSecondaryButton extends StatelessWidget {
  const AppSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final glyph = icon;
    return SizedBox(
      height: kButtonHeight,
      width: expand ? double.infinity : null,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, kButtonHeight),
          padding: EdgeInsets.symmetric(horizontal: expand ? 16 : 20),
          side: BorderSide(
            color: AppColors.textPrimary.withValues(alpha: 0.22),
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (glyph != null) ...[
              Icon(glyph, size: 19),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}
