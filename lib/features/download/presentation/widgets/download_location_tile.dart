import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/download/domain/entities/download_location.dart';
import 'package:soplay/features/download/presentation/download_messages.dart';

/// Where the library is kept, and the way to move it.
///
/// Hidden when there is one volume — which is most phones. A settings row
/// offering a list of one is a row that teaches people the setting does
/// nothing.
class DownloadLocationTile extends StatelessWidget {
  const DownloadLocationTile({
    super.key,
    required this.locations,
    required this.current,
    required this.busy,
    required this.onPick,
  });

  final List<DownloadLocation> locations;
  final DownloadLocation? current;
  final bool busy;
  final ValueChanged<DownloadLocation> onPick;

  @override
  Widget build(BuildContext context) {
    final location = current;
    if (locations.length < 2 || location == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: busy ? null : () => _openPicker(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              children: [
                Icon(
                  location.isRemovable
                      ? Icons.sd_card_outlined
                      : Icons.smartphone_rounded,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'downloads.location'.tr(),
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        locationLabel(location),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (busy)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textSecondary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetCtx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textSecondary.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'downloads.location'.tr(),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Text(
                'downloads.location_hint'.tr(),
                style: const TextStyle(
                  color: AppColors.textHint,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
            for (final option in locations)
              ListTile(
                leading: Icon(
                  option.isRemovable
                      ? Icons.sd_card_outlined
                      : Icons.smartphone_rounded,
                  color: AppColors.textSecondary,
                ),
                title: Text(
                  locationLabel(option),
                  style: const TextStyle(color: AppColors.textPrimary),
                ),
                subtitle: Text(
                  option.freeBytes > 0
                      ? 'downloads.storage_free'
                          .tr(args: [formatBytes(option.freeBytes)])
                      : option.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textHint,
                    fontSize: 12,
                  ),
                ),
                trailing: option.path == current?.path
                    ? const Icon(Icons.check_rounded, color: AppColors.success)
                    : null,
                onTap: option.path == current?.path
                    ? null
                    : () {
                        Navigator.of(sheetCtx).pop();
                        onPick(option);
                      },
              ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}
