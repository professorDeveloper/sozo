import 'dart:async';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/features/detail/presentation/widgets/player_engine_sheet.dart';
import 'package:soplay/features/detail/domain/episode_blocks.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/system/platform_utils.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/tv/tv.dart';
import 'package:soplay/features/detail/domain/download_choices.dart';
import 'package:soplay/features/detail/domain/entities/episode_entity.dart';
import 'package:soplay/features/detail/domain/entities/episodes_args.dart';
import 'package:soplay/features/detail/domain/entities/player_args.dart';
import 'package:soplay/core/extensions/provider_media_kind.dart';
import 'package:soplay/features/manga/domain/entities/reader_args.dart';
import 'package:soplay/features/manga/domain/entities/manga_pages_entity.dart';
import 'package:soplay/features/detail/domain/usecases/get_episodes_usecase.dart';
import 'package:soplay/features/detail/domain/usecases/get_pages_usecase.dart';
import 'package:soplay/features/detail/domain/usecases/resolve_media_usecase.dart';
import 'package:soplay/features/detail/domain/entities/media_resolve_entity.dart';
import 'package:soplay/features/download/domain/entities/download_item.dart';
import 'package:soplay/features/download/domain/entities/download_request.dart';
import 'package:soplay/features/download/domain/entities/download_status.dart';
import 'package:soplay/features/download/domain/repositories/download_repository.dart';
import 'package:soplay/features/download/domain/usecases/enqueue_download_usecase.dart';
import 'package:soplay/features/download/domain/usecases/get_downloads_usecase.dart';
import 'package:soplay/features/download/presentation/download_messages.dart';
import 'package:soplay/features/history/data/history_service.dart';
import 'package:soplay/features/history/domain/entities/history_item.dart';

