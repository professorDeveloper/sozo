import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/theme/kaizoku_colors.dart';

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
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: KaizokuColors.neonCrimson.withValues(alpha: 0.12),
                border: Border.all(
                  color: KaizokuColors.neonCrimson.withValues(alpha: 0.25),
                  width: 1,
                ),
              ),
              child: Center(
                child: Icon(
                  filtered
                      ? Icons.filter_alt_off_outlined
                      : Icons.download_outlined,
                  size: 34,
                  color: KaizokuColors.neonCrimson,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              filtered
                  ? 'downloads.filter_empty_title'.tr()
                  : 'downloads.empty_title'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: KaizokuColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              filtered
                  ? 'downloads.filter_empty_subtitle'.tr()
                  : 'downloads.empty_subtitle'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: KaizokuColors.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            if (filtered) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: onClearFilter,
                style: FilledButton.styleFrom(
                  backgroundColor: KaizokuColors.neonCrimson.withValues(alpha: 0.15),
                  foregroundColor: KaizokuColors.neonCrimson,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text('downloads.filter_clear'.tr()),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
