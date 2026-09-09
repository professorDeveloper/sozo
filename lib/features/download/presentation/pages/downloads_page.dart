import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/detail/domain/entities/episode_entity.dart';
import 'package:soplay/features/detail/domain/entities/player_args.dart';
import 'package:soplay/features/download/domain/entities/download_item.dart';
import 'package:soplay/features/download/domain/entities/download_status.dart';
import 'package:soplay/features/download/domain/usecases/control_download_usecase.dart';
import 'package:soplay/features/download/domain/usecases/download_location_usecase.dart';
import 'package:soplay/features/download/domain/usecases/download_storage_usecase.dart';
import 'package:soplay/features/download/domain/usecases/export_download_usecase.dart';
import 'package:soplay/features/download/domain/usecases/get_downloads_usecase.dart';
import 'package:soplay/features/download/domain/usecases/remove_download_usecase.dart';
import 'package:soplay/features/download/domain/usecases/verify_downloads_usecase.dart';
import 'package:soplay/features/download/presentation/bloc/downloads_bloc.dart';
import 'package:soplay/features/download/presentation/download_messages.dart';
import 'package:soplay/features/download/presentation/widgets/download_group_tile.dart';
import 'package:soplay/features/download/presentation/widgets/download_location_tile.dart';
import 'package:soplay/features/download/presentation/widgets/downloads_empty_state.dart';
import 'package:soplay/features/download/presentation/widgets/downloads_storage_header.dart';
import 'package:soplay/features/download/presentation/widgets/downloads_toolbar.dart';
import 'package:soplay/features/manga/domain/entities/reader_args.dart';
import 'package:soplay/features/profile/presentation/widgets/settings_tiles.dart';

/// The offline library.
///
/// The screen is a renderer: it holds no filesystem knowledge, decides nothing
/// about what "downloaded" means, and never builds a path. Opening an item
/// asks the domain for a path that can actually be opened and takes null as an
/// answer — which is the difference between "File not found" as a dead end and
/// a row that offers to fetch the file back.
class DownloadsPage extends StatelessWidget {
  const DownloadsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => DownloadsBloc(
        getDownloads: getIt<GetDownloadsUseCase>(),
        control: getIt<ControlDownloadUseCase>(),
        remove: getIt<RemoveDownloadUseCase>(),
        verify: getIt<VerifyDownloadsUseCase>(),
        storage: getIt<DownloadStorageUseCase>(),
        location: getIt<DownloadLocationUseCase>(),
        hive: getIt<HiveService>(),
      )..add(const DownloadsStarted()),
      child: const _DownloadsView(),
    );
  }
}

