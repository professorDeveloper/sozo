import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/system/app_dates.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/automation/data/automation_settings.dart';
import 'package:soplay/features/profile/presentation/widgets/settings_tiles.dart';
import 'package:soplay/features/tracker/data/follow_service.dart';
import 'package:soplay/features/tracker/data/library_update_scheduler.dart';

/// Settings → Automation: what the app does without being asked.
class AutomationSettingsPage extends StatelessWidget {
  const AutomationSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = getIt<AutomationSettings>();
    return ValueListenableBuilder<int>(
      valueListenable: settings.revision,
      builder: (context, _, _) => _AutomationBody(settings: settings),
    );
  }
}

class _AutomationBody extends StatefulWidget {
  const _AutomationBody({required this.settings});

  final AutomationSettings settings;

  @override
  State<_AutomationBody> createState() => _AutomationBodyState();
}

class _AutomationBodyState extends State<_AutomationBody> {
  AutomationSettings get settings => widget.settings;

  static String _bytesLabel(int bytes) => bytes <= 0
      ? 'automation.no_limit'.tr()
      : 'automation.gb'.tr(args: ['${bytes ~/ (1024 * 1024 * 1024)}']);

  static String _secondsLabel(int s) =>
      s <= 0 ? 'general.off'.tr() : 'automation.seconds'.tr(args: ['$s']);

  String _status(BuildContext context) {
    final status = settings.lastStatus;
    if (status == null) return 'automation.status_never'.tr();
    final at =
        '${AppDates.short(context, status.at)} '
        '${DateFormat.Hm(context.locale.toString()).format(status.at)}';
    final lines = <String>[
      status.queued > 0
          ? 'automation.status_queued'.tr(args: [at, '${status.queued}'])
          : 'automation.status_nothing'.tr(args: [at]),
      switch (status.hold) {
        AutoDownloadHold.wifi => 'automation.hold_wifi'.tr(),
        AutoDownloadHold.storageCap => 'automation.hold_cap'.tr(),
        AutoDownloadHold.busy => 'automation.hold_busy'.tr(),
        AutoDownloadHold.none => '',
      },
      if (status.skipped > 0)
        'automation.skipped_n'.tr(args: ['${status.skipped}']),
    ].where((l) => l.isNotEmpty);
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final auto = settings.autoDownloadEnabled;
    final titlesOn = getIt<FollowService>()
        .list()
        .where((t) => t.autoDownload)
        .length;
    final checksOff = getIt<LibraryUpdateScheduler>().intervalHours <= 0;

    return SettingsPageScaffold(
      title: 'automation.title'.tr(),
      children: [
        SettingsLabel('automation.section_downloads'.tr()),
        SettingsCard(
          children: [
            SettingsSwitchTile(
              icon: Icons.download_for_offline_outlined,
              title: 'automation.auto_download'.tr(),
              subtitle: 'automation.auto_download_desc'.tr(),
              value: auto,
              onChanged: settings.setAutoDownloadEnabled,
            ),
            const SettingsDivider(),
            SettingsSwitchTile(
              icon: Icons.wifi_rounded,
              title: 'automation.wifi_only'.tr(),
              subtitle: 'automation.wifi_only_desc'.tr(),
              value: settings.autoDownloadWifiOnly,
              enabled: auto,
              onChanged: settings.setAutoDownloadWifiOnly,
            ),
            const SettingsDivider(),
            SettingsDropdownTile<int>(
              icon: Icons.layers_outlined,
              title: 'automation.keep_last'.tr(),
              value: settings.keepLast,
              options: AutomationSettings.keepLastChoices,
              labelOf: (n) => 'automation.keep_last_value'.tr(args: ['$n']),
              enabled: auto,
              onChanged: settings.setKeepLast,
            ),
            const SettingsDivider(),
            SettingsDropdownTile<int>(
              icon: Icons.sd_storage_outlined,
              title: 'automation.storage_cap'.tr(),
              subtitle: 'automation.storage_cap_desc'.tr(),
              value: settings.maxBytes,
              options: AutomationSettings.maxBytesChoices,
              labelOf: _bytesLabel,
              enabled: auto,
              onChanged: settings.setMaxBytes,
            ),
            const SettingsDivider(),
            SettingsNavTile(
              icon: Icons.bookmarks_outlined,
              title: 'automation.titles'.tr(),
              subtitle: 'automation.titles_desc'.tr(),
              value: 'automation.titles_value'.tr(args: ['$titlesOn']),
              valueColor: titlesOn > 0 ? AppColors.primary : null,
              enabled: auto,
              onTap: () async {
                // Titles are switched on there; the count here follows.
                await context.push('/following');
                if (mounted) setState(() {});
              },
            ),
          ],
        ),
        if (auto && checksOff)
          SettingsFootnote('automation.library_off'.tr())
        else if (auto)
          SettingsFootnote(_status(context)),
        const SizedBox(height: 20),
        SettingsLabel('automation.section_cleanup'.tr()),
        SettingsCard(
          children: [
            SettingsSwitchTile(
              icon: Icons.auto_delete_outlined,
              title: 'automation.delete_watched'.tr(),
              subtitle: 'automation.delete_watched_desc'.tr(),
              value: settings.autoDeleteWatched,
              onChanged: settings.setAutoDeleteWatched,
            ),
          ],
        ),
        const SizedBox(height: 20),
        SettingsLabel('automation.section_playback'.tr()),
        SettingsCard(
          children: [
            SettingsSwitchTile(
              icon: Icons.fast_forward_outlined,
              title: 'automation.prefetch_episode'.tr(),
              subtitle: 'automation.prefetch_episode_desc'.tr(),
              value: settings.prefetchNextEpisode,
              onChanged: settings.setPrefetchNextEpisode,
            ),
            const SettingsDivider(),
            SettingsDropdownTile<int>(
              icon: Icons.timer_outlined,
              title: 'automation.up_next_prompt'.tr(),
              subtitle: 'automation.up_next_prompt_desc'.tr(),
              value: settings.upNextSeconds,
              options: AutomationSettings.upNextChoices,
              labelOf: _secondsLabel,
              onChanged: settings.setUpNextSeconds,
            ),
            const SettingsDivider(),
            SettingsSwitchTile(
              icon: Icons.menu_book_outlined,
              title: 'automation.prefetch_chapter'.tr(),
              subtitle: 'automation.prefetch_chapter_desc'.tr(),
              value: settings.prefetchNextChapter,
              onChanged: settings.setPrefetchNextChapter,
            ),
          ],
        ),
      ],
    );
  }
}
