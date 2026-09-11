import 'dart:ui';
import 'package:flutter/material.dart';
import '../../theme/kaizoku_colors.dart';
import '../../theme/kaizoku_typography.dart';

enum KaizokuBadgeVariant {
  primary,
  amber,
  cyan,
  glass,
  live,
}

/// Frosted capsule badge for quality indicators (4K, HDR), status, and counters.
class KaizokuBadge extends StatelessWidget {
  const KaizokuBadge({
    super.key,
    required this.label,
    this.variant = KaizokuBadgeVariant.glass,
    this.icon,
    this.padding = const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
  });

  final String label;
  final KaizokuBadgeVariant variant;
  final IconData? icon;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    Color textColor;
    Border? border;

    switch (variant) {
      case KaizokuBadgeVariant.primary:
        bgColor = KaizokuColors.crimson;
        textColor = Colors.white;
        break;
      case KaizokuBadgeVariant.amber:
        bgColor = KaizokuColors.amber;
        textColor = Colors.black;
        break;
      case KaizokuBadgeVariant.cyan:
        bgColor = KaizokuColors.cyan;
        textColor = Colors.black;
        break;
      case KaizokuBadgeVariant.live:
        bgColor = const Color(0xFFE50914);
        textColor = Colors.white;
        break;
      case KaizokuBadgeVariant.glass:
        bgColor = const Color(0x990D0F14);
        textColor = KaizokuColors.textHigh;
        border = Border.all(color: const Color(0x33FFFFFF), width: 0.8);
        break;
    }

    Widget content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: border,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (variant == KaizokuBadgeVariant.live) ...[
            Container(
              width: 5,
              height: 5,
              margin: const EdgeInsets.only(right: 4),
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ] else if (icon != null) ...[
            Icon(icon, size: 10, color: textColor),
            const SizedBox(width: 3),
          ],
          Text(
            label.toUpperCase(),
            style: KaizokuTypography.badgeMobile.copyWith(
              color: textColor,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );

    if (variant == KaizokuBadgeVariant.glass) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: content,
        ),
      );
    }

    return content;
  }
}
