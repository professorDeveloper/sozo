import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/download/domain/entities/storage_usage.dart';
import 'package:soplay/features/download/presentation/download_messages.dart';

/// What the library costs, and what is left.
///
/// Downloads are the one thing in the app that can fill a phone, and this was
/// the one screen that never said how much they had taken — "Clear all" was
/// the only control, which is not a decision anybody can make without a
/// number.
class DownloadsStorageHeader extends StatelessWidget {
  const DownloadsStorageHeader({
    super.key,
    required this.usage,
    required this.busy,
    required this.onSweep,
  });

  final StorageUsage usage;
  final bool busy;
  final VoidCallback onSweep;

  @override
  Widget build(BuildContext context) {
    // The bar is meaningless without both halves; with only one it would be a
    // full bar or an empty one regardless of the device.
    final total = usage.usedBytes + usage.freeBytes;
    final fraction = total > 0 ? usage.usedBytes / total : null;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.sd_storage_outlined,
                size: 18,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'downloads.storage_used'.tr(
                    args: [formatBytes(usage.usedBytes)],
                  ),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (usage.freeBytes > 0)
                Text(
                  'downloads.storage_free'.tr(
                    args: [formatBytes(usage.freeBytes)],
                  ),
                  style: const TextStyle(
                    color: AppColors.textHint,
                    fontSize: 11.5,
                  ),
                ),
            ],
          ),
          if (fraction != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: fraction.clamp(0.0, 1.0),
                minHeight: 4,
                backgroundColor: AppColors.divider,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
          ],
          // Only when there is something to reclaim. A permanently visible
          // "clean up" row on a screen with nothing to clean up is a button
          // that teaches people it does nothing.
          if (usage.hasOrphans) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'downloads.orphans_found'.tr(
                      args: [formatBytes(usage.orphanBytes)],
                    ),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                TextButton(
                  onPressed: busy ? null : onSweep,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 34),
                  ),
                  child: busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child:
                              CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text('downloads.orphans_clean'.tr()),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
