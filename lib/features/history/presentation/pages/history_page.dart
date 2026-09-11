import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/system/platform_utils.dart';
import 'package:soplay/core/theme/kaizoku_colors.dart';
import 'package:soplay/features/profile/presentation/widgets/library_accents.dart';
import 'package:soplay/features/detail/domain/entities/detail_args.dart';
import 'package:soplay/features/history/data/history_service.dart';
import 'package:soplay/features/history/data/history_sync_service.dart';
import 'package:soplay/features/history/domain/entities/history_item.dart';
import 'package:soplay/features/home/presentation/widgets/home_shared_widgets.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final HistoryService _historyService = getIt<HistoryService>();
  final HistorySyncService _syncService = getIt<HistorySyncService>();
  List<HistoryItem> _items = const [];

  @override
  void initState() {
    super.initState();
    _historyService.revision.addListener(_reload);
    // Cached first, then synced. Waiting on the network to draw a list that is
    // already on disk would leave the screen empty on a slow link; the reload
    // is driven by the service's own revision notifier once rows land.
    _reload();
    _syncService.sync();
  }

  @override
  void dispose() {
    _historyService.revision.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    final items = _historyService.getAll();
    if (!mounted) return;
    setState(() => _items = items);
  }

  void _clearHistory() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KaizokuColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
        title: Text(
          'history.clear_title'.tr(),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'history.clear_confirm'.tr(),
          style: const TextStyle(color: KaizokuColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'general.cancel'.tr(),
              style: const TextStyle(color: KaizokuColors.textMuted),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              // Tombstone first, then clear: once the rows are gone there is
              // nothing left to describe the delete, and the next sync would
              // download the whole list straight back.
              _syncService
                  .rememberClearedAll()
                  .then((_) => _historyService.clearAll())
                  .then((_) => _syncService.sync());
              // Appearance suggests accents from these posters and caches the
              // result for the app run. With the library gone, the cache is
              // suggesting colours from titles the user just deleted.
              LibraryAccents.invalidate();
            },
            child: Text(
              'history.clear'.tr(),
              style: const TextStyle(
                color: KaizokuColors.neonCrimson,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _removeItem(HistoryItem item) {
    if (mounted) {
      setState(() {
        _items = _items.where((e) => e.storageKey != item.storageKey).toList();
      });
    }
    _syncService
        .rememberDeleted(item)
        .then((_) => _historyService.remove(item.storageKey))
        .then((_) => _syncService.sync());
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: KaizokuColors.cyberObsidian,
      body: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // Pinned: "Clear all" and the back button are the only controls on
          // this screen, and a long history scrolled them out of reach.
          SliverAppBar(
            pinned: true,
            automaticallyImplyLeading: false,
            backgroundColor: KaizokuColors.cyberObsidian,
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
                    'profile.watch_history'.tr(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (_items.isNotEmpty)
                  _PillButton(
                    label: 'history.clear_all'.tr(),
                    onTap: _clearHistory,
                  ),
              ],
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
          if (_items.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyState(),
            )
          else
            SliverList.separated(
              itemCount: _items.length,
              separatorBuilder: (_, _) => Divider(
                color: KaizokuColors.surfaceLight.withValues(alpha: 0.5),
                height: 1,
                indent: 82,
              ),
              itemBuilder: (_, i) {
                final item = _items[i];
                return _HistoryRow(
                  item: item,
                  onTap: () {
                    context.push(
                      '/detail',
                      extra: DetailArgs(
                        contentUrl: item.contentUrl,
                        autoPlay: true,
                        resumeEpisodeIndex: item.episodeIndex,
                        provider: item.provider,
                      ),
                    );
                  },
                  onDismissed: () => _removeItem(item),
                );
              },
            ),
          SliverToBoxAdapter(child: SizedBox(height: bottomPad + 24)),
        ],
      ),
    );
  }
}

