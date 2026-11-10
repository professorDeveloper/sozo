import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/theme/app_colors.dart';

/// "Couldn't load more · Retry", where a paged grid's bottom spinner was.
class LoadMoreFailedFooter extends StatelessWidget {
  const LoadMoreFailedFooter({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              'general.load_more_failed'.tr(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textHint, fontSize: 13),
            ),
          ),
          const Text(
            ' · ',
            style: TextStyle(color: AppColors.textHint, fontSize: 13),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(48, 40),
            ),
            child: Text('general.retry'.tr()),
          ),
        ],
      ),
    );
  }
}
