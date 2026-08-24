import 'dart:ui';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/system/platform_utils.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/tv/tv.dart';
import 'package:soplay/features/detail/domain/entities/episode_entity.dart';
import 'package:soplay/features/detail/domain/entities/episodes_args.dart';
import 'package:soplay/features/detail/domain/entities/player_args.dart';
import 'package:soplay/core/extensions/provider_media_kind.dart';
import 'package:soplay/features/manga/domain/entities/reader_args.dart';
import 'package:soplay/features/manga/domain/entities/manga_pages_entity.dart';
import 'package:soplay/features/detail/domain/usecases/get_episodes_usecase.dart';
import 'package:soplay/features/detail/domain/usecases/get_pages_usecase.dart';
import 'package:soplay/features/download/data/download_service.dart';
import 'package:soplay/features/download/domain/entities/download_item.dart';
import 'package:soplay/features/history/data/history_service.dart';
import 'package:soplay/features/history/domain/entities/history_item.dart';

class EpisodesPage extends StatefulWidget {
  const EpisodesPage({super.key, required this.args});
  final EpisodesArgs args;

  @override
  State<EpisodesPage> createState() => _EpisodesPageState();
}

class _EpisodesPageState extends State<EpisodesPage> {
  final ScrollController _scroll = ScrollController();
  final ValueNotifier<double> _blurProgress = ValueNotifier<double>(0);
  final HistoryService _historyService = getIt<HistoryService>();
  final DownloadService _downloads = getIt<DownloadService>();
  late final GetEpisodesUseCase _getEpisodes;

  /// Reading source (manga / manhwa / novel) rather than a video source.
  ///
  /// Resolved through [ProviderMediaKindX] instead of a `mn:` prefix test: a
  /// Mangayomi provider (`my:`) can be manga, novel OR anime under the same
  /// prefix, so only the source's declared item type can answer this.
  bool get _isManga => widget.args.provider.opensReader;

  late List<EpisodeEntity> _episodes;
  late int _page;
  late int _totalPages;
  late int _total;
  late int _size;
  String _sort = 'asc';
  bool _loadingMore = false;
  bool _resorting = false;
  bool _showImages = false;
  String? _error;

  HistoryItem? _historyItem;

  @override
  void initState() {
    super.initState();
    _getEpisodes = getIt<GetEpisodesUseCase>();
    _episodes = List.of(widget.args.episodes);
    _page = widget.args.page;
    _totalPages = widget.args.totalPages;
    _total = widget.args.total > 0 ? widget.args.total : _episodes.length;
    _size = widget.args.size;
    _showImages = _hasAnyImage(_episodes);
    _scroll.addListener(_onScroll);
    _historyService.revision.addListener(_refreshHistory);
    _downloads.revision.addListener(_onDownloadsChanged);
    _refreshHistory();
    _maybeAutoFill();
  }

