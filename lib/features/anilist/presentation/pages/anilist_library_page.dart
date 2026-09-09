import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/anilist/data/anilist_service.dart';
import 'package:soplay/features/anilist/domain/entities/anilist_entities.dart';
import 'package:soplay/features/anilist/presentation/controllers/anilist_library_controller.dart';
import 'package:soplay/features/anilist/presentation/widgets/anilist_brand.dart';
import 'package:soplay/features/anilist/presentation/widgets/anilist_logo.dart';
import 'package:soplay/features/anilist/presentation/widgets/anilist_entry_sheet.dart';

/// The viewer's AniList anime list, one tab per status.
///
/// Owns nothing but presentation: the controller is created here and disposed
/// with the page, which is what makes the whole screen disappear cleanly when
/// the account is disconnected from somewhere else.
class AnilistLibraryPage extends StatefulWidget {
  const AnilistLibraryPage({super.key, this.showAppBar = true, this.controller});

  /// False when hosted inside another scaffold's tab, which already supplies
  /// its own bar — two stacked app bars is the usual cost of reusing a page.
  final bool showAppBar;

  /// Supplied by a host that shows this list alongside another view of the same
  /// data (the tracker hub). Shared rather than duplicated so both views reflect
  /// a "+1" immediately and the library is fetched once, not once per tab.
  final AnilistLibraryController? controller;

  @override
  State<AnilistLibraryPage> createState() => _AnilistLibraryPageState();
}

class _AnilistLibraryPageState extends State<AnilistLibraryPage>
    with SingleTickerProviderStateMixin {
  final AnilistService _service = getIt<AnilistService>();
  late final AnilistLibraryController _controller;
  late final TabController _tabs;

  /// Only a controller this page created may be disposed here — disposing a
  /// borrowed one would break the host that still uses it.
  late final bool _ownsController = widget.controller == null;

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ?? AnilistLibraryController(service: _service);
    _tabs = TabController(length: AnilistStatus.values.length, vsync: this);
    _controller.addListener(_onChange);
    _service.addListener(_onConnectionChange);
    _controller.load();
  }

  @override
  void dispose() {
    _controller.removeListener(_onChange);
    _service.removeListener(_onConnectionChange);
    if (_ownsController) _controller.dispose();
    _tabs.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  /// Connecting from this very screen must fill it in without a manual pull.
  void _onConnectionChange() {
    if (!mounted) return;
    setState(() {});
    if (_service.isConnected && _controller.entries.isEmpty) {
      _controller.load(force: true);
    }
    final error = _service.consumeError();
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), behavior: SnackBarBehavior.floating),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = _service.isConnected;

    final body = !connected
        ? AnilistConnectPrompt(
            message: 'anilist.connect_prompt'.tr(),
            actionLabel: 'anilist.connect'.tr(),
            busy: _service.linking,
            onConnect: _service.beginLink,
          )
        : Column(
            children: [
              _StatusTabBar(controller: _tabs, library: _controller),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    for (final status in AnilistStatus.values)
                      _StatusList(
                        status: status,
                        controller: _controller,
                        onRefresh: () => _controller.load(force: true),
                      ),
                  ],
                ),
              ),
            ],
          );

    if (!widget.showAppBar) return body;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        title: Row(
          children: [
            const AnilistLogo(size: 20),
            const SizedBox(width: 9),
            Text(
              'AniList',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        actions: [
          // Offered signed out too: the schedule is public, and it is the one
          // part of AniList that is worth something without an account.
          IconButton(
            tooltip: 'anilist.browse_title'.tr(),
            onPressed: () => context.push('/anilist/browse'),
            icon: const Icon(Icons.explore_rounded),
          ),
          IconButton(
            tooltip: 'anilist.calendar_title'.tr(),
            onPressed: () => context.push('/anilist/calendar'),
            icon: const Icon(Icons.calendar_month_rounded),
          ),
          if (connected)
            IconButton(
              tooltip: 'anilist.refresh'.tr(),
              onPressed: _controller.loading
                  ? null
                  : () => _controller.load(force: true),
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
      body: body,
    );
  }
}

class _StatusTabBar extends StatelessWidget {
  const _StatusTabBar({required this.controller, required this.library});

  final TabController controller;
  final AnilistLibraryController library;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: AlignmentDirectional.centerStart,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider, width: 0.5)),
      ),
      child: TabBar(
        controller: controller,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        dividerColor: Colors.transparent,
        indicatorColor: kAnilistBlue,
        indicatorSize: TabBarIndicatorSize.label,
        indicatorWeight: 2.5,
        labelColor: kAnilistBlue,
        unselectedLabelColor: AppColors.textSecondary,
        labelStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
        unselectedLabelStyle:
            const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        tabs: [
          for (final status in AnilistStatus.values)
            Tab(
              height: 44,
              text: () {
                final count = library.countOf(status);
                final label = status.labelKey.tr();
                return count > 0 ? '$label  $count' : label;
              }(),
            ),
        ],
      ),
    );
  }
}