/// Focus highlight for the full-width rows on this page.
///
/// The same fill the player's episode, quality and settings rows use
/// (`_kTvFocusFill`, player_page.tv.dart) — those rows and these are the same
/// list to a viewer with a remote, and a row that highlights differently in one
/// of the two places reads as a different kind of thing. It is a fill rather
/// than an outline because a ring on a full-width row dominates the screen from
/// across a room.
///
/// Null off TV, which is what these `InkWell`s passed before, so phone and
/// desktop keep the theme default and render unchanged.
Color? get _kTvRowFocusFill =>
    isTvPlatform ? AppColors.primary.withValues(alpha: 0.22) : null;

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
  final GetDownloadsUseCase _downloads = getIt<GetDownloadsUseCase>();
  final EnqueueDownloadUseCase _enqueue = getIt<EnqueueDownloadUseCase>();
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
  String? _error;

  /// Whether rows carry a thumbnail. Decided once, from the first page.
  ///
  /// It used to be recomputed on every scroll-load and reassigned on sort and
  /// on jump: one image arriving with page three grew every row above it under
  /// a moving finger, and a jump into a block whose source shipped no stills
  /// shrank them all back. Row height is a layout decision, and a layout
  /// decision that changes mid-scroll throws away the reader's place.
  late final bool _showImages;

  HistoryItem? _historyItem;

  /// Indices picked in multi-select. Empty means normal browsing.
  ///
  /// Downloading a season one tap at a time is the kind of chore that makes
  /// people give up and leave the app open on wifi overnight instead. Picking a
  /// run of episodes and queueing them in one go is the whole point of having a
  /// download queue at all.
  final Set<int> _selected = <int>{};

  /// True while a batch is being resolved and queued. Each episode needs its
  /// own resolve call, which is a network round trip per item, so the UI has to
  /// say it is working rather than looking frozen.
  bool _queueing = false;

  /// Where the loaded window starts in the whole run.
  ///
  /// Zero while paging forward from the top, which is every ordinary series.
  /// It moves only when a range chip jumps straight to a later block, and it
  /// exists so the rows still know their real position — a download id, and
  /// the episode handed to the player, must not change meaning because
  /// somebody skipped ahead.
  int _indexOffset = 0;

  /// True while a range jump is in flight.
  bool _jumping = false;

  /// Filters the loaded window down to episodes matching a typed number.
  ///
  /// Deliberately a number and not a title: episode titles are missing on most
  /// sources, and "take me to 847" is the actual question someone asks of a
  /// thousand-episode run.
  final TextEditingController _filter = TextEditingController();
  String _query = '';

  /// A number a jump went looking for and the loaded page did not carry.
  ///
  /// Sources with gaps in their numbering exist, and the page arithmetic cannot
  /// see a gap. Remembering the miss keeps the action row from offering the
  /// same fruitless jump again, and lets the list say what happened.
  int? _jumpMiss;

  /// The row a jump landed on, tinted for a moment so the reader can see where
  /// they were put down.
  int? _flashIndex;
  Timer? _flashTimer;
  final GlobalKey _flashRowKey = GlobalKey();

  /// Identifies the episode sliver so the block strip can be told which block
  /// is actually on screen — see [_topVisiblePosition].
  final GlobalKey _listKey = GlobalKey();

  /// Caches for the two lists every build reads.
  ///
  /// [_visibleIndices] allocated a fresh `List<int>` — a thousand entries on a
  /// long run — on every build, and [_blocks] ran the whole block arithmetic
  /// twice in one build, once to decide whether to show the strip and once to
  /// fill it. Both change only when the window or the query changes, and while
  /// something is downloading the rows rebuild twice a second.
  List<int>? _visibleCache;
  List<EpisodeBlock>? _blocksCache;

  /// Which block the reader is looking at, as opposed to where the window
  /// starts.
  ///
  /// Scroll-loading appends without moving [_indexOffset], so at episode 480
  /// the window still started at page 1: the strip highlighted a chip left
  /// three hundred episodes ago, and [_jumpToBlock]'s same-page guard made the
  /// chip the reader was actually inside do nothing at all.
  int _activePage = 1;

  bool get _selecting => _selected.isNotEmpty;

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

  /// Drops the derived-list caches. Every place that replaces the window or the
  /// query has to call this, or the list keeps drawing the old one.
  void _invalidateDerived() {
    _visibleCache = null;
    _blocksCache = null;
  }

  @override
  void dispose() {
    _historyService.revision.removeListener(_refreshHistory);
    _flashTimer?.cancel();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _filter.dispose();
    _blurProgress.dispose();
    super.dispose();
  }

  void _onScroll() {
    final next = (_scroll.offset / 80).clamp(0.0, 1.0);
    if ((next - _blurProgress.value).abs() >= 0.015) {
      _blurProgress.value = next;
    }

    _syncActivePage();

    if (!_loadingMore &&
        _query.isEmpty &&
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
          _loadingMore = false;
          _invalidateDerived();
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
          // A selection is a set of POSITIONS, and every position in this list
          // has just come to mean a different episode. Ticking 1–10 ascending,
          // flipping the sort and pressing Download used to queue the last ten
          // episodes of the series, and the confirm dialog's bare count could
          // not show it. _jumpToBlock has cleared it for this reason all along.
          _selected.clear();
          // The window is page one again, whichever block it was before.
          _indexOffset = 0;
          _activePage = 1;
          _resorting = false;
          _invalidateDerived();
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

  /// Whether the row at [index] is the one history is pointing at.
  ///
  /// Matched on the episode NUMBER wherever history recorded one, because the
  /// position of an episode in this list is not a property of the episode. It
  /// changes when the sort is flipped and again when a range chip jumps to
  /// another block — and comparing positions meant the "continue" marker sat on
  /// whatever happened to be in slot 5, which after a sort toggle is a
  /// different episode entirely.
  ///
  /// The stored index remains the fallback for history written before the
  /// number was recorded, and there it is only trusted while the window still
  /// starts where that index was counted from.
  bool _isHistoryEpisode(int index) {
    final item = _historyItem;
    if (item == null || index < 0 || index >= _episodes.length) return false;
    final number = item.episodeNumber;
    if (number != null) return _episodes[index].episode == number;
    return _indexOffset == 0 && item.episodeIndex == index;
  }

  /// The rows to draw: everything loaded, or what matches what was typed.
  ///
  /// Numbers and titles both, because a source that ships episode titles makes
  /// "Marineford" a far better way to find an episode than counting to 385 —
  /// and a source that ships none loses nothing by the extra check.
  List<int> get _visibleIndices => _visibleCache ??= _computeVisible();

  List<int> _computeVisible() {
    if (_query.isEmpty) {
      return [for (var i = 0; i < _episodes.length; i++) i];
    }
    final q = _query.toLowerCase();
    return [
      for (var i = 0; i < _episodes.length; i++)
        if ('${_episodes[i].episode}'.contains(q) ||
            _episodes[i].label.toLowerCase().contains(q))
          i,
    ];
  }

  /// Jumpable blocks, one per server page, or empty when there is nothing to
  /// jump over.
  ///
  /// A thousand-episode run is 20+ scroll-loads away from its own ending, and
  /// the only way to reach a late episode was to sit there loading pages. The
  /// blocks are the pages the server already serves, so a jump is one request
  /// rather than every request in between.
  ///
  /// Numbers are derived from [_size] and the first episode actually loaded,
  /// not assumed to start at 1 — plenty of sources number from 0, and some
  /// carry a season's absolute numbering.
  List<EpisodeBlock> get _blocks => _blocksCache ??= _computeBlocks();

  List<EpisodeBlock> _computeBlocks() {
    if (_totalPages < 2) return const [];
    return episodeBlocks(
      total: _total,
      size: _size,
      descending: _sort == 'desc',
      firstNumber: _firstNumber,
    );
  }

  /// The number the whole run starts at, recovered from whichever window is
  /// loaded. In ascending order the first loaded episode is [_indexOffset]
  /// places into the run; in descending order it is that many places from the
  /// end.
  int get _firstNumber {
    final loaded = _episodes.isEmpty ? 1 : _episodes.first.episode;
    return _sort == 'asc'
        ? loaded - _indexOffset
        : loaded - (_total - 1 - _indexOffset);
  }

  /// Loads one block and shows it on its own, rather than appending.
  ///
  /// Replacing is the point: appending would mean fetching every page between
  /// here and there, which is the wait the blocks exist to remove.
  /// Loads [block] into the window.
  ///
  /// Returns whether the window actually changed. The caller needs to know:
  /// a failed request and "the episode is not on this page" are different
  /// answers that used to be indistinguishable, because both left `_episodes`
  /// untouched.
  Future<bool> _jumpToBlock(EpisodeBlock block) async {
    if (_jumping || block.page == _activePage) return false;
    if (widget.args.contentUrl.isEmpty) return false;
    setState(() {
      _jumping = true;
      _error = null;
      // A selection is a set of positions, and the positions are about to mean
      // something else.
      _selected.clear();
      // The filter searches the loaded window, and the window is being
      // replaced: a jump made with text in the field used to land on a list
      // filtered to nothing, which reads as an empty block.
      _query = '';
      _jumpMiss = null;
      _filter.clear();
      _invalidateDerived();
    });

    final result = await _getEpisodes(
      widget.args.contentUrl,
      page: block.page,
      size: _size,
      sort: _sort,
      provider: widget.args.provider,
    );
    if (!mounted) return false;
    switch (result) {
      case Success(:final value):
        setState(() {
          _episodes = List.of(value.episodes);
          _page = value.page;
          _totalPages = value.totalPages;
          _total = value.total > 0 ? value.total : _total;
          _indexOffset = (value.page - 1) * _size;
          _activePage = value.page;
          _jumping = false;
          _invalidateDerived();
        });
        if (_scroll.hasClients) _scroll.jumpTo(0);
        return true;
      case Failure(:final error):
        setState(() {
          _jumping = false;
          _error = error.toString().replaceFirst('Exception: ', '');
        });
        return false;
    }
  }

  /// Which block the window currently starts in.
  int get _pageOfWindow => _size < 1 ? 1 : (_indexOffset ~/ _size) + 1;

  void _setQuery(String value) {
    setState(() {
      _query = value.trim();
      _jumpMiss = null;
      _invalidateDerived();
    });
  }

  /// The typed filter read as an episode number, when it is one.
  int? get _queryNumber => _query.isEmpty ? null : int.tryParse(_query);

  /// The block holding the typed number, when the loaded window does not hold
  /// it — the offer behind the "go to episode 437" row.
  EpisodeBlock? get _jumpBlock {
    final number = _queryNumber;
    if (number == null || number == _jumpMiss) return null;
    if (_episodes.any((e) => e.episode == number)) return null;
    return blockContaining(
      number,
      total: _total,
      size: _size,
      descending: _sort == 'desc',
      firstNumber: _firstNumber,
    );
  }

  /// Loads the page holding [number] and puts that row at the top.
  Future<void> _jumpToEpisode(int number, EpisodeBlock block) async {
    final landed = await _jumpToBlock(block);
    if (!mounted) return;

    // The page never loaded — the request failed, or a jump was already in
    // flight. `_episodes` is untouched, and the number was known not to be in
    // the window (that was the precondition for offering the jump), so the
    // `indexWhere` below would always be -1. Reporting that as "episode 437 is
    // not on this page" is a lie about a request that never landed, and
    // setting `_jumpMiss` then suppressed the offer permanently, so there was
    // no way to retry short of retyping the query. Leave the offer standing;
    // the error banner _jumpToBlock set says what actually happened.
    if (!landed) return;

    final index = _episodes.indexWhere((e) => e.episode == number);
    if (index < 0) {
      // Genuinely absent: the page the arithmetic pointed at IS loaded and the
      // number is not on it — numbering with gaps, or a season's absolute
      // numbering. Putting the query back and saying so beats leaving the
      // reader on a block they never asked for with no explanation.
      setState(() {
        _query = '$number';
        _filter.text = '$number';
        _jumpMiss = number;
        _invalidateDerived();
      });
      return;
    }
    _flashRow(index);
  }

  /// Tints the row a jump landed on, long enough to find it and no longer.
  void _flashRow(int index) {
    _flashTimer?.cancel();
    setState(() => _flashIndex = index);
    _flashTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _flashIndex = null);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealRow(index));
  }

  /// Scrolls the flashed row to the top of the viewport.
  ///
  /// Two passes rather than one `Scrollable.ensureVisible`: the jump replaced
  /// the whole window, so a row forty places down has not been built and
  /// ensureVisible needs a laid-out row to measure. The first pass scrolls to a
  /// proportional estimate, which builds the rows around it; the pass that then
  /// finds the row hands the remaining pixels to ensureVisible, which is exact.
  void _revealRow(int index, {int attempt = 0}) {
    if (!mounted || !_scroll.hasClients) return;
    final rowContext = _flashRowKey.currentContext;
    if (rowContext != null) {
      Scrollable.ensureVisible(
        rowContext,
        alignment: 0,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
      return;
    }
    if (attempt >= 4) return;
    final max = _scroll.position.maxScrollExtent;
    final count = _visibleIndices.length;
    if (max <= 0 || count < 2) return;
    _scroll.jumpTo((max * index / (count - 1)).clamp(0.0, max));
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _revealRow(index, attempt: attempt + 1),
    );
  }

  /// Points the block strip at the block the top row belongs to.
  void _syncActivePage() {
    if (_blocks.length < 2) return;
    final visible = _visibleIndices;
    final position = _topVisiblePosition();
    if (position == null || position < 0 || position >= visible.length) return;
    final block = blockContaining(
      _episodes[visible[position]].episode,
      total: _total,
      size: _size,
      descending: _sort == 'desc',
      firstNumber: _firstNumber,
    );
    final page = block?.page ?? _pageOfWindow;
    if (page != _activePage && mounted) setState(() => _activePage = page);
  }

  /// The window position of the row at the top of the viewport, or null while
  /// the list is not laid out.
  ///
  /// Walks the sliver's live children instead of dividing the scroll offset by
  /// an assumed row height: a row is one or two lines tall depending on the
  /// title its source shipped, and an estimate drifts by whole screens over a
  /// hundred of them — which is exactly the error this replaces.
  int? _topVisiblePosition() {
    final render = _listKey.currentContext?.findRenderObject();
    // No geometry means no layout has reached it yet, and asking such a sliver
    // for its constraints throws.
    if (render is! RenderSliverMultiBoxAdaptor || render.geometry == null) {
      return null;
    }
    final scrolled = render.constraints.scrollOffset;
    RenderBox? child = render.firstChild;
    while (child != null) {
      final data = child.parentData;
      if (data is! SliverMultiBoxAdaptorParentData) return null;
      final start = data.layoutOffset;
      if (start != null && start + child.size.height > scrolled) {
        // Separators share the child index space with rows: child 2n is row n.
        return ((data.index ?? 0) + 1) ~/ 2;
      }
      child = render.childAfter(child);
    }
    return null;
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/main');
    }
  }

  Future<void> _playFrom(int index) async {
    final isHistoryEntry =
        _isHistoryEpisode(index) && _historyItem!.positionMs > 0;

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
    // The engine question belongs before the player exists — see
    // confirmPlayerEngine.
    if (!await confirmPlayerEngine(context) || !mounted) return;
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
        // The player used to be handed this page and nothing else, so every
        // "is there a next episode" question answered against a hundred
        // entries: opening episode 4 of a 1176-episode run meant Next went
        // grey at 100, autoplay stopped, and there was no way forward from
        // inside the player. These four say where the page sits in the run, so
        // it can fetch the next one itself.
        windowStart: _indexOffset,
        totalEpisodes: _total,
        pageSize: _size,
        sort: _sort,
      ),
    );
  }

  /// The download id for [index], whichever kind of source this is.
  String _downloadIdFor(int index) {
    final item = _episodes[index];
    return _isManga
        ? DownloadRequest.mangaChapterId(
            contentUrl: widget.args.contentUrl,
            provider: widget.args.provider,
            chapterRef: item.mediaRef,
          )
        : DownloadRequest.videoId(
            contentUrl: widget.args.contentUrl,
            episodeNumber: item.episode,
          );
  }

  /// Queues one video episode.
  ///
  /// The stream URL does not exist until the provider is asked for it, so this
  /// resolves first — the same call the player makes on open. That is why the
  /// button spins for a moment before the download appears: it is a real
  /// network round trip, not a delay we chose.
  ///
  /// Returns whether anything was queued, so [_downloadSelected] can report a
  /// batch accurately instead of claiming successes it did not have.
  Future<bool> _downloadEpisode(int index, {bool quiet = false}) async {
    final ep = _episodes[index];

    // Whether this episode is already accounted for is asked of the repository
    // at enqueue time, not here: only it can tell a genuinely finished
    // download from a row that says "downloaded" for a file that has gone.
    // Checking first meant a stale row blocked the re-download that would have
    // repaired it.
    final result = await getIt<ResolveMediaUseCase>()(
      ref: ep.mediaRef,
      provider: widget.args.provider,
    );
    if (!mounted) return false;

    if (result is! Success<MediaResolveEntity> || result.value.videoUrl.isEmpty) {
      if (!quiet) _toast('detail.download_resolve_failed'.tr());
      return false;
    }

    final media = result.value;
    // A directive means `videoUrl` is the embed PAGE — the stream only exists
    // after a WebView sniff, which the downloader does not do. Saving it would
    // produce an HTML file under a video's name that fails on first open.
    // Playing the episode once runs the sniff, and the player can then
    // download the resolved stream.
    if (!DownloadChoices.isDownloadableUrl(
      url: media.videoUrl,
      type: media.type,
      hasDirective: media.extractor != null,
    )) {
      if (!quiet) _toast('detail.download_needs_playback'.tr());
      return false;
    }
    final outcome = await _enqueue(
      DownloadRequest.video(
        contentUrl: widget.args.contentUrl,
        provider: widget.args.provider,
        title: widget.args.title,
        sourceUrl: media.videoUrl,
        thumbnailUrl: widget.args.thumbnail,
        headers: media.headers,
        isSerial: true,
        episodeNumber: ep.episode,
        episodeLabel: ep.label,
      ),
    );

    if (outcome != EnqueueOutcome.started && !quiet && mounted) {
      _toast(downloadOutcomeMessage(outcome));
    }
    return outcome == EnqueueOutcome.started;
  }

  void _toggleSelection(int index) {
    setState(() {
      if (!_selected.remove(index)) _selected.add(index);
    });
  }

  void _clearSelection() => setState(_selected.clear);

  /// Selects every episode currently loaded — not every episode that exists.
  ///
  /// The list pages in as you scroll, and a long-running show can have a
  /// thousand entries. "All" meaning "all 1000, including the 950 not fetched
  /// yet" would be a trap, so it means what is on screen.
  void _selectAllLoaded() {
    setState(() {
      if (_selected.length == _episodes.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(List.generate(_episodes.length, (i) => i));
      }
    });
  }

  /// Queues everything selected, in episode order.
  ///
  /// Sequential rather than parallel: each item needs its own resolve call, and
  /// firing thirty at once at a provider is how you get rate-limited into
  /// failing all thirty. The download service has its own queue for the
  /// transfers themselves.
  Future<void> _downloadSelected() async {
    if (_queueing || _selected.isEmpty) return;

    final indices = _selected.toList()..sort();
    if (indices.length >= _batchConfirmThreshold) {
      final ok = await _confirmLargeBatch(indices);
      if (ok != true) return;
    }

    if (!mounted) return;
    setState(() => _queueing = true);
    var queued = 0;
    try {
      for (final index in indices) {
        if (!mounted) break;
        // `indices` is a snapshot; `_episodes` is live. A block chip or a
        // sort tapped mid-queue replaces the window under this loop, and
        // `_episodes[index]` inside _downloadEpisode then throws RangeError.
        // Skipping is right: the row that index pointed at is no longer on
        // screen, so queueing whatever now occupies the slot would download
        // something nobody selected.
        if (index >= _episodes.length) continue;
        final started = _isManga
            ? await _downloadChapterQuietly(index)
            : await _downloadEpisode(index, quiet: true);
        if (started) queued++;
      }
    } finally {
      // Without this, one exception left `_queueing` true for the life of the
      // page: the batch bar span forever and every later tap early-returned
      // at the guard on the first line.
      if (mounted) {
        setState(() {
          _queueing = false;
          _selected.clear();
        });
      }
    }
    if (!mounted) return;
    _toast(queued == 0
        ? 'detail.download_none_queued'.tr()
        : 'detail.download_queued_n'.tr(args: ['$queued']));
  }

  /// Batches past this size ask first. Thirty episodes is several gigabytes and
  /// a long time on mobile data; a mis-tap on "select all" should not spend it.
  static const _batchConfirmThreshold = 10;

  /// The episode numbers a batch covers, lowest to highest.
  ///
  /// The dialog used to show a bare count, and a count is the one thing that
  /// stays right when the selection is wrong — a selection is a set of
  /// positions, and positions change meaning under a sort. Naming the episodes
  /// puts what is about to be downloaded in front of the person confirming it.
  String _selectionRange(List<int> indices) {
    var lo = _episodes[indices.first].episode;
    var hi = lo;
    for (final index in indices) {
      final number = _episodes[index].episode;
      if (number < lo) lo = number;
      if (number > hi) hi = number;
    }
    return lo == hi ? '$lo' : '$lo–$hi';
  }

  Future<bool?> _confirmLargeBatch(List<int> indices) => showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(
            'detail.download_batch_title'.tr(),
            style: TextStyle(color: AppColors.textPrimary, fontSize: 17),
          ),
          content: Text(
            'detail.download_batch_body'.tr(namedArgs: {
              'range': _selectionRange(indices),
              'count': '${indices.length}',
            }),
            style: TextStyle(color: AppColors.textSecondary, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                'general.cancel'.tr(),
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text('detail.download_action'.tr()),
            ),
          ],
        ),
      );

  /// [_downloadChapter] with its own error reporting suppressed, for batches.
  Future<bool> _downloadChapterQuietly(int index) async {
    final before = _downloads.byId(_downloadIdFor(index));
    if (before != null && before.status != DownloadStatus.failed) return false;
    await _downloadChapter(index);
    return _downloads.byId(_downloadIdFor(index)) != null;
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _downloadChapter(int index) async {
    final ch = _episodes[index];

    // Pages are resolved here rather than left to the queue because this is
    // where a failure can be reported: a chapter whose pages cannot be listed
    // is not a download that should sit in the list saying "pending".
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
    await _enqueue(
      DownloadRequest.mangaChapter(
        contentUrl: widget.args.contentUrl,
        provider: widget.args.provider,
        title: widget.args.title,
        thumbnailUrl: widget.args.thumbnail,
        headers: pages.headers,
        pageUrls: pages.pages.map((p) => p.imageUrl).toList(),
        chapterRef: ch.mediaRef,
        chapterIndex: index,
        episodeNumber: ch.episode,
        episodeLabel: ch.label,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    final appBarH = topPad + 56;
    final visible = _visibleIndices;
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    final jumpBlock = _jumpBlock;
    final jumpNumber = _queryNumber;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      // Back during a selection undoes the selection. Without this the Android
      // back gesture threw away forty ticked episodes AND the page they were
      // ticked on, in one stroke, with nothing to undo it.
      child: PopScope(
        canPop: !_selecting,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _clearSelection();
        },
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
                                    // Only once the window has been moved off the
                                    // start of the run: while paging down from
                                    // the top "100 of 1176" is the truth, but
                                    // after a jump it reads as still-loading when
                                    // what it means is "these hundred, up there".
                                    rangeFrom: _indexOffset > 0
                                        ? _episodes.first.episode
                                        : null,
                                    rangeTo: _indexOffset > 0
                                        ? _episodes.last.episode
                                        : null,
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
                        // Jump blocks, then the number filter. Both only appear
                        // once the run is long enough to need them — on a
                        // twelve-episode season they would be chrome over a list
                        // that already fits on two screens.
                        if (_blocks.length > 1)
                          SliverToBoxAdapter(
                            child: _BlockStrip(
                              blocks: _blocks,
                              activePage: _activePage,
                              busy: _jumping,
                              onPick: _jumpToBlock,
                            ),
                          ),
                        if (_episodes.length > 12)
                          SliverToBoxAdapter(
                            child: _EpisodeFilterField(
                              controller: _filter,
                              onChanged: _setQuery,
                            ),
                          ),
                        // The way out of a filter that searched only the loaded
                        // window: the strip above already knows which page holds
                        // the number that was typed.
                        if (jumpBlock != null && jumpNumber != null)
                          SliverToBoxAdapter(
                            child: _JumpToEpisodeRow(
                              number: jumpNumber,
                              block: jumpBlock,
                              busy: _jumping,
                              onTap: () => _jumpToEpisode(jumpNumber, jumpBlock),
                            ),
                          )
                        else if (_query.isNotEmpty && visible.isEmpty)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
                              child: Text(
                                _jumpMiss != null && _jumpMiss == jumpNumber
                                    ? 'episodes.jump_missing'.tr(
                                        namedArgs: {'n': '$_jumpMiss'},
                                      )
                                    : 'episodes.filter_none'.tr(
                                        namedArgs: {'query': _query},
                                      ),
                                style: const TextStyle(
                                  color: AppColors.textHint,
                                  fontSize: 13,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ),
                        SliverList.separated(
                          key: _listKey,
                          itemCount: visible.length,
                          // Indents line up with where the row's label starts:
                          // 16 + 88 thumb + 12, or 16 + 44 number + 12.
                          separatorBuilder: (_, _) => Divider(
                            color: AppColors.divider,
                            height: 1,
                            indent: _showImages ? 116 : 72,
                          ),
                          itemBuilder: (_, position) {
                            final i = visible[position];
                            final isCurrent = _isHistoryEpisode(i);
                            return _EpisodeRow(
                              key: i == _flashIndex ? _flashRowKey : null,
                              episode: _episodes[i],
                              showImage: _showImages,
                              // The headers that unlock the stills are the ones
                              // the player was handed; a referer-locked source
                              // serves nothing without them.
                              headers: widget.args.headers,
                              isManga: _isManga,
                              flash: i == _flashIndex,
                              progress: isCurrent ? _historyItem!.progress : null,
                              // In selection mode a tap picks rather than plays;
                              // opening the player from under a half-made
                              // selection is the classic multi-select mistake.
                              onTap: _selecting
                                  ? () => _toggleSelection(i)
                                  : () => _playFrom(i),
                              onLongPress: () => _toggleSelection(i),
                              selected: _selected.contains(i),
                              selecting: _selecting,
                              onDownload: _isManga
                                  ? () => _downloadChapter(i)
                                  : () => _downloadEpisode(i),
                              downloadId: _downloadIdFor(i),
                              downloads: _downloads,
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
                        // The batch bar covers about 76px of the list while a
                        // selection is on, and it covered the last episodes'
                        // checkboxes: the run you most often want to queue is the
                        // one at the end.
                        SliverToBoxAdapter(
                          child: SizedBox(
                            height: bottomPad + (_selecting ? 100 : 24),
                          ),
                        ),
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
                    selectedCount: _selected.length,
                    allSelected: _selected.length == _episodes.length,
                    onCancelSelection: _clearSelection,
                    onSelectAll: _selectAllLoaded,
                  ),
                ),
              ),
              if (_selecting)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _BatchDownloadBar(
                    count: _selected.length,
                    busy: _queueing,
                    onDownload: _downloadSelected,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BlockStrip extends StatefulWidget {
  const _BlockStrip({
    required this.blocks,
    required this.activePage,
    required this.busy,
    required this.onPick,
  });

  final List<EpisodeBlock> blocks;
  final int activePage;
  final bool busy;
  final ValueChanged<EpisodeBlock> onPick;

  @override
  State<_BlockStrip> createState() => _BlockStripState();
}

class _BlockStripState extends State<_BlockStrip> {
  final ScrollController _strip = ScrollController();

  /// Rides on whichever chip is active, so revealing it is a measurement
  /// rather than a guess.
  final GlobalKey _activeKey = GlobalKey();

  @override
  void didUpdateWidget(covariant _BlockStrip old) {
    super.didUpdateWidget(old);
    // Follow a jump. Landing on block 14 with the strip still showing 1–4
    // leaves no indication of where you are.
    //
    // After the frame, not during it. didUpdateWidget runs BEFORE the subtree
    // rebuilds, so `_activeKey` is still mounted on the chip that was active a
    // moment ago — and `Scrollable.ensureVisible` reads its render object
    // synchronously. Called directly from here it scrolled to where the OLD
    // chip already is, i.e. did nothing, which is the exact failure the
    // measured key replaced an estimate to fix. initState already gets this
    // right a few lines down.
    if (old.activePage != widget.activePage) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealActive());
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealActive());
  }

  void _revealActive() {
    if (!mounted || !_strip.hasClients) return;
    final chip = _activeKey.currentContext;
    // The pills were assumed 108px wide, which is right for "1–100" and out by
    // half a chip for "1001–1100" — on a thousand-episode run the error
    // compounds across a dozen chips and the one you jumped to lands off
    // screen. Measured, it cannot drift.
    if (chip != null) {
      Scrollable.ensureVisible(
        chip,
        alignment: 0.5,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
      return;
    }
    // Not built: the active chip is outside the horizontal cache extent, so
    // hand the strip a rough offset and measure on the next frame.
    //
    // The jump is deferred rather than run here because this method is now
    // reachable from a post-frame callback that a scroll notification
    // scheduled — mutating a scroll position from inside that dispatch
    // re-enters the notification it came from.
    final index = widget.blocks.indexWhere((b) => b.page == widget.activePage);
    if (index < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_strip.hasClients) return;
      _strip.jumpTo(
        (index * 108.0 - 60).clamp(0.0, _strip.position.maxScrollExtent),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final built = _activeKey.currentContext;
        if (built != null) Scrollable.ensureVisible(built, alignment: 0.5);
      });
    });
  }

  @override
  void dispose() {
    _strip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: ListView.separated(
        controller: _strip,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsetsDirectional.only(start: 16, end: 16, bottom: 6),
        itemCount: widget.blocks.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final block = widget.blocks[i];
          final active = block.page == widget.activePage;
          return _BlockChip(
            key: active ? _activeKey : null,
            label: block.label,
            active: active,
            // Everything is disabled during a jump, not just the tapped one:
            // two jumps in flight would race to replace the same list.
            onTap: widget.busy ? null : () => widget.onPick(block),
          );
        },
      ),
    );
  }
}