class _CircleBackButton extends StatelessWidget {
  const _CircleBackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
      ),
      child: Material(
        color: KaizokuColors.surface,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: const SizedBox(
            width: 36,
            height: 36,
            child: Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white,
              size: 16,
            ),
          ),
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: KaizokuColors.neonCrimson.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: KaizokuColors.neonCrimson.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Text(
            label,
            style: const TextStyle(
              color: KaizokuColors.neonCrimson,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.item,
    required this.onTap,
    required this.onDismissed,
  });

  final HistoryItem item;
  final VoidCallback onTap;
  final VoidCallback onDismissed;

  /// Swiping is the only way to delete a row on a phone, and nothing on screen
  /// advertises it. Long-press offers the same action out in the open.
  Future<void> _showActions(BuildContext context) async {
    final remove = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: KaizokuColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetCtx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: KaizokuColors.surfaceLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(
                Icons.delete_outline_rounded,
                color: KaizokuColors.neonCrimson,
              ),
              title: Text(
                'history.remove'.tr(),
                style: const TextStyle(
                  color: KaizokuColors.neonCrimson,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () => Navigator.of(sheetCtx).pop(true),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (remove ?? false) onDismissed();
  }

  @override
  Widget build(BuildContext context) {
    final row = InkWell(
        onTap: onTap,
        onLongPress: isDesktopPlatform ? null : () => _showActions(context),
        splashColor: KaizokuColors.neonCrimson.withValues(alpha: 0.1),
        highlightColor: Colors.white.withValues(alpha: 0.05),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 76,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                    width: 0.8,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    HomeNetworkImage(
                      url: item.thumbnail,
                      borderRadius: BorderRadius.zero,
                      placeholderIcon: Icons.movie_outlined,
                    ),
                    if (item.progress > 0)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(
                          value: item.progress,
                          minHeight: 3.5,
                          backgroundColor: KaizokuColors.surface,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            KaizokuColors.neonCrimson,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (item.isSerial && item.episodeNumber != null) ...[
                          Text(
                            'EP ${item.episodeNumber}',
                            style: const TextStyle(
                              color: KaizokuColors.neonCrimson,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (item.episodeLabel != null &&
                              item.episodeLabel!.trim().isNotEmpty)
                            Expanded(
                              child: Text(
                                ' · ${item.episodeLabel}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: KaizokuColors.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                        ],
                        if (!item.isSerial && item.durationMs > 0)
                          Text(
                            _formatProgress(item),
                            style: const TextStyle(
                              color: KaizokuColors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _watchedAgo(context, item.watchedAt),
                      style: const TextStyle(
                        color: KaizokuColors.textMuted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: KaizokuColors.neonCrimson.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: KaizokuColors.neonCrimson.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: KaizokuColors.neonCrimson,
                  size: 22,
                ),
              ),
            ],
          ),
        ),
      );

    if (isDesktopPlatform) {
      return Row(
        children: [
          Expanded(child: row),
          IconButton(
            tooltip: 'history.remove'.tr(),
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: KaizokuColors.textMuted,
            ),
            hoverColor: KaizokuColors.neonCrimson.withValues(alpha: 0.15),
            onPressed: onDismissed,
          ),
          const SizedBox(width: 8),
        ],
      );
    }

    return Dismissible(
      key: ValueKey(item.storageKey),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDismissed(),
      background: _SwipeToRemoveBackground(label: 'history.remove'.tr()),
      child: row,
    );
  }

  String _formatProgress(HistoryItem item) {
    final pos = Duration(milliseconds: item.positionMs);
    final dur = Duration(milliseconds: item.durationMs);
    return '${_fmt(pos)} / ${_fmt(dur)}';
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    String two(int n) => n.toString().padLeft(2, '0');
    if (h > 0) return '${two(h)}:${two(m)}:${two(s)}';
    return '${two(m)}:${two(s)}';
  }

  /// Same shape as the notifications list, which is the app's only other
  /// timestamped feed — the two used to disagree, in English only.
  String _watchedAgo(BuildContext context, int ms) {
    final at = DateTime.fromMillisecondsSinceEpoch(ms);
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 1) return 'time.now'.tr();
    if (diff.inHours < 1) return 'time.minutes'.tr(args: ['${diff.inMinutes}']);
    if (diff.inDays < 1) return 'time.hours'.tr(args: ['${diff.inHours}']);
    if (diff.inDays < 7) return 'time.days'.tr(args: ['${diff.inDays}']);
    return DateFormat.yMMMd(context.locale.toString()).format(at);
  }
}

class _SwipeToRemoveBackground extends StatelessWidget {
  const _SwipeToRemoveBackground({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: AlignmentDirectional.centerEnd,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      color: KaizokuColors.neonCrimson,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 22),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: KaizokuColors.surface,
              border: Border.all(
                color: KaizokuColors.neonCrimson.withValues(alpha: 0.3),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: KaizokuColors.neonCrimson.withValues(alpha: 0.12),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(
              Icons.history_rounded,
              color: KaizokuColors.neonCrimson,
              size: 34,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'history.empty_title'.tr(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'history.empty_subtitle'.tr(),
            style: const TextStyle(
              color: KaizokuColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
