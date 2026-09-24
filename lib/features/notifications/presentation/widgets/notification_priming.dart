import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/widgets/app_buttons.dart';
import 'package:soplay/features/notifications/data/services/notification_service.dart';

/// Explains what notifications are for before the system dialog asks.
///
/// Resolves to whether permission ended up granted. Already granted, it
/// returns straight away without showing anything.
Future<bool> showNotificationPriming(
  BuildContext context, {
  String? titleHint,
}) async {
  final service = getIt<NotificationService>();
  if (await service.permissionGranted) return true;
  if (!context.mounted) return false;
  final accepted = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_active_rounded,
              size: 44,
              color: AppColors.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'onboarding.notify_title'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              titleHint == null
                  ? 'onboarding.notify_body'.tr()
                  : 'onboarding.notify_body_title'.tr(args: [titleHint]),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            AppPrimaryButton(
              label: 'onboarding.notify_allow'.tr(),
              onPressed: () => Navigator.pop(ctx, true),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('onboarding.notify_later'.tr()),
            ),
          ],
        ),
      ),
    ),
  );
  if (accepted != true) return false;
  return service.requestPermission();
}