class _BlockChip extends StatelessWidget {
  const _BlockChip({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      child: Material(
        color: active ? AppColors.primary : Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(11),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: active ? Colors.white : AppColors.textSecondary,
                  fontSize: 13.5,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  // Numerals line up between pills, so the strip does not
                  // shimmer as the digits change width under a scroll.
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Filters the loaded block down to episodes whose number contains the text.
///
/// A number pad rather than a full keyboard, and a substring rather than an
/// exact match: someone reaching for 1043 types "104" and wants to see the
/// neighbourhood, not one row.
class _EpisodeFilterField extends StatelessWidget {
  const _EpisodeFilterField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        // Not a number pad: titles are searchable too, and a keyboard that
        // cannot type "Marineford" makes half the feature unreachable.
        textInputAction: TextInputAction.search,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.05),
          hintText: 'episodes.filter_hint'.tr(),
          hintStyle: const TextStyle(color: AppColors.textHint, fontSize: 13.5),
          prefixIcon: const Icon(
            Icons.search_rounded,
            size: 19,
            color: AppColors.textHint,
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 40),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (_, value, _) => value.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    color: AppColors.textHint,
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                    },
                  ),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 11),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(11),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

/// The offer to load the page that actually holds a typed episode number.
///
/// The filter searches the loaded window, and the loader refuses to page in
/// more while a query is set, so typing 437 on a fresh 1176-episode list ended
/// at "no episode matching 437 in this block" with nothing to do next — while
/// the chip strip directly above it knew the answer. This is that chip, spelled
/// out and put where the answer was expected.
class _JumpToEpisodeRow extends StatelessWidget {
  const _JumpToEpisodeRow({
    required this.number,
    required this.block,
    required this.busy,
    required this.onTap,
  });