  void _maybeAutoFill() {
    if (!isDesktopPlatform) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      if (!_loadingMore &&
          _page < _totalPages &&
          _scroll.position.maxScrollExtent <= 0) {
        _loadMore();
      }
    });
  }

  void _onDownloadsChanged() {
    if (mounted) setState(() {});
  }

  void _refreshHistory() {
    final item = _historyService.get(widget.args.contentUrl);
    if (!mounted) return;
    setState(() => _historyItem = item);
  }

  static bool _hasAnyImage(List<EpisodeEntity> list) {
    for (final e in list) {
      final img = e.image;
      if (img != null && img.isNotEmpty) return true;
    }
    return false;
  }

  @override
  void dispose() {
    _historyService.revision.removeListener(_refreshHistory);
    _downloads.revision.removeListener(_onDownloadsChanged);
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _blurProgress.dispose();
    super.dispose();
  }

  void _onScroll() {
    final next = (_scroll.offset / 80).clamp(0.0, 1.0);
    if ((next - _blurProgress.value).abs() >= 0.015) {
      _blurProgress.value = next;
    }

    if (!_loadingMore &&
        _page < _totalPages &&
        _scroll.position.pixels >= _scroll.position.maxScrollExtent - 600) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _page >= _totalPages) return;
    if (widget.args.contentUrl.isEmpty) return;
    setState(() {
      _loadingMore = true;
      _error = null;
    });

    final result = await _getEpisodes(
      widget.args.contentUrl,
      page: _page + 1,
      size: _size,
      sort: _sort,
      provider: widget.args.provider,
    );

    if (!mounted) return;
    switch (result) {
      case Success(:final value):
        final merged = [..._episodes, ...value.episodes];
        setState(() {
          _page = value.page;
          _totalPages = value.totalPages;
          _total = value.total > 0 ? value.total : _total;
          _episodes = merged;
          _showImages = _showImages || _hasAnyImage(value.episodes);
          _loadingMore = false;
        });
        _maybeAutoFill();
      case Failure(:final error):
        setState(() {
          _loadingMore = false;
          _error = error.toString().replaceFirst('Exception: ', '');
        });
    }
  }

  Future<void> _toggleSort() async {
    if (_resorting || widget.args.contentUrl.isEmpty) return;
    final next = _sort == 'asc' ? 'desc' : 'asc';
    setState(() {
      _resorting = true;
      _error = null;
    });
    final result = await _getEpisodes(
      widget.args.contentUrl,
      page: 1,
      size: _size,
      sort: next,
      provider: widget.args.provider,
    );
    if (!mounted) return;
    switch (result) {
      case Success(:final value):
        final fresh = List.of(value.episodes);
        setState(() {
          _sort = next;
          _episodes = fresh;
          _page = value.page;
          _totalPages = value.totalPages;
          _total = value.total > 0 ? value.total : _total;
          _showImages = _hasAnyImage(fresh);
          _resorting = false;
        });
        if (_scroll.hasClients) {
          _scroll.animateTo(
            0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      case Failure(:final error):
        setState(() {
          _resorting = false;
          _error = error.toString().replaceFirst('Exception: ', '');
        });
    }
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/main');
    }
  }

  void _playFrom(int index) {
    final isHistoryEntry = _historyItem != null &&
        _historyItem!.episodeIndex == index &&
        _historyItem!.positionMs > 0;

    if (_isManga) {
      context.push(
        '/reader',
        extra: ReaderArgs(
          title: widget.args.title,
          provider: widget.args.provider,
          contentUrl: widget.args.contentUrl,
          thumbnail: widget.args.thumbnail,
          chapters: _episodes,
          initialChapterIndex: index,
          resumePage: isHistoryEntry ? _historyItem!.positionMs : 0,
        ),
      );
      return;
    }

    final resumeMs = isHistoryEntry ? _historyItem!.positionMs : 0;
    context.push(
      '/player',
      extra: PlayerArgs(
        title: widget.args.title,
        provider: widget.args.provider,
        headers: widget.args.headers,
        contentUrl: widget.args.contentUrl,
        thumbnail: widget.args.thumbnail,
        episodes: _episodes,
        initialEpisodeIndex: index,
        resumePosition: Duration(milliseconds: resumeMs),
      ),
    );
  }

  Future<void> _downloadChapter(int index) async {
    final ch = _episodes[index];
    final id = DownloadService.mangaChapterId(
      contentUrl: widget.args.contentUrl,
      provider: widget.args.provider,
      chapterRef: ch.mediaRef,
    );
    final existing = _downloads.get(id);
    if (existing != null &&
        (existing.status == DownloadStatus.downloading ||
            existing.status == DownloadStatus.completed)) {
      return;
    }

    final result = await getIt<GetPagesUseCase>()(
      ref: ch.mediaRef,
      provider: widget.args.provider,
    );
    if (!mounted) return;
    if (result is! Success<MangaPagesEntity>) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('detail.failed_resolve_pages'.tr())),
      );
      return;
    }

    final pages = result.value;
    final item = DownloadItem(
      id: id,
      kind: 'manga',
      contentUrl: widget.args.contentUrl,
      provider: widget.args.provider,
      title: widget.args.title,
      thumbnail: widget.args.thumbnail,
      videoUrl: '',
      localPath: '',
      headers: pages.headers,
      pageUrls: pages.pages.map((p) => p.imageUrl).toList(),
      chapterRef: ch.mediaRef,
      chapterIndex: index,
      isSerial: true,
      episodeNumber: ch.episode,
      episodeLabel: ch.label,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _downloads.startDownload(item);
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    final appBarH = topPad + 56;
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Stack(
          children: [
            _episodes.isEmpty
                ? const _EmptyState()
                : CustomScrollView(
                    controller: _scroll,
                    slivers: [
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(16, appBarH + 8, 16, 8),
                        sliver: SliverToBoxAdapter(
                          child: Row(
                            children: [
                              Expanded(
                                child: _CountHeader(
                                  loaded: _episodes.length,
                                  total: _total,
                                ),
                              ),
                              _SortToggle(
                                sort: _sort,
                                busy: _resorting,
                                onTap: _toggleSort,
                              ),
                            ],
                          ),
                        ),
                      ),
                      SliverList.separated(
                        itemCount: _episodes.length,
                        // Indents line up with where the row's label starts:
                        // 16 + 88 thumb + 12, or 16 + 44 number + 12.
                        separatorBuilder: (_, _) => Divider(
                          color: AppColors.divider,
                          height: 1,
                          indent: _showImages ? 116 : 72,
                        ),
                        itemBuilder: (_, i) {
                          final isCurrent = _historyItem != null &&
                              _historyItem!.episodeIndex == i;
                          DownloadItem? download;
                          if (_isManga) {
                            final id = DownloadService.mangaChapterId(
                              contentUrl: widget.args.contentUrl,
                              provider: widget.args.provider,
                              chapterRef: _episodes[i].mediaRef,
                            );
                            download = _downloads.get(id);
                          }
                          return _EpisodeRow(
                            episode: _episodes[i],
                            showImage: _showImages,
                            progress: isCurrent ? _historyItem!.progress : null,
                            onTap: () => _playFrom(i),
                            onDownload:
                                _isManga ? () => _downloadChapter(i) : null,
                            download: download,
                          );
                        },
                      ),
                      if (_loadingMore)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 22),
                            child: Center(
                              child: SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  color: AppColors.primary,
                                  strokeWidth: 2.4,
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (_error != null)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                            child: _LoadMoreError(
                              message: _error!,
                              onRetry: _loadMore,
                            ),
                          ),
                        ),
                      SliverToBoxAdapter(child: SizedBox(height: bottomPad + 24)),
                    ],
                  ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: ValueListenableBuilder<double>(
                valueListenable: _blurProgress,
                builder: (_, progress, _) => _EpisodesAppBar(
                  title: widget.args.title,
                  blurProgress: progress,
                  onBack: _goBack,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EpisodesAppBar extends StatelessWidget {
  const _EpisodesAppBar({
    required this.title,
    required this.blurProgress,
    required this.onBack,
  });

  final String title;
  final double blurProgress;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    final progress = blurProgress.clamp(0.0, 1.0);

    final content = Container(
      height: topPad + 56,
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.9 * progress),
        border: progress > 0.05
            ? Border(
                bottom: BorderSide(
                  color: Colors.white.withValues(alpha: 0.07 * progress),
                  width: 0.5,
                ),
              )
            : null,
      ),
      padding: EdgeInsets.fromLTRB(4, topPad + 4, 16, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 20,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
            ),
          ),
        ],
      ),
    );

    if (progress < 0.01) return content;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20 * progress, sigmaY: 20 * progress),
        child: content,
      ),
    );
  }
}