class _DownloadsView extends StatelessWidget {
  const _DownloadsView();

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: BlocConsumer<DownloadsBloc, DownloadsState>(
        // A move is an event, not a condition: it is reported once, when it
        // finishes, rather than by every later rebuild.
        listenWhen: (prev, curr) => prev.busy && !curr.busy,
        listener: (context, state) {
          final outcome = context.read<DownloadsBloc>().lastMoveOutcome;
          if (outcome == null) return;
          context.read<DownloadsBloc>().lastMoveOutcome = null;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(moveOutcomeMessage(outcome)),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
        builder: (context, state) {
          final bloc = context.read<DownloadsBloc>();
          return CustomScrollView(
            slivers: [
              // Pinned: on a long library the back button and the bulk actions
              // scrolled out of reach.
              SliverAppBar(
                pinned: true,
                automaticallyImplyLeading: false,
                backgroundColor: AppColors.background,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                scrolledUnderElevation: 0,
                titleSpacing: 16,
                title: Row(
                  children: [
                    _CircleBackButton(
                      onTap: () => context.canPop()
                          ? context.pop()
                          : context.go('/main'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'navigation.downloads'.tr(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (state.total > 0)
                      _OverflowMenu(
                        onRetryAll: () =>
                            bloc.add(const DownloadsRetryAllRequested()),
                        onClearAll: () => _confirmClear(context, bloc),
                        onSort: (sort) =>
                            bloc.add(DownloadsSortChanged(sort)),
                        sort: state.sort,
                      ),
                  ],
                ),
              ),

              if (state.total > 0)
                SliverToBoxAdapter(
                  child: DownloadsStorageHeader(
                    usage: state.usage,
                    busy: state.busy,
                    onSweep: () => bloc.add(const DownloadsSweepRequested()),
                  ),
                ),

              SliverToBoxAdapter(
                child: DownloadLocationTile(
                  locations: state.locations,
                  current: state.currentLocation,
                  busy: state.busy,
                  onPick: (l) => bloc.add(DownloadsLocationChosen(l)),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: SettingsSwitchTile(
                    icon: Icons.wifi_rounded,
                    title: 'downloads.wifi_only'.tr(),
                    subtitle: state.waitingForWifi
                        ? 'downloads.waiting_for_wifi'.tr()
                        : 'downloads.wifi_only_desc'.tr(),
                    value: state.wifiOnly,
                    onChanged: (v) =>
                        bloc.add(DownloadsWifiOnlyToggled(v)),
                  ),
                ),
              ),

              if (state.total > 0)
                SliverToBoxAdapter(
                  child: DownloadsToolbar(
                    filter: state.filter,
                    onFilter: (f) => bloc.add(DownloadsFilterChanged(f)),
                  ),
                ),

              if (state.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: DownloadsEmptyState(
                    // "No downloads yet" is wrong when there are twelve of
                    // them and the filter is hiding all twelve.
                    filtered: state.total > 0,
                    onClearFilter: () => bloc
                        .add(const DownloadsFilterChanged(DownloadsFilter.all)),
                  ),
                )
              else
                SliverList.separated(
                  itemCount: state.groups.length,
                  separatorBuilder: (_, _) => Divider(
                    color: AppColors.divider,
                    height: 1,
                    indent: 82,
                  ),
                  itemBuilder: (_, i) {
                    final group = state.groups[i];
                    return DownloadGroupTile(
                      group: group,
                      thumbnailOf: getIt<GetDownloadsUseCase>().thumbnailOf,
                      onOpen: (item) => _open(context, item),
                      onPauseResume: (item) => bloc.add(
                        item.status == DownloadStatus.paused
                            ? DownloadsResumeRequested(item.id)
                            : DownloadsPauseRequested(item.id),
                      ),
                      onRetry: (item) =>
                          bloc.add(DownloadsRetryRequested(item.id)),
                      onRemove: (ids) =>
                          bloc.add(DownloadsRemoveRequested(ids)),
                      onExport: (item) => _export(context, item),
                    );
                  },
                ),

              SliverToBoxAdapter(child: SizedBox(height: bottomPad + 24)),
            ],
          );
        },
      ),
    );
  }

  /// Opens a finished download.
  ///
  /// The path is asked for rather than assumed, and a null answer is handled
  /// as a repairable state instead of a toast. This is the exact call that used
  /// to end in "File not found" with nothing to do next.
  void _open(BuildContext context, DownloadItem item) {
    final bloc = context.read<DownloadsBloc>();
    final downloads = getIt<GetDownloadsUseCase>();

    if (item.status == DownloadStatus.missing) {
      bloc.add(DownloadsRetryRequested(item.id));
      _snack(context, 'downloads.redownload_started'.tr());
      return;
    }
    if (item.status != DownloadStatus.completed) return;

    if (item.isManga) {
      _openReader(context, item);
      return;
    }

    final path = downloads.pathOf(item);
    if (path == null) {
      // The file went away between the sweep and this tap — an SD card pulled,
      // a cleaner app, a restore mid-session. Fix the row and offer the only
      // thing that can help.
      bloc.add(const DownloadsRefreshed());
      bloc.add(DownloadsRetryRequested(item.id));
      _snack(context, 'downloads.file_missing_retry'.tr());
      return;
    }

    context.push(
      '/player',
      extra: PlayerArgs(
        title: item.isSerial && item.episodeNumber != null
            ? '${item.title} · EP ${item.episodeNumber}'
            : item.title,
        provider: item.provider,
        headers: const {},
        contentUrl: item.contentUrl,
        thumbnail: downloads.thumbnailOf(item) ?? item.thumbnailUrl,
        movieUrl: item.isHls ? Uri.file(path).toString() : path,
        type: item.isHls ? 'hls' : null,
        showDownloadAction: false,
      ),
    );
  }

  void _openReader(BuildContext context, DownloadItem item) {
    final downloads = getIt<GetDownloadsUseCase>();
    final state = context.read<DownloadsBloc>().state;

    // Every finished chapter of the same title, so the reader can page between
    // them offline instead of stopping at the one that was tapped.
    final siblings = [
      for (final group in state.groups)
        if (group.key == item.groupKey)
          for (final d in group.items)
            if (d.isManga && d.status == DownloadStatus.completed) d,
    ]..sort((a, b) => (a.chapterIndex ?? 0).compareTo(b.chapterIndex ?? 0));

    final chapters = [
      for (final d in siblings)
        EpisodeEntity(
          episode: d.episodeNumber ?? 0,
          label: d.episodeLabel ?? d.title,
          mediaRef: d.chapterRef ?? '',
        ),
    ];
    var start = siblings.indexWhere((d) => d.id == item.id);
    if (start < 0) start = 0;

    context.push(
      '/reader',
      extra: ReaderArgs(
        title: item.title,
        provider: item.provider,
        contentUrl: item.contentUrl,
        thumbnail: downloads.thumbnailOf(item) ?? item.thumbnailUrl,
        chapters: chapters,
        initialChapterIndex: start,
      ),
    );
  }

  /// Copies a finished download into the device's shared Downloads folder.
  ///
  /// The message names the folder rather than saying "done": the whole point
  /// is that the file is now somewhere findable, and "saved" without a
  /// location is the same dead end the export exists to fix.
  Future<void> _export(BuildContext context, DownloadItem item) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(content: Text('downloads.export_running'.tr())),
    );
    final location = await getIt<ExportDownloadUseCase>()(item.id);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            location == null
                ? 'downloads.export_failed'.tr()
                : 'downloads.export_done'.tr(args: [location]),
          ),
        ),
      );
  }

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  void _confirmClear(BuildContext context, DownloadsBloc bloc) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'downloads.delete_all_title'.tr(),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'general.cancel'.tr(),
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              bloc.add(const DownloadsClearRequested());
            },
            child: Text(
              'general.delete'.tr(),
              style: const TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sort and the two bulk actions, behind one button.
///
/// They used to be a single "Clear all" pill, which is the most destructive
/// thing on the screen sitting where a primary action goes.
class _OverflowMenu extends StatelessWidget {
  const _OverflowMenu({
    required this.onRetryAll,
    required this.onClearAll,
    required this.onSort,
    required this.sort,
  });

  final VoidCallback onRetryAll;
  final VoidCallback onClearAll;
  final ValueChanged<DownloadsSort> onSort;
  final DownloadsSort sort;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<Object>(
      icon: const Icon(Icons.more_vert_rounded, color: AppColors.textPrimary),
      color: AppColors.surface,
      onSelected: (value) {
        if (value is DownloadsSort) {
          onSort(value);
        } else if (value == 'retry') {
          onRetryAll();
        } else if (value == 'clear') {
          onClearAll();
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem<Object>(
          enabled: false,
          height: 30,
          child: Text(
            'downloads.sort_by'.tr(),
            style: const TextStyle(color: AppColors.textHint, fontSize: 11),
          ),
        ),
        for (final option in DownloadsSort.values)
          CheckedPopupMenuItem<Object>(
            value: option,
            checked: option == sort,
            child: Text(
              switch (option) {
                DownloadsSort.newest => 'downloads.sort_newest'.tr(),
                DownloadsSort.title => 'downloads.sort_title'.tr(),
                DownloadsSort.size => 'downloads.sort_size'.tr(),
              },
              style: const TextStyle(color: AppColors.textPrimary),
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem<Object>(
          value: 'retry',
          child: Text(
            'downloads.retry_all'.tr(),
            style: const TextStyle(color: AppColors.textPrimary),
          ),
        ),
        PopupMenuItem<Object>(
          value: 'clear',
          child: Text(
            'downloads.clear_all'.tr(),
            style: const TextStyle(color: AppColors.error),
          ),
        ),
      ],
    );
  }
}

class _CircleBackButton extends StatelessWidget {
  const _CircleBackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: const SizedBox(
          width: 36,
          height: 36,
          child: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppColors.textPrimary,
            size: 16,
          ),
        ),
      ),
    );
  }
}
