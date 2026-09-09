import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/anilist/presentation/widgets/anilist_brand.dart';
import 'package:soplay/features/mal/data/mal_service.dart';
import 'package:soplay/features/mal/domain/entities/mal_entities.dart';
import 'package:soplay/features/mal/presentation/controllers/mal_library_controller.dart';
import 'package:soplay/features/mal/presentation/widgets/mal_brand.dart';
import 'package:soplay/features/mal/presentation/widgets/mal_entry_sheet.dart';

/// The viewer's MyAnimeList, in the app.
///
/// The cover, chip, progress bar and empty-state widgets are AniList's by name
/// only — nothing in them is AniList-specific — so they are reused rather than
/// cloned under a second name.
class MalLibraryPage extends StatefulWidget {
  const MalLibraryPage({super.key});

  @override
  State<MalLibraryPage> createState() => _MalLibraryPageState();
}

class _MalLibraryPageState extends State<MalLibraryPage>
    with SingleTickerProviderStateMixin {
  final MalService _service = getIt<MalService>();
  late final MalLibraryController _controller;
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _controller = MalLibraryController(service: _service);
    _tabs = TabController(length: kMalLibraryStatuses.length, vsync: this);
    _controller.addListener(_onChange);
    _service.addListener(_onConnectionChange);
    _controller.load();
  }

  @override
  void dispose() {
    _controller.removeListener(_onChange);
    _service.removeListener(_onConnectionChange);
    _controller.dispose();
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

    final Widget body;
    if (!connected) {
      body = AnilistConnectPrompt(
        message: 'mal.connect_prompt'.tr(),
        actionLabel: 'mal.connect'.tr(),
        busy: _service.linking,
        onConnect: _service.beginLink,
        accent: kMalBlue,
      );
    } else if (_controller.loading && _controller.entries.isEmpty) {
      body = const Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: kMalBlue),
      );
    } else if (_controller.error != null && _controller.entries.isEmpty) {
      body = AnilistScrollableMessage(
        message: AnilistStateMessage(
          icon: Icons.cloud_off_rounded,
          text: _controller.error!,
          actionLabel: 'anilist.retry'.tr(),
          onAction: () => _controller.load(force: true),
          accent: kMalBlue,
        ),
      );
    } else {
      body = Column(
        children: [
          _StatusTabBar(controller: _tabs, library: _controller),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                for (final status in kMalLibraryStatuses)
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
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        title: Text(
          'mal.open_library'.tr(),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        actions: [
          if (connected)
            IconButton(
              tooltip: 'anilist.refresh'.tr(),
              onPressed: _controller.loading
                  ? null
                  : () => _controller.load(force: true),
              icon: const Icon(Icons.refresh_rounded, size: 20),
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
  final MalLibraryController library;

  @override
  Widget build(BuildContext context) {
    return TabBar(
      controller: controller,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      indicatorColor: kMalBlue,
      indicatorSize: TabBarIndicatorSize.label,
      labelColor: AppColors.textPrimary,
      unselectedLabelColor: AppColors.textSecondary,
      dividerColor: Colors.transparent,
      labelStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
      unselectedLabelStyle:
          const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
      tabs: [
        for (final status in kMalLibraryStatuses)
          Tab(
            // The count is part of the label rather than a badge: on a list
            // that can be empty in four of five tabs, "Dropped 0" is the
            // fastest way to see there is nothing to look at.
            text: '${malStatusLabel(status)}  ${library.byStatus(status).length}',
          ),
      ],
    );
  }
}

class _StatusList extends StatelessWidget {
  const _StatusList({
    required this.status,
    required this.controller,
    required this.onRefresh,
  });

  final String status;
  final MalLibraryController controller;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final rows = controller.byStatus(status);
    if (rows.isEmpty) {
      return AnilistScrollableMessage(
        message: AnilistStateMessage(
          icon: Icons.inbox_rounded,
          text: 'anilist.empty_status'.tr(args: [malStatusLabel(status)]),
          accent: kMalBlue,
        ),
      );
    }
    return RefreshIndicator(
      color: kMalBlue,
      backgroundColor: AppColors.surface,
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        itemCount: rows.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _EntryTile(
          entry: rows[i],
          busy: controller.isBusy(rows[i].anime.id),
          onTap: () => MalEntrySheet.show(
            context,
            animeId: rows[i].anime.id,
            controller: controller,
          ),
        ),
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.entry,
    required this.busy,
    required this.onTap,
  });

  final MalListEntry entry;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final total = entry.anime.episodes;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: busy ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnilistCover(url: entry.anime.picture, width: 46, radius: 8),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.anime.title,
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
                    Text(
                      total != null
                          ? '${entry.progress} / $total  ·  ${'anilist.episodes_watched'.tr()}'
                          : '${entry.progress}  ·  ${'anilist.episodes_watched'.tr()}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    if (total != null && total > 0) ...[
                      const SizedBox(height: 6),
                      AnilistProgressBar(value: entry.fraction),
                    ],
                    if (entry.score > 0 || entry.isRewatching) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (entry.score > 0)
                            AnilistChip(
                              label: '${entry.score}/10',
                              icon: Icons.star_rounded,
                              color: AppColors.rating,
                            ),
                          if (entry.isRewatching)
                            AnilistChip(
                              label: 'anilist.status_repeating'.tr(),
                              icon: Icons.repeat_rounded,
                              color: kMalBlue,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (busy)
                const Padding(
                  padding: EdgeInsetsDirectional.only(start: 8, top: 4),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: kMalBlue,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