class _SortToggle extends StatelessWidget {
  const _SortToggle({
    required this.sort,
    required this.busy,
    required this.onTap,
  });
  final String sort;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDesc = sort == 'desc';
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.textSecondary,
                  ),
                )
              else
                Icon(
                  isDesc
                      ? Icons.arrow_downward_rounded
                      : Icons.arrow_upward_rounded,
                  color: AppColors.textPrimary,
                  size: 16,
                ),
              const SizedBox(width: 6),
              Text(
                isDesc ? 'search.sort_newest'.tr() : 'search.sort_oldest'.tr(),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountHeader extends StatelessWidget {
  const _CountHeader({required this.loaded, required this.total});
  final int loaded;
  final int total;

  @override
  Widget build(BuildContext context) {
    final showOf = total > 0 && total > loaded;
    final label = showOf
        ? 'detail.episodes_count_of'.tr(args: ['$loaded', '$total'])
        : 'detail.episodes_count'.tr(args: ['$total']);
    return Text(
      label,
      style: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

class _LoadMoreError extends StatelessWidget {
  const _LoadMoreError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 0.6),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.textHint,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
          TextButton(onPressed: onRetry, child: Text('general.retry'.tr())),
        ],
      ),
    );
  }
}

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({
    required this.episode,
    required this.showImage,
    required this.onTap,
    this.progress,
    this.onDownload,
    this.download,
  });

  final EpisodeEntity episode;
  final bool showImage;
  final VoidCallback onTap;
  final double? progress;
  final VoidCallback? onDownload;
  final DownloadItem? download;

  @override
  Widget build(BuildContext context) {
    final hasSub = episode.hasSub == true;
    final hasDub = episode.hasDub == true;
    final label = episode.label.isNotEmpty
        ? episode.label
        : 'detail.episode_n'.tr(args: ['${episode.episode}']);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: showImage ? 8 : 14,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (showImage) ...[
                  _EpisodeThumb(image: episode.image, episode: episode.episode),
                  const SizedBox(width: 12),
                ] else
                  SizedBox(
                    width: 44,
                    child: Text(
                      '${episode.episode}'.padLeft(2, '0'),
                      style: TextStyle(
                        color: progress != null ? AppColors.primary : AppColors.textHint,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                if (!showImage) const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        maxLines: showImage ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: showImage
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                          fontSize: showImage ? 13 : 14,
                          fontWeight:
                              showImage ? FontWeight.w600 : FontWeight.w500,
                          height: 1.25,
                        ),
                      ),
                      if (showImage && _meta(episode).isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          _meta(episode),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textHint,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (hasSub) const _LangChip(label: 'SUB', primary: true),
                if (hasSub && hasDub) const SizedBox(width: 4),
                if (hasDub) const _LangChip(label: 'DUB', primary: false),
                if (hasSub || hasDub) const SizedBox(width: 10),
                if (onDownload != null) ...[
                  _DownloadControl(
                    download: download,
                    onDownload: onDownload!,
                  ),
                  const SizedBox(width: 8),
                ],
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: progress != null
                        ? AppColors.primary.withValues(alpha: 0.15)
                        : AppColors.surfaceVariant,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    onDownload != null
                        ? Icons.menu_book_outlined
                        : Icons.play_arrow_rounded,
                    color: progress != null
                        ? AppColors.primary
                        : AppColors.textPrimary,
                    size: 18,
                  ),
                ),
              ],
            ),
            if (progress != null)
              Padding(
                padding: EdgeInsets.only(
                  left: showImage ? 0 : 56,
                  top: 6,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(1.5),
                  child: LinearProgressIndicator(
                    value: progress!,
                    minHeight: 3,
                    backgroundColor: AppColors.divider,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.primary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _meta(EpisodeEntity e) {
    final parts = <String>[];
    final air = e.airdate;
    final run = e.runtime;
    if (air != null && air.isNotEmpty) parts.add(air);
    if (run != null && run.isNotEmpty) parts.add(run);
    return parts.join(' · ');
  }
}

class _DownloadControl extends StatelessWidget {
  const _DownloadControl({required this.download, required this.onDownload});

  final DownloadItem? download;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final status = download?.status;

    if (status == DownloadStatus.downloading || status == DownloadStatus.pending) {
      final d = download!;
      return SizedBox(
        width: 34,
        height: 34,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              value: status == DownloadStatus.downloading && d.totalBytes > 0
                  ? d.progress
                  : null,
              strokeWidth: 2,
              color: AppColors.primary,
            ),
          ),
        ),
      );
    }

    if (status == DownloadStatus.completed) {
      return Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.download_done_rounded,
          color: AppColors.success,
          size: 18,
        ),
      );
    }

    final failed = status == DownloadStatus.failed;
    final button = Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        shape: BoxShape.circle,
      ),
      child: Icon(
        failed ? Icons.refresh_rounded : Icons.download_outlined,
        // The retry glyph IS the failure signal on this row — it has to stay
        // red rather than turn into whatever the accent is.
        color: failed ? AppColors.error : AppColors.textSecondary,
        size: 18,
      ),
    );

    // Android TV: the episode row itself is an InkWell (focusable for free),
    // but this download control sat on a bare GestureDetector, so a remote
    // could play an episode and never download one. Off TV: unchanged.
    if (isTvPlatform) {
      return TvFocusable(
        onPressed: onDownload,
        borderRadius: 17,
        child: button,
      );
    }

    return GestureDetector(onTap: onDownload, child: button);
  }
}

class _EpisodeThumb extends StatelessWidget {
  const _EpisodeThumb({required this.image, required this.episode});
  final String? image;
  final int episode;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 88,
        height: 50,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (image != null && image!.isNotEmpty)
              Image.network(
                image!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const _ThumbFallback(),
                loadingBuilder: (_, child, chunk) =>
                    chunk == null ? child : const _ThumbFallback(),
              )
            else
              const _ThumbFallback(),
            Positioned(
              left: 4,
              bottom: 3,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  episode.toString().padLeft(2, '0'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThumbFallback extends StatelessWidget {
  const _ThumbFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceVariant,
      alignment: Alignment.center,
      child: const Icon(
        Icons.movie_outlined,
        color: AppColors.textHint,
        size: 18,
      ),
    );
  }
}

class _LangChip extends StatelessWidget {
  const _LangChip({required this.label, required this.primary});
  final String label;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final color = primary ? AppColors.primary : AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
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
          const Icon(
            Icons.video_library_outlined,
            color: AppColors.textHint,
            size: 48,
          ),
          const SizedBox(height: 12),
          Text(
            'detail.no_episodes'.tr(),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