class _StatusList extends StatelessWidget {
  const _StatusList({
    required this.status,
    required this.controller,
    required this.onRefresh,
  });

  final AnilistStatus status;
  final AnilistLibraryController controller;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (controller.loading && controller.entries.isEmpty) {
      return const _LoadingList();
    }

    final error = controller.error;
    if (error != null && controller.entries.isEmpty) {
      return RefreshIndicator(
        color: kAnilistBlue,
        backgroundColor: AppColors.surface,
        onRefresh: onRefresh,
        child: AnilistScrollableMessage(
          message: AnilistStateMessage(
            icon: Icons.cloud_off_rounded,
            text: error,
            actionLabel: 'anilist.retry'.tr(),
            onAction: onRefresh,
          ),
        ),
      );
    }

    final items = controller.byStatus(status);
    if (items.isEmpty) {
      return RefreshIndicator(
        color: kAnilistBlue,
        backgroundColor: AppColors.surface,
        onRefresh: onRefresh,
        child: AnilistScrollableMessage(
          message: AnilistStateMessage(
            icon: Icons.inbox_rounded,
            text: 'anilist.empty_status'
                .tr(args: [status.labelKey.tr().toLowerCase()]),
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: kAnilistBlue,
      backgroundColor: AppColors.surface,
      onRefresh: onRefresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) => AnilistEntryCard(
          entry: items[i],
          busy: controller.isBusy(items[i].id),
          onTap: () => AnilistEntrySheet.show(
            context,
            entryId: items[i].id,
            controller: controller,
          ),
          onBump: () async {
            final error = await controller.bumpEpisode(items[i]);
            if (error != null && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(error), behavior: SnackBarBehavior.floating),
              );
            }
          },
        ),
      ),
    );
  }
}

/// One title in the library.
class AnilistEntryCard extends StatelessWidget {
  const AnilistEntryCard({
    super.key,
    required this.entry,
    required this.onTap,
    this.onBump,
    this.busy = false,
  });

  final AnilistListEntry entry;
  final VoidCallback onTap;
  final VoidCallback? onBump;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final media = entry.media;
    final total = media.episodes;
    final behind = entry.behindBy;

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnilistCover(url: media.coverImage, width: 54, radius: 8),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      media.displayTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          total != null
                              ? '${entry.progress} / $total'
                              : '${entry.progress}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (behind > 0) ...[
                          const SizedBox(width: 8),
                          AnilistChip(
                            label: 'anilist.behind_n'.tr(args: ['$behind']),
                            color: AppColors.success,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    AnilistProgressBar(value: entry.completion),
                  ],
                ),
              ),
              if (onBump != null && entry.nextEpisode != null) ...[
                const SizedBox(width: 8),
                _BumpButton(
                  busy: busy,
                  episode: entry.nextEpisode!,
                  onTap: onBump!,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BumpButton extends StatelessWidget {
  const _BumpButton({
    required this.busy,
    required this.episode,
    required this.onTap,
  });

  final bool busy;
  final int episode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'anilist.mark_episode_watched'.tr(args: ['$episode']),
      child: Material(
        color: kAnilistBlue.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: busy ? null : onTap,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 42,
            height: 42,
            child: busy
                ? const Center(
                    child: SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: kAnilistBlue,
                      ),
                    ),
                  )
                : const Icon(Icons.add_rounded, color: kAnilistBlue, size: 21),
          ),
        ),
      ),
    );
  }
}

/// Skeleton rows shaped like the real cards, so the list does not jump when
/// the data lands.
class _LoadingList extends StatelessWidget {
  const _LoadingList();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
      itemCount: 6,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      // Matches the real card: 10 of padding either side of a 54-wide 2:3
      // cover. A skeleton of a different height defeats its own purpose.
      itemBuilder: (_, _) => Container(
        height: 54 * 3 / 2 + 20,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }
}