  final int number;
  final EpisodeBlock block;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
      child: Material(
        color: AppColors.primary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: busy ? null : onTap,
          focusColor: _kTvRowFocusFill,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                if (busy)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  )
                else
                  Icon(
                    Icons.my_location_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'episodes.jump_to'.tr(namedArgs: {'n': '$number'}),
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'episodes.jump_loads'.tr(
                          namedArgs: {'range': block.label},
                        ),
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
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

class _EpisodesAppBar extends StatelessWidget {
  const _EpisodesAppBar({
    required this.title,
    required this.blurProgress,
    required this.onBack,
    this.selectedCount = 0,
    this.allSelected = false,
    this.onCancelSelection,
    this.onSelectAll,
  });

  final String title;
  final double blurProgress;
  final VoidCallback onBack;

  final int selectedCount;
  final bool allSelected;
  final VoidCallback? onCancelSelection;
  final VoidCallback? onSelectAll;

  bool get _selecting => selectedCount > 0;

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    // Selection is opaque regardless of scroll: a half-transparent bar
    // over the list makes the count hard to read, and the count is the only
    // thing telling the user what is about to be downloaded.
    final progress = _selecting ? 1.0 : blurProgress.clamp(0.0, 1.0);

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
      padding: EdgeInsetsDirectional.fromSTEB(4, topPad + 4, 16, 0),
      child: _selecting ? _selectionRow(context) : _titleRow(context),
    );

    return progress > 0.02
        ? ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18 * progress, sigmaY: 18 * progress),
              child: content,
            ),
          )
        : content;
  }

  Widget _selectionRow(BuildContext context) => Row(
        children: [
          IconButton(
            onPressed: onCancelSelection,
            icon: const Icon(Icons.close_rounded, size: 22, color: Colors.white),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Text(
              'detail.selected_n'.tr(args: ['$selectedCount']),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
            ),
          ),
          TextButton(
            onPressed: onSelectAll,
            child: Text(
              allSelected
                  ? 'detail.select_none'.tr()
                  : 'detail.select_all'.tr(),
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );

  Widget _titleRow(BuildContext context) => Row(
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
      );
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
  const _CountHeader({
    required this.loaded,
    required this.total,
    this.rangeFrom,
    this.rangeTo,
  });
  final int loaded;
  final int total;

  /// The episode numbers the loaded window actually covers, set only once the
  /// window has been moved off the start of the run.
  final int? rangeFrom;
  final int? rangeTo;

  @override
  Widget build(BuildContext context) {
    final from = rangeFrom;
    final to = rangeTo;
    final showOf = total > 0 && total > loaded;
    final label = from != null && to != null
        ? 'episodes.range_of'.tr(namedArgs: {
            'from': '$from',
            'to': '$to',
            'total': '$total',
          })
        : showOf
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
      padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 12, 12),
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

/// The number as the column shows it.
///
/// Zero-padded to two so single digits line up under double ones, and left
/// alone past that — padding "1043" would do nothing except make the string
/// longer.
String _episodeNumberLabel(int number) =>
    number < 100 ? '$number'.padLeft(2, '0') : '$number';

/// Matches a label that says nothing the number column does not.
///
/// Sources routinely name every entry "Episode 12" / "12-qism" / "Серия 12",
/// so the row read "12  Episode 12" — the same fact twice, in a list where
/// vertical space is the scarce thing. Anchored at both ends and required to
/// contain the episode's own number, so "Episode 12: Marineford" keeps its
/// title.
final RegExp _redundantEpisodeLabel = RegExp(
  // Two orders, because languages differ on which comes first:
  //   "Episode 12", "Серия 12", "حلقة 12"   — word then number
  //   "12-qism", "12-bo'lim", "12 серия"     — number then word
  r'^\s*(?:'
  r'(?:episode|episodio|ep|серия|серія|qism|bo[ʻ’\x27]?lim|فصل|حلقة)'
  r'\s*[.:\-]?\s*0*(\d+)'
  r'|'
  r'0*(\d+)\s*[.:\-]?\s*'
  r'(?:episode|episodio|ep|серия|серія|qism|bo[ʻ’\x27]?lim|فصل|حلقة)'
  r')\s*$',
  caseSensitive: false,
);

/// What the title line should say, or an empty string when the number column
/// has already said it.
///
/// Public only so a test can run the real thing. The rule had a test that
/// re-declared the regex and read the two capture groups correctly, while this
/// function read only the first and crashed on every label of the other shape
/// — a test of the rule cannot catch the implementation drifting from it.
String episodeRowTitle(EpisodeEntity episode) {
  final label = episode.label.trim();
  if (label.isEmpty) return '';
  final match = _redundantEpisodeLabel.firstMatch(label);
  if (match == null) return label;
  // The pattern has two alternatives and therefore two groups: the number is
  // in the first when the word comes first ("Episode 12") and in the second
  // when it does not ("12-qism", "1 серия"). Only one of them can be set, so
  // reading group 1 with a `!` threw on every label of the second shape — and
  // it threw during build, which took the whole episode list down rather than
  // one row's title.
  final number = match.group(1) ?? match.group(2);
  if (number != null && int.tryParse(number) == episode.episode) {
    return '';
  }
  return label;
}

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({
    super.key,
    required this.episode,
    required this.showImage,
    required this.onTap,
    required this.headers,
    required this.downloadId,
    required this.downloads,
    this.isManga = false,
    this.onLongPress,
    this.selected = false,
    this.selecting = false,
    this.flash = false,
    this.progress,
    this.onDownload,
  });

  final EpisodeEntity episode;
  final bool showImage;
  final VoidCallback onTap;

  /// Whatever the page was handed for this source, forwarded to the thumbnail.
  final Map<String, String> headers;

  final String downloadId;
  final GetDownloadsUseCase downloads;

  /// A reading source rather than a video one. Decides the trailing icon, which
  /// used to key off "does this row have a download button" — true only for
  /// manga back when only manga could be downloaded, and wrong the moment
  /// episodes became downloadable too.
  final bool isManga;

  final VoidCallback? onLongPress;
  final bool selected;

  /// Whether the list as a whole is in multi-select. The row needs this, not
  /// just [selected]: every row shows a checkbox once selection starts, so the
  /// user can see what is tappable.
  final bool selecting;

  /// Briefly tinted because a jump just put the reader on this row. A hundred
  /// rows all look alike, and "you are here" has to be visible for a moment or
  /// the jump lands nowhere in particular.
  final bool flash;

  final double? progress;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) {
    final hasSub = episode.hasSub == true;
    final hasDub = episode.hasDub == true;
    final label = episodeRowTitle(episode);

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      focusColor: _kTvRowFocusFill,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        color: selected
            ? AppColors.primary.withValues(alpha: 0.10)
            : flash
                ? AppColors.primary.withValues(alpha: 0.18)
                : Colors.transparent,
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
                  _EpisodeThumb(
                    image: episode.image,
                    episode: episode.episode,
                    headers: headers,
                  ),
                  const SizedBox(width: 12),
                ] else
                  // A minimum, not a fixed width, and a size that steps down
                  // past three digits.
                  //
                  // A hard 44pt box at 22pt w900 fits three characters. On the
                  // shows this screen exists for — a thousand-episode run — the
                  // fourth digit ran straight into the title beside it.
                  // Tabular figures so the column of numbers stays a column
                  // rather than jittering with the glyph widths.
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 44),
                    child: Text(
                      _episodeNumberLabel(episode.episode),
                      maxLines: 1,
                      style: TextStyle(
                        color: progress != null ? AppColors.primary : AppColors.textHint,
                        fontSize: episode.episode >= 1000 ? 16 : 22,
                        fontWeight: FontWeight.w900,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                if (!showImage) const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Absent, not empty, when the label said nothing the
                      // number column has not: an empty Text still claims a
                      // line box, so the row would keep the height of a title
                      // it is not showing.
                      if (label.isNotEmpty)
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
                        if (label.isNotEmpty) const SizedBox(height: 2),
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
                if (selecting) ...[
                  // What is already on disk is exactly the information needed
                  // to choose, and selection used to hide it behind the
                  // checkbox — so a batch happily re-queued ten episodes the
                  // reader already had.
                  _DownloadedTick(id: downloadId, downloads: downloads),
                  Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                    size: 24,
                    color: selected ? AppColors.primary : AppColors.textHint,
                  ),
                ] else ...[
                  if (onDownload != null) ...[
                    _DownloadControl(
                      id: downloadId,
                      downloads: downloads,
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
                      isManga
                          ? Icons.menu_book_outlined
                          : Icons.play_arrow_rounded,
                      color: progress != null
                          ? AppColors.primary
                          : AppColors.textPrimary,
                      size: 18,
                    ),
                  ),
                ],
              ],
            ),
            if (progress != null)
              Padding(
                padding: EdgeInsetsDirectional.only(
                  start: showImage ? 0 : 56,
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

/// The bottom action bar shown while episodes are selected.
///
/// Bottom rather than in the app bar: on a tall phone the primary action of a
/// selection is the one thing that must stay under the thumb, and the app bar
/// is already carrying the count and "select all".
class _BatchDownloadBar extends StatelessWidget {
  const _BatchDownloadBar({
    required this.count,
    required this.busy,
    required this.onDownload,
  });

  final int count;
  final bool busy;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPad + 12),
      decoration: BoxDecoration(
        color: AppColors.navBackground,
        border: Border(
          top: BorderSide(color: AppColors.divider, width: 0.5),
        ),
      ),
      child: SizedBox(
        height: 46,
        width: double.infinity,
        child: FilledButton.icon(
          // Disabled while queueing so a second tap cannot double-queue a set
          // that is halfway through resolving.
          onPressed: busy ? null : onDownload,
          icon: busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.download_rounded, size: 19),
          label: Text(
            busy
                ? 'detail.download_queueing'.tr()
                : 'detail.download_n'.tr(args: ['$count']),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

/// The download affordance for one row, and the only thing on the page that
/// watches the download service.
///
/// The page State used to hold that listener and answer it with a bare
/// `setState` on itself. [GetDownloadsUseCase.revision] ticks twice a second while
/// anything is downloading, so twice a second the ENTIRE row subtree rebuilt —
/// thumbnail, title, meta line, progress ring, focus decoration — for every row
/// on screen, whether or not anything about it had changed. On a TV box that is
/// the frame budget spent on rows that did not move.
///
/// Listening here narrows the rebuild to this widget. What it does NOT remove
/// is the per-row `downloads.byId(id)` — that is still a box read, a
/// `jsonDecode` and a `DownloadItem.fromJson` per row per tick, because every
/// row mounts one of these. Making that cheaper means the service handing out
/// a decoded snapshot rather than re-parsing per caller, which is a change to
/// the download layer, not to this widget.
class _DownloadControl extends StatelessWidget {
  const _DownloadControl({
    required this.id,
    required this.downloads,
    required this.onDownload,
  });

  final String id;
  final GetDownloadsUseCase downloads;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: downloads.revision,
        builder: (context, _, _) => _control(downloads.byId(id)),
      );

  /// A fixed 48dp slot whatever the state. The states swap under a scrolling
  /// list, and a control that changes width takes the play button next to it
  /// along for the ride.
  Widget _slot(Widget child) =>
      SizedBox(width: 48, height: 48, child: Center(child: child));

  Widget _control(DownloadItem? download) {
    final status = download?.status;

    if (status == DownloadStatus.downloading ||
        status == DownloadStatus.pending) {
      return Semantics(
        label: 'detail.download_in_progress'.tr(),
        child: _slot(
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              value: status == DownloadStatus.downloading
                  ? download?.progress
                  : null,
              strokeWidth: 2,
              color: AppColors.primary,
            ),
          ),
        ),
      );
    }

    if (status == DownloadStatus.completed) {
      return Semantics(
        label: 'downloads.downloaded'.tr(),
        child: _slot(
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.download_done_rounded,
              color: AppColors.success,
              size: 18,
            ),
          ),
        ),
      );
    }

    final failed = status == DownloadStatus.failed;
    final button = Container(
      width: 40,
      height: 40,
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
    final label =
        failed ? 'general.retry'.tr() : 'detail.download_action'.tr();

    // Android TV: the episode row itself is an InkWell (focusable for free),
    // but this download control sat on a bare GestureDetector, so a remote
    // could play an episode and never download one.
    if (isTvPlatform) {
      return Semantics(
        button: true,
        label: label,
        child: TvFocusable(
          onPressed: onDownload,
          borderRadius: 20,
          child: _slot(button),
        ),
      );
    }

    // Off TV it was a bare 34px GestureDetector: under the 48dp minimum, eight
    // pixels from the play button, with no ripple to say it had been hit and
    // nothing for a screen reader to announce. A mis-tap here starts a download
    // instead of playback, or the other way round.
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: SizedBox(
          width: 48,
          height: 48,
          child: InkResponse(
            onTap: onDownload,
            radius: 24,
            child: Center(child: button),
          ),
        ),
      ),
    );
  }
}

