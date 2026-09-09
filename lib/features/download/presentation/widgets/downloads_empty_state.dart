import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/theme/app_colors.dart';

/// Nothing to show — and which of the two reasons it is.
///
/// "No downloads yet" over a library of twelve, hidden by a filter, is the
/// kind of message that makes somebody think the app lost their files.
class DownloadsEmptyState extends StatelessWidget {
  const DownloadsEmptyState({
    super.key,
    required this.filtered,
    required this.onClearFilter,
  });

  final bool filtered;
  final VoidCallback onClearFilter;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              filtered
                  ? Icons.filter_alt_off_outlined
                  : Icons.download_outlined,
              size: 46,
              color: AppColors.textHint,
            ),
            const SizedBox(height: 14),
            Text(
              filtered
                  ? 'downloads.filter_empty_title'.tr()
                  : 'downloads.empty_title'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              filtered
                  ? 'downloads.filter_empty_subtitle'.tr()
                  : 'downloads.empty_subtitle'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            if (filtered) ...[
              const SizedBox(height: 14),
              TextButton(
                onPressed: onClearFilter,
                child: Text('downloads.filter_clear'.tr()),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
