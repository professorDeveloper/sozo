import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/detail/domain/entities/detail_args.dart';
import 'package:soplay/features/detail/domain/entities/episode_entity.dart';
import 'package:soplay/features/detail/domain/entities/player_args.dart';
import 'package:soplay/features/download/domain/entities/download_item.dart';
import 'package:soplay/features/download/domain/entities/download_status.dart';
import 'package:soplay/features/download/domain/entities/downloaded_title.dart';
import 'package:soplay/features/download/domain/repositories/offline_title_repository.dart';
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
import 'package:soplay/features/download/presentation/widgets/downloaded_titles_grid.dart';
import 'package:soplay/features/download/presentation/widgets/downloads_toolbar.dart';
import 'package:soplay/features/download/presentation/widgets/downloads_view_switch.dart';
import 'package:soplay/features/download/presentation/widgets/relink_source_sheet.dart';
import 'package:soplay/features/history/data/history_service.dart';
import 'package:soplay/features/home/domain/entities/movie.dart';
import 'package:soplay/features/manga/domain/entities/reader_args.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_bloc.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_state.dart';
import 'package:soplay/features/profile/presentation/widgets/settings_tiles.dart';

/// The offline library.
///
/// The screen is a renderer: it holds no filesystem knowledge, decides nothing
/// about what "downloaded" means, and never builds a path. Opening an item
/// asks the domain for a path that can actually be opened and takes null as an
/// answer — which is the difference between "File not found" as a dead end and
/// a row that offers to fetch the file back.
class DownloadsPage extends StatelessWidget {
  const DownloadsPage({super.key, this.isTab = false});

  final bool isTab;

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
      child: _DownloadsView(isTab: isTab),
    );
  }
}

class _DownloadsView extends StatefulWidget {
  const _DownloadsView({required this.isTab});

  final bool isTab;

  @override
  State<_DownloadsView> createState() => _DownloadsViewState();
}

class _DownloadsViewState extends State<_DownloadsView> {
  // Survives leaving the tab and coming back within a session.
  static DownloadsView _lastView = DownloadsView.titles;
  DownloadsView _view = _lastView;

