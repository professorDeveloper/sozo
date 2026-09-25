import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/system/app_dates.dart';
import 'package:share_plus/share_plus.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/profile/data/backup_service.dart';
import 'package:soplay/features/profile/presentation/widgets/settings_tiles.dart';

/// Export and restore, on a screen of its own.
///
/// This was a two-row bottom sheet, which is the wrong shape for it: a sheet
/// is for a quick choice, and the question here — what is in a backup, what is
/// deliberately left out, when this device last made one — needs room to be
/// answered. Everything else Settings opens is a page; so is this.
///
/// The two halves are deliberately not symmetrical in tone. Exporting is
/// harmless and immediate. Restoring writes over live data, so it asks first
/// and then says exactly how many values it wrote — a silent "done" after a
/// restore leaves the user with no way to tell a working backup from an empty
/// one until they go looking for something that is not there.
class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  final BackupService _service = getIt<BackupService>();
  bool _busy = false;

  /// What the page is doing while busy, when it is worth saying: reinstalling
  /// sources takes long enough that a bare spinner looks like a hang.
  String? _stage;

  Future<void> _export() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final file = await _service.export();
      if (!mounted) return;
      await Share.shareXFiles([
        XFile(file.path),
      ], subject: 'backup.file_subject'.tr());
    } catch (_) {
      if (mounted) _say('backup.export_failed'.tr());
    } finally {
      // setState also refreshes the "last backup" line the export just moved.
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    if (_busy) return;
    // Asked before the picker, not after. Once a file is chosen the natural
    // expectation is that something happens, and a confirmation at that point
    // reads as an obstacle rather than a safeguard.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'backup.restore'.tr(),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'backup.restore_warning'.tr(),
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'general.cancel'.tr(),
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'backup.restore'.tr(),
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      // `FileType.any` on purpose: a .json filter is honoured inconsistently
      // across Android file providers, and the common failure is a picker that
      // greys out the very file the user just saved.
      final picked = await FilePicker.pickFiles(type: FileType.any);
      final path = picked?.files.single.path;
      if (path == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final summary = await _service.import(
        File(path),
        onExtensions: (_) {
          if (mounted) {
            setState(() => _stage = 'backup.reinstalling_sources'.tr());
          }
        },
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _stage = null;
      });
      if (!summary.ok) {
        _say(
          summary.error == 'too_new'
              ? 'backup.too_new'.tr()
              : 'backup.not_a_backup'.tr(),
        );
        return;
      }
      if (summary.extensions.reposAdded == 0 &&
          summary.extensions.pluginsInstalled == 0 &&
          summary.extensions.complete) {
        _say('backup.restored'.tr(args: ['${summary.restored}']));
      } else {
        await _report(summary);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _stage = null;
        });
        _say('backup.restore_failed'.tr());
      }
    }
  }

  /// The whole account of a restore that touched the sources: how much came
  /// back, and by name what did not — a source that silently failed to return
  /// is found only when somebody goes to read from it.
  Future<void> _report(BackupSummary summary) {
    final ext = summary.extensions;
    final lines = <String>[
      'backup.restored'.tr(args: ['${summary.restored}']),
      if (ext.reposAdded > 0)
        'backup.repos_added'.tr(args: ['${ext.reposAdded}']),
      if (ext.pluginsInstalled > 0)
        'backup.plugins_installed'.tr(args: ['${ext.pluginsInstalled}']),
      if (ext.preferencesRestored > 0)
        'backup.prefs_restored'.tr(args: ['${ext.preferencesRestored}']),
    ];
    const muted = TextStyle(color: AppColors.textSecondary, fontSize: 14);
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          ext.complete
              ? 'backup.restore_done'.tr()
              : 'backup.restore_partial'.tr(),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final l in lines) Text(l, style: muted),
              if (ext.missingSources.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'backup.missing_sources'.tr(),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(ext.missingSources.join(', '), style: muted),
              ],
              if (ext.failedRepos.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'backup.failed_repos'.tr(),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(ext.failedRepos.join('\n'), style: muted),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('general.ok'.tr()),
          ),
        ],
      ),
    );
  }

  void _say(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String _lastLine() {
    final at = _service.lastExportAt;
    if (at == null) return 'backup.never_exported'.tr();
    final stamp =
        '${AppDates.short(context, at)} '
        '${DateFormat.Hm(context.locale.toString()).format(at)}';
    return 'backup.last_export'.tr(args: [stamp]);
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPageScaffold(
      title: 'backup.title'.tr(),
      actions: [
        if (_busy)
          const Padding(
            padding: EdgeInsetsDirectional.only(end: 18),
            child: Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
      ],
      children: [
        SettingsLabel('profile.section_data'.tr()),
        SettingsCard(
          children: [
            SettingsNavTile(
              icon: Icons.ios_share_rounded,
              title: 'backup.export'.tr(),
              subtitle: 'backup.export_desc'.tr(),
              enabled: !_busy,
              onTap: _busy ? null : _export,
            ),
            const SettingsDivider(),
            SettingsNavTile(
              icon: Icons.restore_rounded,
              title: 'backup.restore'.tr(),
              subtitle: 'backup.restore_desc'.tr(),
              enabled: !_busy,
              onTap: _busy ? null : _import,
            ),
          ],
        ),
        // What a backup holds, then whether this device has one. Two notes
        // rather than a row apiece: neither is something to tap.
        if (_stage != null) SettingsFootnote(_stage!),
        SettingsFootnote('backup.subtitle'.tr()),
        SettingsFootnote(_lastLine()),
      ],
    );
  }
}
