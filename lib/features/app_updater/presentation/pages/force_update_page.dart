import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/theme/app_theme.dart';
import 'package:soplay/features/app_updater/domain/entities/app_version_check.dart';
import 'package:soplay/features/app_updater/presentation/widgets/release_notes_view.dart';

const Color _androidAccent = Color(0xFF10B981);
const Color _iosAccent = Color(0xFF0F172A);

class ForceUpdatePage extends StatelessWidget {
  const ForceUpdatePage({
    super.key,
    required this.check,
    required this.onUpdate,
  });

  final AppVersionCheck check;
  final Future<void> Function(BuildContext context) onUpdate;

  @override
  Widget build(BuildContext context) {
    final accent = Platform.isIOS ? _iosAccent : _androidAccent;
    final hasAction = Platform.isAndroid ||
        (check.storeUrl != null && check.storeUrl!.isNotEmpty);
    final actionLabel = Platform.isIOS ? 'Open in App Store' : 'Update';

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: Column(
              children: [
                const Spacer(),
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.system_update_alt,
                    color: accent,
                    size: 44,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Update required',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Please install the new version (v${check.version}) to continue using the app.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                if ((check.releaseNotes ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ReleaseNotesView(
                      text: check.releaseNotes!,
                      fontSize: 13,
                    ),
                  ),
                ],
                const Spacer(),
                if (hasAction)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(kButtonRadius),
                        ),
                      ),
                      onPressed: () => onUpdate(context),
                      child: Text(
                        actionLabel,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => SystemNavigator.pop(),
                  child: const Text(
                    'Exit app',
                    style: TextStyle(color: AppColors.textHint),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
