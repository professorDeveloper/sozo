import 'package:flutter/material.dart';
import '../../theme/kaizoku_colors.dart';

enum KaizokuButtonVariant {
  primary,
  secondary,
  outline,
  ghost,
}

/// Tactile, responsive button component styled for Kaizoku.
class KaizokuButton extends StatelessWidget {
  const KaizokuButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = KaizokuButtonVariant.primary,
    this.icon,
    this.loading = false,
    this.fullWidth = false,
    this.height = 46.0,
    this.borderRadius = const BorderRadius.all(Radius.circular(10)),
  });

  final String label;
  final VoidCallback? onPressed;
  final KaizokuButtonVariant variant;
  final IconData? icon;
  final bool loading;
  final bool fullWidth;
  final double height;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    Color fgColor;
    Border? border;

    switch (variant) {
      case KaizokuButtonVariant.primary:
        bgColor = KaizokuColors.crimson;
        fgColor = Colors.white;
        break;
      case KaizokuButtonVariant.secondary:
        bgColor = KaizokuColors.surfaceElevated;
        fgColor = KaizokuColors.textHigh;
        border = Border.all(color: KaizokuColors.borderSubtle, width: 1);
        break;
      case KaizokuButtonVariant.outline:
        bgColor = Colors.transparent;
        fgColor = KaizokuColors.crimson;
        border = Border.all(color: KaizokuColors.crimson, width: 1.5);
        break;
      case KaizokuButtonVariant.ghost:
        bgColor = Colors.transparent;
        fgColor = KaizokuColors.textMedium;
        break;
    }

    Widget content = SizedBox(
      height: height,
      child: Material(
        color: bgColor,
        borderRadius: borderRadius,
        child: InkWell(
          onTap: loading ? null : onPressed,
          borderRadius: borderRadius,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              border: border,
            ),
            child: Center(
              child: loading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(fgColor),
                      ),
                    )
                  : Row(
                      mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (icon != null) ...[
                          Icon(icon, size: 18, color: fgColor),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          label,
                          style: TextStyle(
                            color: fgColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );

    return fullWidth ? SizedBox(width: double.infinity, child: content) : content;
  }
}