/// "Already on disk", shown beside the checkbox during selection.
class _DownloadedTick extends StatelessWidget {
  const _DownloadedTick({required this.id, required this.downloads});

  final String id;
  final GetDownloadsUseCase downloads;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: downloads.revision,
        builder: (context, _, _) {
          if (downloads.byId(id)?.status != DownloadStatus.completed) {
            return const SizedBox.shrink();
          }
          return Semantics(
            label: 'downloads.downloaded'.tr(),
            child: const Padding(
              padding: EdgeInsetsDirectional.only(end: 10),
              child: Icon(
                Icons.download_done_rounded,
                color: AppColors.success,
                size: 18,
              ),
            ),
          );
        },
      );
}

class _EpisodeThumb extends StatelessWidget {
  const _EpisodeThumb({
    required this.image,
    required this.episode,
    required this.headers,
  });
  final String? image;
  final int episode;
  final Map<String, String> headers;

  /// The slot these are drawn into, and what they are decoded at.
  static const double _width = 88;
  static const double _height = 50;

  @override
  Widget build(BuildContext context) {
    final url = image;
    // Decoded at the size it is drawn at. A 1280×720 still in an 88px slot
    // holds two hundred times the pixels it can show, and a long list holds
    // dozens of them at once.
    final decodeWidth = (_width * MediaQuery.devicePixelRatioOf(context))
        .round();

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: _width,
        height: _height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // CachedNetworkImage, not Image.network — the rest of the app made
            // this move already. Image.network caches in memory only, so
            // scrolling back up a season re-downloaded every still; it was
            // never given the source's headers, so referer-locked hosts
            // answered with nothing and the list drew a screen of grey film
            // strips; and its loadingBuilder swapped the fallback in on every
            // chunk, so each thumbnail flickered where it should have faded.
            if (url != null && url.isNotEmpty)
              CachedNetworkImage(
                imageUrl: url,
                httpHeaders: headers.isEmpty ? null : headers,
                fit: BoxFit.cover,
                memCacheWidth: decodeWidth > 0 ? decodeWidth : null,
                fadeInDuration: const Duration(milliseconds: 240),
                placeholder: (_, _) => const _ThumbFallback(),
                errorWidget: (_, _, _) => const _ThumbFallback(),
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
