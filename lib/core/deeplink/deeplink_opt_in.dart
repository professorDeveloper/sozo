import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/theme/app_theme.dart';

import 'deeplink_settings.dart';

class DeeplinkOptIn {
  DeeplinkOptIn._();

  static Future<void> maybePrompt(BuildContext context) async {
    final hive = getIt<HiveService>();
    if (hive.hasDeeplinkPromptSeen) return;
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!context.mounted) return;
    await _show(context, persistDecision: true);
  }

  static Future<void> showManually(BuildContext context) =>
      _show(context, persistDecision: false);

  static Future<void> _show(
    BuildContext context, {
    required bool persistDecision,
  }) async {
    final hive = getIt<HiveService>();
    final result = await showAdaptiveModal<_OptInResult>(
      context: context,
      backgroundColor: AppColors.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => const _OptInSheet(),
    );
    if (persistDecision) {
      await hive.markDeeplinkPromptSeen();
    }
    if (result == null) return;
    await hive.setDeeplinkOptIn(result == _OptInResult.enable);
    if (result == _OptInResult.enable) {
      await DeeplinkSettings.openDefaultLinksSettings();
    }
  }
}

enum _OptInResult { enable, skip }

class _OptInSheet extends StatelessWidget {
  const _OptInSheet();

  @override
  Widget build(BuildContext context) {
    final isIos = Platform.isIOS;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textSecondary.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.link_rounded,
                size: 28,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'deeplink.opt_in_title'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isIos
                  ? 'deeplink.opt_in_body_ios'.tr()
                  : 'deeplink.opt_in_body_android'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(kButtonRadius),
                ),
              ),
              onPressed: () =>
                  Navigator.of(context).pop(_OptInResult.enable),
              child: Text(
                'deeplink.opt_in_enable'.tr(),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(_OptInResult.skip),
              child: Text(
                'deeplink.opt_in_later'.tr(),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
