import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/detail/domain/entities/source_notice.dart';

/// What the source said about this title, and the one thing worth doing next.
///
/// The failure this replaces was a snackbar reading "Video URL aniqlanmadi":
/// true in the narrowest sense, useless to the person holding the phone, and
/// identical for every reason a title will not play. A viewer who has been told
/// that the source moved this film into its own app knows the title is not
/// broken and that Sozo is not broken — and the sheet then offers the step they
/// would otherwise have had to work out themselves, which is to look for the
/// same title on another source.
///
/// The offer leans on machinery that already exists: `AlternateSourceSheet`
/// searches every other installed source for the title and hands back something
/// playable. Nothing new is built here.
Future<void> showSourceNoticeSheet(
  BuildContext context, {
  required SourceNotice notice,
  required VoidCallback onFindOther,
}) {
  return showAdaptiveModal<void>(
    context: context,
    backgroundColor: AppColors.background,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _SourceNoticeSheet(notice: notice, onFindOther: onFindOther),
  );
}

class _SourceNoticeSheet extends StatelessWidget {
  const _SourceNoticeSheet({required this.notice, required this.onFindOther});

  final SourceNotice notice;
  final VoidCallback onFindOther;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textSecondary.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    notice == SourceNotice.isSeries
                        ? Icons.playlist_play_rounded
                        : Icons.movie_filter_outlined,
                    color: AppColors.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'detail.notice_title'.tr(),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              notice.messageKey.tr(),
              style: const TextStyle(
                fontSize: 14,
                height: 1.45,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  // Closed first: the alternate-source search opens its own
                  // sheet, and two stacked over the page leaves the viewer
                  // dismissing this one after they have already moved on.
                  Navigator.of(context).pop();
                  onFindOther();
                },
                icon: const Icon(Icons.travel_explore_rounded, size: 20),
                label: Text('detail.find_other_sources'.tr()),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'general.close'.tr(),
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
