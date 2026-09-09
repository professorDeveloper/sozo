import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/features/download/domain/usecases/get_downloads_usecase.dart';
import 'package:soplay/features/history/data/history_service.dart';
import 'package:soplay/features/profile/presentation/widgets/settings_tiles.dart';
import 'package:soplay/features/stats/presentation/watch_stats_page.dart';
import 'package:soplay/features/tracker/data/follow_service.dart';

/// The record the app keeps on its own: what was watched, what was saved to
/// the device, what is being followed, and the totals over all of it.
///
/// Split out of Library, which now holds only the lists the viewer curates by
/// hand. The line between them is who wrote the entry.
class ActivityPage extends StatefulWidget {
  const ActivityPage({super.key});

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage> {
  final HistoryService _history = getIt<HistoryService>();
  final GetDownloadsUseCase _downloads = getIt<GetDownloadsUseCase>();

  @override
  void initState() {
    super.initState();
    _history.revision.addListener(_onChange);
    _downloads.revision.addListener(_onChange);
  }

  @override
  void dispose() {
    _history.revision.removeListener(_onChange);
    _downloads.revision.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final following = getIt<FollowService>().list().length;
    return SettingsPageScaffold(
      title: 'profile.activity'.tr(),
      children: [
        SettingsLabel(
          'profile.section_activity'.tr(),
          featureIds: const ['stats'],
        ),
        SettingsCard(
          children: [
            SettingsNavTile(
              icon: Icons.history_rounded,
              title: 'profile.watch_history'.tr(),
              value: countLabel(_history.getAll().length),
              onTap: () => context.push('/history'),
            ),
            const SettingsDivider(),
            SettingsNavTile(
              icon: Icons.download_rounded,
              title: 'profile.downloads'.tr(),
              value: countLabel(_downloads().length),
              onTap: () => context.push('/downloads'),
            ),
            const SettingsDivider(),
            SettingsNavTile(
              icon: Icons.notifications_active_outlined,
              title: 'tracker.title'.tr(),
              value: countLabel(following),
              onTap: () => context.push('/following'),
            ),
            const SettingsDivider(),
            SettingsNavTile(
              icon: Icons.bar_chart_rounded,
              title: 'stats.title'.tr(),
              subtitle: 'stats.entry_subtitle'.tr(),
              featureId: 'stats',
              onTap: () => WatchStatsPage.open(context),
            ),
          ],
        ),
      ],
    );
  }
}
