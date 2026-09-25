import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/theme/app_theme.dart';
import 'package:soplay/core/widgets/item_appear.dart';
import 'package:soplay/features/automation/data/auto_download_service.dart';
import 'package:soplay/features/tracker/data/release_feed_store.dart';
import 'package:soplay/features/tracker/data/release_watch.dart';
import 'package:soplay/features/tracker/domain/release_entry.dart';
import 'package:soplay/features/tracker/presentation/widgets/release_labels.dart';
import 'package:soplay/features/tracker/presentation/widgets/release_widgets.dart';

/// New episodes and chapters of everything followed, newest first, in days.
class ReleaseFeedPage extends StatefulWidget {
  const ReleaseFeedPage({super.key});

  @override
  State<ReleaseFeedPage> createState() => _ReleaseFeedPageState();
}

class _ReleaseFeedPageState extends State<ReleaseFeedPage> {
  final ReleaseFeedStore _feed = getIt<ReleaseFeedStore>();
  final ReleaseWatch _watch = getIt<ReleaseWatch>();
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _feed.revision.addListener(_changed);
    unawaited(_watch.drain());
  }

  @override
  void dispose() {
    _feed.revision.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _refresh() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final auto = getIt<AutoDownloadService>();
      final grown = await _watch.checkNow(onChecked: auto.collect);
      unawaited(auto.afterCheck());
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              grown > 0
                  ? 'tracker.new_episodes_found'.tr(args: ['$grown'])
                  : 'release_notify.feed_none_found'.tr(),
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _markSeen(ReleaseEntry e) async {
    HapticFeedback.selectionClick();
    await _watch.markSeen(e.provider, e.contentUrl);
  }

  Future<void> _remove(ReleaseEntry e) async {
    HapticFeedback.selectionClick();
    await _feed.dismiss(e.key);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('release_notify.feed_removed'.tr()),
          action: SnackBarAction(
            label: 'tracker.undo'.tr(),
            onPressed: () => unawaited(_feed.restore(e)),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final entries = _feed.entries();
    final unseen = entries.where((e) => !e.seen).length;
    final groups = groupReleases(entries, DateTime.now());

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        titleSpacing: 16,
        title: Text(
          'release_notify.feed_title'.tr(),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        actions: [
          if (isDesktopPlatform || isTvPlatform)
            IconButton(
              tooltip: 'general.retry'.tr(),
              onPressed: _checking ? null : _refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          if (unseen > 0)
            IconButton(
              tooltip: 'release_notify.feed_mark_all'.tr(),
              onPressed: () {
                HapticFeedback.selectionClick();
                unawaited(_feed.markAllSeen());
              },
              icon: const Icon(Icons.done_all_rounded),
            ),
        ],
        bottom: _checking
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(
                  minHeight: 2,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation(AppColors.primary),
                ),
              )
            : null,
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: AppColors.surface,
        onRefresh: _refresh,
        child: entries.isEmpty
            ? _EmptyFeed(onCheck: _refresh, checking: _checking)
            : MaxWidthBox(
                maxWidth: 760,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    for (final (bucket, items) in groups) ...[
                      SliverToBoxAdapter(
                        child: _BucketHeader(bucket: bucket, count: items.length),
                      ),
                      SliverList.builder(
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          final e = items[i];
                          return ItemAppear(
                            key: ValueKey(e.key),
                            index: i,
                            child: _SwipeRow(
                              entry: e,
                              onSeen: () => _markSeen(e),
                              onRemove: () => _remove(e),
                            ),
                          );
                        },
                      ),
                    ],
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: MediaQuery.paddingOf(context).bottom + 28,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _BucketHeader extends StatelessWidget {
  const _BucketHeader({required this.bucket, required this.count});

  final ReleaseBucket bucket;
  final int count;

  @override
  Widget build(BuildContext context) {
    final label = switch (bucket) {
      ReleaseBucket.today => 'release_notify.feed_today',
      ReleaseBucket.yesterday => 'release_notify.feed_yesterday',
      ReleaseBucket.thisWeek => 'release_notify.feed_week',
      ReleaseBucket.earlier => 'release_notify.feed_earlier',
    }.tr();
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(18, 18, 18, 8),
      child: Row(
        children: [
          if (bucket == ReleaseBucket.today) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.6),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$count',
            style: const TextStyle(
              color: AppColors.textHint,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 1,
              color: AppColors.divider.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

/// Swipe towards the reading end to mark seen, the other way to remove.
class _SwipeRow extends StatelessWidget {
  const _SwipeRow({
    required this.entry,
    required this.onSeen,
    required this.onRemove,
  });

  final ReleaseEntry entry;
  final VoidCallback onSeen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    Widget backdrop(bool start) {
      final seen = start;
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 22),
        alignment: start
            ? AlignmentDirectional.centerStart
            : AlignmentDirectional.centerEnd,
        decoration: BoxDecoration(
          color: (seen ? AppColors.success : AppColors.error).withValues(
            alpha: 0.22,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              seen ? Icons.done_rounded : Icons.delete_outline_rounded,
              color: seen ? AppColors.success : AppColors.errorLight,
            ),
            const SizedBox(height: 4),
            Text(
              seen
                  ? 'release_notify.action_seen'.tr()
                  : 'release_notify.feed_remove'.tr(),
              style: TextStyle(
                color: seen ? AppColors.success : AppColors.errorLight,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    return Dismissible(
      key: ValueKey('release-${entry.key}-${entry.seen}'),
      direction: entry.seen
          ? DismissDirection.endToStart
          : DismissDirection.horizontal,
      background: backdrop(true),
      secondaryBackground: backdrop(false),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          onSeen();
          return false;
        }
        return true;
      },
      onDismissed: (_) => onRemove(),
      child: ReleaseCard(entry: entry, onSeen: onSeen),
    );
  }
}

@visibleForTesting
class ReleaseCard extends StatelessWidget {
  const ReleaseCard({super.key, required this.entry, required this.onSeen});

  final ReleaseEntry entry;
  final VoidCallback onSeen;

  @override
  Widget build(BuildContext context) {
    final fresh = !entry.seen;
    final reading = entry.isReading;
    final cta = (reading ? 'release_notify.feed_read' : 'release_notify.feed_watch')
        .tr();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 250),
        opacity: fresh ? 1 : 0.62,
        child: HoverTap(
          onTap: () => openRelease(context, entry),
          borderRadius: 16,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: fresh
                    ? AppColors.primary.withValues(alpha: 0.35)
                    : AppColors.border.withValues(alpha: 0.4),
              ),
              boxShadow: fresh
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.10),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 78,
                  height: 112,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ReleasePoster(url: entry.thumbnail, radius: 11),
                      PositionedDirectional(
                        start: 5,
                        bottom: 5,
                        child: _ModeBadge(mode: entry.mode),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  // At least the poster's height, taller when the text is.
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 112),
                    child: IntrinsicHeight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  entry.title.isEmpty ? '—' : entry.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w800,
                                    height: 1.25,
                                  ),
                                ),
                              ),
                              if (fresh) ...[
                                const SizedBox(width: 6),
                                const NewBadge(),
                              ],
                            ],
                          ),
                          const SizedBox(height: 7),
                          Row(
                            children: [
                              Flexible(
                                child: EpisodePill(
                                  text: releaseEpisodeLabel(entry),
                                  strong: fresh,
                                ),
                              ),
                              const SizedBox(width: 7),
                              Flexible(
                                child: Text(
                                  releaseAgo(entry.time),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.textHint,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Spacer(),
                          Row(
                            children: [
                              Flexible(
                                child: FilledButton.icon(
                                  onPressed: () => openRelease(context, entry),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: fresh
                                        ? Colors.white
                                        : AppColors.surfaceVariant,
                                    foregroundColor: fresh
                                        ? Colors.black
                                        : AppColors.textPrimary,
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    minimumSize: const Size(0, 34),
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(kButtonRadius),
                                    ),
                                    textStyle: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  icon: Icon(
                                    reading
                                        ? Icons.menu_book_rounded
                                        : Icons.play_arrow_rounded,
                                    size: 18,
                                  ),
                                  label: Text(
                                    cta,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              if (fresh)
                                IconButton(
                                  tooltip: 'release_notify.action_seen'.tr(),
                                  visualDensity: VisualDensity.compact,
                                  onPressed: onSeen,
                                  icon: const Icon(
                                    Icons.done_rounded,
                                    size: 20,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
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

class _ModeBadge extends StatelessWidget {
  const _ModeBadge({required this.mode});

  final String mode;

  @override
  Widget build(BuildContext context) {
    final icon = switch (mode) {
      'manga' => Icons.auto_stories_rounded,
      'novel' => Icons.menu_book_rounded,
      _ => Icons.movie_rounded,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: Colors.white),
          const SizedBox(width: 3),
          Text(
            releaseModeLabel(mode).toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 8.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// Nothing yet: a quiet stack of blank posters with a bell over them, and the
/// two ways forward — check now, or go and follow something.
class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed({required this.onCheck, required this.checking});

  final VoidCallback onCheck;
  final bool checking;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 32),
      children: [
        SizedBox(height: MediaQuery.sizeOf(context).height * 0.12),
        const ItemAppear(index: 0, child: _EmptyArt()),
        const SizedBox(height: 26),
        ItemAppear(
          index: 1,
          child: Text(
            'release_notify.feed_empty_title'.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 8),
        ItemAppear(
          index: 2,
          child: Text(
            'release_notify.feed_empty_body'.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
              height: 1.45,
            ),
          ),
        ),
        const SizedBox(height: 22),
        ItemAppear(
          index: 3,
          child: Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: checking ? null : onCheck,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text('release_notify.feed_check'.tr()),
                ),
                OutlinedButton.icon(
                  onPressed: () => context.push('/following'),
                  icon: const Icon(Icons.bookmark_added_outlined, size: 18),
                  label: Text('tracker.title'.tr()),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyArt extends StatelessWidget {
  const _EmptyArt();

  @override
  Widget build(BuildContext context) {
    Widget blank(double angle, double dx, double opacity) => Transform.translate(
      offset: Offset(dx, 0),
      child: Transform.rotate(
        angle: angle,
        child: Opacity(
          opacity: opacity,
          child: Container(
            width: 74,
            height: 106,
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
            ),
            child: Align(
              alignment: const Alignment(0, 0.7),
              child: Container(
                width: 40,
                height: 6,
                decoration: BoxDecoration(
                  color: AppColors.textHint.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return SizedBox(
      height: 140,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 170,
            height: 140,
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [
                  AppColors.primary.withValues(alpha: 0.18),
                  AppColors.primary.withValues(alpha: 0),
                ],
              ),
            ),
          ),
          blank(-0.16, -52, 0.55),
          blank(0.16, 52, 0.55),
          blank(0, 0, 1),
          Positioned(
            top: 4,
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.5),
                    blurRadius: 16,
                  ),
                ],
              ),
              child: Icon(
                Icons.notifications_none_rounded,
                color: AppColors.onPrimary,
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
