import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/system/star_prompt.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/app_updater/domain/entities/app_version_check.dart';
import 'package:soplay/features/app_updater/presentation/widgets/release_notes_view.dart';
import 'package:url_launcher/url_launcher.dart';

const Color _androidAccent = Color(0xFF10B981);
const Color _iosAccent = Color(0xFF0F172A);

Future<bool?> showUpdateDialog(
  BuildContext context,
  AppVersionCheck check,
) {
  if (Platform.isIOS) {
    return showCupertinoDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _CupertinoUpdateDialog(check: check),
    );
  }
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _MaterialUpdateDialog(check: check),
  );
}

class _MaterialUpdateDialog extends StatelessWidget {
  const _MaterialUpdateDialog({required this.check});
  final AppVersionCheck check;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        'update.available_title'.tr(args: ['${check.version}']),
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            (check.releaseNotes ?? '').trim().isEmpty
                ? Text(
                    'update.available_body'.tr(),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  )
                : ReleaseNotesView(text: check.releaseNotes!, fontSize: 14),
            const SizedBox(height: 8),
            const _StarOnGitHubButton(),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            'update.later'.tr(),
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: _androidAccent),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text('update.now'.tr()),
        ),
      ],
    );
  }
}

class _CupertinoUpdateDialog extends StatelessWidget {
  const _CupertinoUpdateDialog({required this.check});
  final AppVersionCheck check;

  @override
  Widget build(BuildContext context) {
    final hasStore = check.storeUrl != null && check.storeUrl!.isNotEmpty;
    return CupertinoAlertDialog(
      title: Text('update.available_title'.tr(args: ['${check.version}'])),
      content: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            (check.releaseNotes ?? '').trim().isEmpty
                ? Text('update.available_body'.tr())
                : ReleaseNotesView(text: check.releaseNotes!, fontSize: 14),
            const SizedBox(height: 6),
            const _StarOnGitHubButton(),
          ],
        ),
      ),
      actions: [
        if (hasStore)
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('update.later'.tr()),
          ),
        if (hasStore)
          CupertinoDialogAction(
            isDefaultAction: true,
            textStyle: const TextStyle(color: _iosAccent),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('update.open_store'.tr()),
          )
        else
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('general.ok'.tr()),
          ),
      ],
    );
  }
}

class _StarOnGitHubButton extends StatelessWidget {
  const _StarOnGitHubButton();

  Future<void> _star() async {
    await StarPrompt.answered();
    try {
      await launchUrl(
        Uri.parse(AppConstants.sozoRepoUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: TextButton.icon(
        onPressed: _star,
        icon: const Icon(Icons.star_rounded, size: 16),
        label: Text('star.update_button'.tr()),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          textStyle: const TextStyle(fontSize: 12.5),
        ),
      ),
    );
  }
}
