import 'dart:ui' show ImageFilter;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/comments/domain/spoiler_rules.dart';

/// A comment blurred behind "tap to reveal" unless [visibility] says it can
/// show. Focusable, so a remote can reveal it too.
class SpoilerGate extends StatelessWidget {
  const SpoilerGate({
    super.key,
    required this.visibility,
    required this.onReveal,
    required this.child,
  });

  final SpoilerVisibility visibility;
  final VoidCallback onReveal;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (visibility == SpoilerVisibility.visible) return child;
    final label = visibility == SpoilerVisibility.spoiler
        ? 'comments.spoiler_hidden'.tr()
        : 'comments.unwatched_hidden'.tr();
    return Stack(
      children: [
        ExcludeSemantics(
          child: IgnorePointer(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
              child: child,
            ),
          ),
        ),
        Positioned.fill(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onReveal,
              focusColor: AppColors.primary.withValues(alpha: 0.18),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border, width: 0.6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.visibility_off_rounded,
                        size: 14,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
