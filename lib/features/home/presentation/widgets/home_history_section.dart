import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/detail/domain/entities/detail_args.dart';
import 'package:soplay/features/history/data/history_service.dart';
import 'package:soplay/features/history/domain/entities/history_item.dart';
import 'package:soplay/features/home/presentation/widgets/home_shared_widgets.dart';

class HistorySection extends StatelessWidget {
  const HistorySection({super.key, required this.items});

  final List<HistoryItem> items;

  static const double _completedThreshold = 0.95;

  List<HistoryItem> _continueWatching() {
    final byContent = <String, HistoryItem>{};
    for (final item in items) {
      if (item.progress >= _completedThreshold && !item.isSerial) continue;
      final existing = byContent[item.contentUrl];
      if (existing == null || item.watchedAt > existing.watchedAt) {
        byContent[item.contentUrl] = item;
      }
    }
    final sorted = byContent.values.toList()
      ..sort((a, b) => b.watchedAt.compareTo(a.watchedAt));
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _continueWatching();
    if (filtered.isEmpty) return const SizedBox.shrink();
    final visible = filtered.length > 20 ? filtered.sublist(0, 20) : filtered;
    final showViewAll =
        filtered.length > visible.length || filtered.length >= 3;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Whole header strip is the target, like every other rail: the old
          // "View all" TextButton was a ~26dp tap target squeezed into the row.
          HomeSectionTapTarget(
            onTap: showViewAll ? () => context.push('/history') : null,
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(17, 18, 20, 14),
              child: Row(
                children: [
                  const Icon(
                    Icons.history_rounded,
                    color: AppColors.textSecondary,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'home.continue_watching'.tr(),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                  ),
                  if (showViewAll) ...[
                    Text(
                      'home.view_all'.tr(),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.textSecondary,
                      size: 18,
                    ),
                  ],
                ],
              ),
            ),
          ),
          SizedBox(
            height: 170,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: visible.length,
              itemBuilder: (_, i) => _HistoryCard(item: visible[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.item});

  final HistoryItem item;

  void _openDetail(BuildContext context) {
    if (item.contentUrl.isEmpty) return;
    context.push(
      '/detail',
      extra: DetailArgs(
        contentUrl: item.contentUrl,
        autoPlay: true,
        resumeEpisodeIndex: item.episodeIndex,
        provider: item.provider,
      ),
    );
  }

  Future<void> _showActions(BuildContext context) async {
    final action = await showModalBottomSheet<_HistoryAction>(
      context: context,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetCtx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textSecondary.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(
                Icons.play_arrow_rounded,
                color: AppColors.primary,
              ),
              title: Text(
                'player.resume'.tr(),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () => Navigator.of(sheetCtx).pop(_HistoryAction.resume),
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline_rounded,
                color: AppColors.error,
              ),
              title: Text(
                'home.remove_from_continue'.tr(),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () => Navigator.of(sheetCtx).pop(_HistoryAction.remove),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    switch (action) {
      case _HistoryAction.resume:
        _openDetail(context);
      case _HistoryAction.remove:
        await getIt<HistoryService>().remove(item.storageKey);
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = item.episodeLabel?.trim();
    final episodeLabel = (item.isSerial && label != null && label.isNotEmpty)
        ? label
        : null;
    return HoverTap(
      onTap: () => _openDetail(context),
      onLongPress: () => _showActions(context),
      onSecondaryTap: () => _showActions(context),
      child: SizedBox(
        width: 150,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      HomeNetworkImage(
                        url: item.thumbnail,
                        borderRadius: BorderRadius.zero,
                        placeholderIcon: Icons.movie_outlined,
                      ),
                      const Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: SizedBox(
                          height: 56,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [
                                  Color(0xDD000000),
                                  Color(0x00000000),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (item.isSerial && item.episodeNumber != null)
                        Positioned(
                          top: 6,
                          left: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              'home.ep_number'.tr(
                                args: ['${item.episodeNumber}'],
                              ),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                height: 1,
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        right: 8,
                        bottom: 12,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                      if (item.progress > 0)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: LinearProgressIndicator(
                            value: item.progress,
                            minHeight: 3,
                            backgroundColor: Colors.white24,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppColors.primary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              FixedTextLines(
                fontSize: 11.5,
                lineHeight: 1.25,
                child: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
              ),
              FixedTextLines(
                fontSize: 10,
                lineHeight: 1.3,
                child: episodeLabel == null
                    ? null
                    : Text(
                        episodeLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10,
                          height: 1.3,
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

enum _HistoryAction { resume, remove }