  bool get isTab => widget.isTab;

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
          final showTitles = state.total > 0 && _view == DownloadsView.titles;
          final titles = showTitles
              ? DownloadedTitle.group(
                  getIt<GetDownloadsUseCase>()(),
                  snapshotOf: getIt<OfflineTitleRepository>().get,
                )
              : const <DownloadedTitle>[];
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
                    if (!isTab) ...[
                      _CircleBackButton(
                        onTap: () => context.canPop()
                            ? context.pop()
                            : context.go('/main'),
                      ),
                      const SizedBox(width: 12),
                    ],
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
                        onSort: (sort) => bloc.add(DownloadsSortChanged(sort)),
                        sort: state.sort,
                      ),
                  ],
                ),
              ),

              if (state.total > 0)
                SliverToBoxAdapter(
                  child: DownloadsViewSwitch(
                    view: _view,
                    onChanged: (v) => setState(() => _view = _lastView = v),
                  ),
                ),

              if (showTitles) ...[
                if (titles.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _NoTitlesYet(
                      onShowFiles: () => setState(
                        () => _view = _lastView = DownloadsView.files,
                      ),
                    ),
                  )
                else
                  DownloadedTitlesGrid(
                    titles: titles,
                    thumbnailOf: getIt<GetDownloadsUseCase>().thumbnailOf,
                    providerNameOf: (t) => _providerName(context, t),
                    onOpen: (t) => _openTitle(context, t),
                    onActions: (t) => _titleActions(context, t),
                  ),
              ] else ...[
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
                      onChanged: (v) => bloc.add(DownloadsWifiOnlyToggled(v)),
                    ),
                  ),
                ),

                // Next to Wi-Fi only, because they are the same kind of setting:
                // both make the queue slower on purpose, for a reason outside
                // the app.
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: SettingsDropdownTile<int>(
                      icon: Icons.hourglass_empty_rounded,
                      title: 'downloads.cooldown'.tr(),
                      subtitle: 'downloads.cooldown_desc'.tr(),
                      value: state.cooldownSeconds,
                      options: const [0, 5, 15, 30, 60, 120],
                      labelOf: (v) => v == 0
                          ? 'downloads.cooldown_off'.tr()
                          : 'downloads.cooldown_n'.tr(args: ['$v']),
                      onChanged: (v) => bloc.add(DownloadsCooldownChanged(v)),
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
                      onClearFilter: () => bloc.add(
                        const DownloadsFilterChanged(DownloadsFilter.all),
                      ),
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
              ],

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

    if (item.isSerial && item.episodeNumber != null) {
      if (_playSeries(context, item)) return;
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
        // The series title alone: history and the trackers key on it, and the
        // player adds the episode itself from offlineEpisodeNumber below.
        title: item.title,
        provider: item.provider,
        headers: const {},
        contentUrl: item.contentUrl,
        thumbnail: downloads.thumbnailOf(item) ?? item.thumbnailUrl,
        movieUrl: item.isHls ? Uri.file(path).toString() : path,
        type: item.isHls ? 'hls' : null,
        showDownloadAction: false,
        // Recorded as the episode it is, not as a film under the series url.
        offlineEpisodeNumber: item.isSerial ? item.episodeNumber : null,
        offlineEpisodeLabel: item.isSerial ? item.episodeLabel : null,
      ),
    );
  }

  /// An episode opens with its downloaded siblings as the run, so next and
  /// previous step through what is on disk.
  bool _playSeries(BuildContext context, DownloadItem item) {
    final downloads = getIt<GetDownloadsUseCase>();
    final siblings = [
      for (final d in downloads.completedOf(item.groupKey))
        if (!d.isManga && d.episodeNumber != null) d,
    ];
    final index = siblings.indexWhere((d) => d.id == item.id);
    if (index < 0 || downloads.pathOf(item) == null) return false;
    final resume = getIt<HistoryService>().get(
      item.contentUrl,
      episodeNumber: item.episodeNumber,
    );
    context.push(
      '/player',
      extra: PlayerArgs(
        title: item.title,
        provider: item.provider,
        headers: const {},
        contentUrl: item.contentUrl,
        thumbnail: downloads.thumbnailOf(item) ?? item.thumbnailUrl,
        episodes: [
          for (final d in siblings)
            EpisodeEntity(
              episode: d.episodeNumber!,
              label: d.episodeLabel ?? '',
              mediaRef: '',
            ),
        ],
        initialEpisodeIndex: index,
        resumePosition: Duration(milliseconds: resume?.positionMs ?? 0),
        showDownloadAction: false,
      ),
    );
    return true;
  }

  String _providerName(BuildContext context, DownloadedTitle title) {
    final saved = title.snapshot?.providerName;
    if (saved != null && saved.isNotEmpty) return saved;
    try {
      final state = context.read<ProviderBloc>().state;
      if (state is ProviderLoaded) {
        for (final p in state.providers) {
          if (p.id == title.provider) return p.name;
        }
      }
    } catch (_) {}
    final id = title.provider;
    final colon = id.indexOf(':');
    return colon >= 0 ? id.substring(colon + 1) : id;
  }

  void _openTitle(BuildContext context, DownloadedTitle title) {
    context.push(
      '/detail',
      extra: DetailArgs(
        contentUrl: title.key,
        provider: title.provider,
        preview: MovieEntity(
          externalId: '',
          title: title.title,
          description: '',
          slug: '',
          url: title.key,
          provider: title.provider,
          thumbnail: title.thumbnailUrl,
          year: title.snapshot?.year,
          rating: null,
          qualities: null,
          category: '',
        ),
      ),
    );
  }

  void _titleActions(BuildContext context, DownloadedTitle title) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Text(
                title.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(
                Icons.info_outline_rounded,
                color: AppColors.textSecondary,
              ),
              title: Text(
                'downloads.open_title'.tr(),
                style: const TextStyle(color: AppColors.textPrimary),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _openTitle(context, title);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.swap_horiz_rounded,
                color: AppColors.textSecondary,
              ),
              title: Text(
                'downloads.relink'.tr(),
                style: const TextStyle(color: AppColors.textPrimary),
              ),
              subtitle: Text(
                'downloads.relink_short'.tr(),
                style: const TextStyle(color: AppColors.textHint, fontSize: 12),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _relink(context, title);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline_rounded,
                color: AppColors.error,
              ),
              title: Text(
                'downloads.delete_downloads'.tr(),
                style: const TextStyle(color: AppColors.error),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _confirmDeleteTitle(context, title);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _relink(BuildContext context, DownloadedTitle title) async {
    final bloc = context.read<DownloadsBloc>();
    final messenger = ScaffoldMessenger.of(context);
    final outcome = await RelinkSourceSheet.show(context, title: title);
    if (outcome == null) return;
    bloc.add(const DownloadsRefreshed());
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          [
            'downloads.relink_done'.tr(args: ['${outcome.moved}']),
            if (outcome.left > 0)
              'downloads.relink_done_left'.tr(args: ['${outcome.left}']),
          ].join(' '),
        ),
      ),
    );
  }

  void _confirmDeleteTitle(BuildContext context, DownloadedTitle title) {
    final bloc = context.read<DownloadsBloc>();
    final ids = [
      for (final d in getIt<GetDownloadsUseCase>()())
        if (d.groupKey == title.key) d.id,
    ];
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'downloads.delete_downloads_confirm'.tr(
            namedArgs: {'count': '${ids.length}', 'title': title.title},
          ),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
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
              bloc.add(DownloadsRemoveRequested(ids));
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

  void _openReader(BuildContext context, DownloadItem item) {
    final downloads = getIt<GetDownloadsUseCase>();
    final state = context.read<DownloadsBloc>().state;

    // Every finished chapter of the same title, so the reader can page between
    // them offline instead of stopping at the one that was tapped.
    final siblings =
        [
          for (final group in state.groups)
            if (group.key == item.groupKey)
              for (final d in group.items)
                if (d.isManga && d.status == DownloadStatus.completed) d,
        ]..sort((a, b) {
          // By chapter number first: it is the one thing that means the same
          // wherever the chapter was downloaded from — the reader, a later block
          // of the list, a list sorted newest-first. The stored index breaks
          // ties, for sources that number nothing.
          final byNumber = (a.episodeNumber ?? 0).compareTo(
            b.episodeNumber ?? 0,
          );
          if (byNumber != 0) return byNumber;
          return (a.chapterIndex ?? 0).compareTo(b.chapterIndex ?? 0);
        });

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
    // How far a novel's export has got: gathering thirty chapters into one
    // book is not instant, and a bare "exporting" for that long reads as
    // stuck.
    final progress = ValueNotifier<(int, int)>((0, 0));
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(minutes: 5),
        content: ValueListenableBuilder<(int, int)>(
          valueListenable: progress,
          builder: (_, p, _) {
            final (done, total) = p;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  total > 1
                      ? 'downloads.export_progress'.tr(
                          args: ['$done', '$total'],
                        )
                      : 'downloads.export_running'.tr(),
                ),
                if (total > 1) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: done >= total ? null : done / total,
                    minHeight: 3,
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
    final location = await getIt<ExportDownloadUseCase>()(
      item.id,
      onProgress: (done, total) => progress.value = (done, total),
    );
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
    progress.dispose();
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

class _NoTitlesYet extends StatelessWidget {
  const _NoTitlesYet({required this.onShowFiles});

  final VoidCallback onShowFiles;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.video_library_outlined,
              size: 46,
              color: AppColors.textHint,
            ),
            const SizedBox(height: 14),
            Text(
              'downloads.titles_empty_title'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'downloads.titles_empty_subtitle'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            TextButton(
              onPressed: onShowFiles,
              child: Text('downloads.view_files'.tr()),
            ),
          ],
        ),
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
            child: Text(switch (option) {
              DownloadsSort.newest => 'downloads.sort_newest'.tr(),
              DownloadsSort.title => 'downloads.sort_title'.tr(),
              DownloadsSort.size => 'downloads.sort_size'.tr(),
            }, style: const TextStyle(color: AppColors.textPrimary)),
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
