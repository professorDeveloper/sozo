import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/theme/app_colors.dart';

/// Says the page is the copy saved with the downloads, not the source's.
class OfflineCopyBanner extends StatelessWidget {
  const OfflineCopyBanner({
    super.key,
    required this.message,
    this.onRetry,
    this.margin = const EdgeInsets.fromLTRB(16, 4, 16, 12),
  });

  final String message;
  final VoidCallback? onRetry;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        margin: margin,
        padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 6, 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(Icons.cloud_off_rounded, color: AppColors.primary, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'detail.offline_copy'.tr(),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            if (onRetry != null)
              TextButton(
                onPressed: onRetry,
                child: Text(
                  'general.retry'.tr(),
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
