import 'dart:ui';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/theme/app_theme.dart';

/// The app's shipped empty / error panel, lifted out of the cast picker so every
/// Buff surface says "there is nothing here" in exactly one voice.
///
/// Geometry is the one measured off `my_list_state_views.dart`: ClipRRect radius
/// 24 over a blur-20 backdrop, fill white@0.06, border white@0.09, padding
/// h24 v28, a 64px icon circle, title 18/w800, body 13/h1.5, button h46.
/// [onAction] is optional — a state nobody can retry out of (no approved clips
/// yet) must not offer a button that changes nothing.
class BuffEmptyPanel extends StatelessWidget {
  const BuffEmptyPanel({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? body;

  /// Defaults to `general.retry` when [onAction] is supplied.
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final text = body;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              BuffIconCircle(icon: icon),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              if (text != null && text.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ],
              if (onAction != null) ...[
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    onPressed: onAction,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(kButtonRadius),
                      ),
                    ),
                    child: Text(
                      actionLabel ?? 'general.retry'.tr(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The 64px accent disc from the shipped empty-state panel — the one place the
/// brand colour is allowed as a soft radial, on glass.
class BuffIconCircle extends StatelessWidget {
  const BuffIconCircle({super.key, required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.22),
            AppColors.primary.withValues(alpha: 0.06),
          ],
        ),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.22)),
      ),
      child: Icon(icon, color: AppColors.primaryLight, size: 30),
    );
  }
}
