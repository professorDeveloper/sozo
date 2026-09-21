import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/network/http_headers.dart';
import 'package:soplay/core/system/desktop_window.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/system/system_controls.dart';
import 'package:soplay/features/anilist/data/anilist_tracker.dart';
import 'package:soplay/features/detail/domain/playback/wakelock_holds.dart';
import 'package:soplay/features/detail/domain/usecases/get_pages_usecase.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/detail/domain/entities/episode_entity.dart';
import 'package:soplay/features/download/domain/entities/download_request.dart';
import 'package:soplay/features/download/domain/entities/download_status.dart';
import 'package:soplay/features/download/presentation/download_messages.dart';
import 'package:soplay/features/download/domain/usecases/enqueue_download_usecase.dart';
import 'package:soplay/features/download/domain/usecases/get_downloads_usecase.dart';
import 'package:soplay/features/history/data/history_service.dart';
import 'package:soplay/features/history/domain/entities/history_item.dart';
import 'package:soplay/features/manga/presentation/widgets/novel_text.dart';
import 'package:soplay/features/manga/domain/entities/manga_page_entity.dart';
import 'package:soplay/features/manga/domain/entities/reader_args.dart';
import 'package:soplay/features/manga/domain/reading/chapter_groups.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:soplay/features/manga/data/chapter_read_store.dart';
import 'package:soplay/features/manga/data/page_tiles.dart';
import 'package:soplay/features/manga/presentation/widgets/tiled_zoom.dart';
import 'package:soplay/features/manga/domain/reading/chapter_progress.dart';
import 'package:soplay/core/theme/app_colors.dart';

class ReaderPage extends StatefulWidget {
  final ReaderArgs args;
  const ReaderPage({super.key, required this.args});

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  /// The manga screens used to carry their own private blue. There is one
  /// accent in the app now, and the user chooses it.
  static Color get _accent => AppColors.primary;

  final _hive = getIt<HiveService>();
  final _downloads = getIt<GetDownloadsUseCase>();
  final _enqueue = getIt<EnqueueDownloadUseCase>();

  late int _chapterIndex;
  List<MangaPageEntity> _pages = const [];

  /// A novel chapter's prose, when the source returned text instead of images.
  /// See MangaPagesEntity.html — the two are different shapes, not two ways of
  /// saying the same thing.
  String? _html;
  Map<String, String> _headers = const {};
  bool _loading = true;
  bool _localChapter = false;
  String? _error;

  late String _mode;

  /// Whether the reader pairs pages in landscape. See [_spread].
  late bool _spreadPref;

  /// The spread reader counts slots where the single-page one counts pages.
  PageController _spreadController = PageController(keepPage: false);
  bool _spreadLayout = false;
  late bool _rtl;
  late String _bgPref;
  double _brightness = 0.5;

  // Prose typography. Only a novel chapter uses these; a comic ignores them.
  late double _novelSize;
  late double _novelLeading;
  late String _novelFamily;
  late bool _novelJustify;

  Color get _backgroundColor => switch (_bgPref) {
    'white' => const Color(0xFFFAFAFA),
    'gray' => const Color(0xFF2A2A2A),
    _ => const Color(0xFF0A0A0A),
  };

  final ValueNotifier<int> _page = ValueNotifier<int>(0);
  final ValueNotifier<int?> _dragging = ValueNotifier<int?>(null);
  bool _showOverlay = true;

  PageController? _pageController;
  final ItemScrollController _itemScrollController = ItemScrollController();

  /// The prose reader's own controller. The indexed one above belongs to the
  /// comic readers, where a chapter is a list of pages; a novel is one
  /// continuous body with no index to scroll to.
  final ScrollController _novelScrollController = ScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  int _initialIndex = 0;
  Timer? _saveDebounce;

  /// Which chapters of this sitting have been read far enough to report, and
  /// which have already been reported. Per reader session, like the player's
  /// WatchProgress: leaving and coming back starts a fresh ledger, and the
  /// tracker's own refusal to move progress backwards catches the repeat.
  final ChapterProgress _progress = ChapterProgress();
  final ChapterReadStore _readStore = ChapterReadStore();

  /// The furthest page of this chapter that has been on screen, as a
  /// high-water mark.
  ///
  /// Only the continuous reader moves this. Its notion of the current page is
  /// whatever straddles the top of the viewport, which goes backwards as
  /// freely as it goes forwards and, for the last page of a chapter, may never
  /// be true at all: a final page shorter than the viewport sits under the top
  /// of the screen with the end-of-chapter footer below it, so the chapter
  /// ends with some middle page at the top. A mark that only ever rises is the
  /// only thing here that can answer "was this chapter read".
  ///
  /// Reset to the start page by [_resetPageControllers], because it describes
  /// one chapter and not the sitting.
  int _furthestSeenPage = 0;

  /// Bumped by every [_loadChapter]. A chapter answer that arrives after the
  /// reader has already moved on — two quick taps on "next", a pick from the
  /// chapter sheet while the previous chapter is still loading — is dropped
  /// instead of painting the wrong chapter under the new chapter's title.
  int _loadToken = 0;

  /// How far through a novel chapter the reader is, in thousandths.
  ///
  /// Prose has no page index, so the history row carries this where a comic
  /// carries its page: position out of a duration of 1000. It is what brings a
  /// reader back to the middle of a long chapter instead of its first line.
  final ValueNotifier<int> _novelProgress = ValueNotifier<int>(0);
  int get _novelPermille => _novelProgress.value;
  set _novelPermille(int value) => _novelProgress.value = value;

  int get _currentPage => _page.value;
  int get _pageCount => _pages.length;

  /// Typed, because the args are: this was `List<dynamic>`, which meant every
  /// read off a chapter in this file went unchecked.
  List<EpisodeEntity> get _chapters => widget.args.chapters;

  @override
  void initState() {
    super.initState();
    _chapterIndex = widget.args.initialChapterIndex.clamp(
      0,
      widget.args.chapters.length - 1,
    );
    _mode = _hive.getReaderMode(widget.args.contentUrl);
    _spreadPref = _hive.readerSpread;
    _rtl = _hive.getReaderRtl(widget.args.contentUrl);
    _bgPref = _hive.getReaderBackground();
    _novelSize = _hive.getNovelFontSize();
    _novelLeading = _hive.getNovelLineHeight();
    _novelFamily = _hive.getNovelFontFamily();
    _novelJustify = _hive.getNovelJustify();
    _itemPositionsListener.itemPositions.addListener(_onItemPositions);
    _novelScrollController.addListener(_onNovelScroll);
    if (!isDesktopPlatform) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    _setWakelock(true);
    SystemControls.getBrightness().then((v) {
      if (mounted) setState(() => _brightness = v);
    });
    _loadChapter(
      _chapterIndex,
      startPage: widget.args.resumePage ?? _savedPosition(_chapterIndex),
    );
  }

  int _savedPosition(int index) {
    final chapter = widget.args.chapters[index];
    final history = getIt<HistoryService>().get(
      widget.args.contentUrl,
      episodeIndex: index,
      episodeNumber: chapter.episode,
    );
    return history?.provider == widget.args.provider ? history!.positionMs : 0;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncSpreadLayout();
  }

  int _slotForPage(int page) => page == 0 ? 0 : (page + 1) ~/ 2;
  int _pageForSlot(int slot) => slot == 0 ? 0 : slot * 2 - 1;

  // Recreate only the controller whose layout is becoming visible. PageStorage
  // can otherwise bring back an old offset after rotating or toggling spreads.
  void _syncSpreadLayout() {
    final spread = _spread;
    if (spread == _spreadLayout) return;
    _spreadLayout = spread;
    if (spread) {
      _spreadController.dispose();
      _spreadController = PageController(
        initialPage: _slotForPage(_currentPage),
      );
    } else {
      _pageController?.dispose();
      _pageController = PageController(
        keepPage: false,
        initialPage: _currentPage,
      );
    }
  }

  void _resetPageControllers(int page) {
    _pageController?.dispose();
    _pageController = PageController(keepPage: false, initialPage: page);
    _spreadController.dispose();
    _spreadController = PageController(
      keepPage: false,
      initialPage: _slotForPage(page),
    );
    _page.value = page;
    _furthestSeenPage = page;
    _initialIndex = page;
  }

  @override
  void dispose() {
    _spreadController.dispose();
    _novelScrollController.removeListener(_onNovelScroll);
    _saveProgress();
    _novelScrollController.dispose();
    _saveDebounce?.cancel();
    _itemPositionsListener.itemPositions.removeListener(_onItemPositions);
    _pageController?.dispose();
    _page.dispose();
    _novelProgress.dispose();
    _dragging.dispose();
    _setWakelock(false);
    SystemControls.resetBrightness();
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  void _setWakelock(bool on) {
    // A hold, not a switch: a download running under the reader keeps its own.
    if (on) {
      WakelockHolds.acquire(this);
    } else {
      WakelockHolds.release(this);
    }
  }

  Future<void> _loadChapter(int index, {int startPage = 0}) async {
    if (index < 0 || index >= _chapters.length) return;
    _saveDebounce?.cancel();
    _saveProgress();
    final token = ++_loadToken;
    setState(() {
      _chapterIndex = index;
      _loading = true;
      _error = null;
      _localChapter = false;
      _pages = const [];
      _html = null;
    });
    _page.value = 0;
    _furthestSeenPage = 0;
    final ch = widget.args.chapters[index];
    final ref = ch.mediaRef;

    final localId = DownloadRequest.mangaChapterId(
      contentUrl: widget.args.contentUrl,
      provider: widget.args.provider,
      chapterRef: ref,
    );
    // Prose first: a novel chapter is one document beside its pictures, and
    // asking for pages would find those pictures and render them as a comic.
    final localHtml = await _downloads.localChapterHtml(localId);
    if (!mounted || token != _loadToken) return;
    if (localHtml != null && localHtml.trim().isNotEmpty) {
      _novelPermille = startPage.clamp(0, 1000);
      setState(() {
        _localChapter = true;
        _html = localHtml;
        _pages = const [];
        _headers = const {};
        _loading = false;
      });
      _restoreNovelPosition(_novelPermille);
      _scheduleSave();
      return;
    }

    final local = await _downloads.localMangaPages(localId);
    if (!mounted || token != _loadToken) return;
    if (local.isNotEmpty) {
      final start = startPage.clamp(0, local.length - 1);
      _resetPageControllers(start);
      setState(() {
        _localChapter = true;
        _pages = local;
        _headers = const {};
        _loading = false;
      });
      _scheduleSave();
      return;
    }
    _localChapter = false;

    final result = await getIt<GetPagesUseCase>()(
      ref: ref,
      provider: widget.args.provider,
    );
    if (!mounted || token != _loadToken) return;
    switch (result) {
      case Success(:final value):
        final start = value.pages.isEmpty
            ? 0
            : startPage.clamp(0, value.pages.length - 1);
        _resetPageControllers(start);
        final isText = value.isText;
        _novelPermille = isText ? startPage.clamp(0, 1000) : 0;
        setState(() {
          _pages = value.pages;
          _html = isText ? value.html : null;
          _headers = value.headers;
          _loading = false;
        });
        if (isText) _restoreNovelPosition(_novelPermille);
        _scheduleSave();
      case Failure(:final error):
        setState(() {
          _error = error.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
    }
  }

  void _onItemPositions() {
    if (_mode != 'vertical' || _pageCount == 0) return;
    _markSeenPages(_itemPositionsListener.itemPositions.value);
    final positions = _itemPositionsListener.itemPositions.value.where(
      (p) => p.index < _pageCount && p.itemTrailingEdge > 0,
    );
    if (positions.isEmpty) return;
    final straddling = positions.where((p) => p.itemLeadingEdge <= 0);
    final page =
        (straddling.isNotEmpty
                ? straddling.reduce(
                    (a, b) => a.itemLeadingEdge >= b.itemLeadingEdge ? a : b,
                  )
                : positions.reduce(
                    (a, b) => a.itemLeadingEdge <= b.itemLeadingEdge ? a : b,
                  ))
            .index;
    if (page != _page.value) {
      _page.value = page;
      _scheduleSave();
    }
  }

  /// Raises [_furthestSeenPage] to the furthest page [positions] shows the
  /// bottom of, and schedules a save when it moves.
  ///
  /// The bottom edge rather than any part of the page, because in a continuous
  /// reader the top of a page arrives long before the page is read: a flick
  /// that brings the last page's first centimetre into view would otherwise
  /// finish the chapter. A page whose trailing edge has been inside the
  /// viewport is a page that has been scrolled through.
  ///
  /// A page only partly on screen is reported too, with whichever edge is off
  /// the screen outside 0..1 — the last page arriving with its top showing
  /// and its bottom below the fold reports a trailing edge past 1 — so the
  /// edge has to be tested against both ends of the viewport and not merely
  /// for being a position at all.
  ///
  /// Zero-height items do not count. An image the reader has not measured yet
  /// lays out flat, so a chapter that has just opened is briefly the pages it
  /// has not measured stacked on one line under the ones it has, every one of
  /// their bottom edges on screen at the same height. Counting that frame
  /// would report every chapter the moment it was opened, which is the one
  /// thing this rule exists to prevent.
  ///
  /// A chapter short enough to fit on the screen is therefore read as soon as
  /// it is open, which matches the one-page comic in [ChapterProgress]: there
  /// is no scrolling left to do and no more of it to see.
  ///
  /// Saves on its own rather than leaving that to the page-changed path,
  /// because the two do not move together: scrolling the end of a tall last
  /// page into view advances this while the page at the top of the viewport
  /// stays exactly where it was.
  void _markSeenPages(Iterable<ItemPosition> positions) {
    var furthest = _furthestSeenPage;
    for (final position in positions) {
      if (position.index >= _pageCount) continue;
      final bottom = position.itemTrailingEdge;
      if (bottom <= 0 || bottom > 1 || bottom <= position.itemLeadingEdge) {
        continue;
      }
      if (position.index > furthest) furthest = position.index;
    }
    if (furthest == _furthestSeenPage) return;
    _furthestSeenPage = furthest;
    _scheduleSave();
  }

  void _jumpVerticalTo(int page) {
    if (!_itemScrollController.isAttached || _pageCount == 0) return;
    _itemScrollController.jumpTo(index: page.clamp(0, _pageCount - 1));
  }

  /// Scrolls a freshly loaded novel chapter to where the reader left it.
  ///
  /// After the first frame, because the prose has no extent to scroll through
  /// until it has been laid out — and always, even to the top, because the
  /// scroll view can otherwise come back holding the previous chapter's offset.
  void _restoreNovelPosition(int permille) {
    final token = _loadToken;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          token != _loadToken ||
          !_novelScrollController.hasClients) {
        return;
      }
      final max = _novelScrollController.position.maxScrollExtent;
      _novelScrollController.jumpTo(max * permille / 1000);
    });
  }

  void _onNovelScroll() {
    if (_html == null || !_novelScrollController.hasClients) return;
    final max = _novelScrollController.position.maxScrollExtent;
    if (max <= 0) return;
    final permille = (_novelScrollController.offset / max * 1000).round().clamp(
      0,
      1000,
    );
    // Every scrolled pixel would otherwise restart the save timer; a change
    // of half a percent is the smallest one worth recording.
    if ((permille - _novelPermille).abs() < 5 && permille != 1000) return;
    _novelPermille = permille;
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 800), _saveProgress);
  }

  void _saveProgress() {
    // A novel chapter has no pages but is very much being read; returning on
    // an empty page list is what used to leave novels out of history entirely.
    final isNovel = _html != null;
    if (!isNovel && _pageCount == 0) return;
    final ch = widget.args.chapters[_chapterIndex];
    getIt<HistoryService>().save(
      HistoryItem(
        contentUrl: widget.args.contentUrl,
        provider: widget.args.provider,
        title: widget.args.title,
        thumbnail: widget.args.thumbnail,
        isSerial: true,
        episodeIndex: _chapterIndex,
        episodeNumber: ch.episode,
        episodeLabel: ch.label,
        positionMs: isNovel ? _novelPermille : _currentPage,
        durationMs: isNovel ? 1000 : (_pageCount > 1 ? _pageCount - 1 : 0),
        watchedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    // On the same tick as the history write, because the two answer questions
    // about the same moment: this is where the reader's position is known to
    // have changed, and every path that moves it already comes through here.
    _maybeReportChapter();
  }

  /// The furthest page of this chapter that has been on screen.
  ///
  /// Each reader needs a different answer, and none of them is the current
  /// page on its own:
  ///
  /// - The double-page reader reports the FIRST page of the pair, so the
  ///   second half of the last slot is just as read and a chapter whose last
  ///   slot holds two would otherwise never reach its last page at all.
  /// - The continuous reader's current page is whatever straddles the top of
  ///   the viewport, which is never the last page of a long chapter; it keeps
  ///   [_furthestSeenPage] instead. That mark starts at the current page and
  ///   only rises, so the max of the two is right whether or not the listener
  ///   has fired yet.
  /// - The page-at-a-time reader turns one page at a time and the current page
  ///   is already the furthest.
  ///
  /// Reads [_spreadLayout] rather than [_spread] because this is reachable
  /// from dispose, where there is no MediaQuery left to ask.
  int get _furthestVisiblePage {
    if (_pages.isEmpty) return _currentPage;
    if (_spreadLayout) {
      final slots = _spreadSlots;
      final slot = _slotForPage(_currentPage);
      return slot < slots.length ? slots[slot].last : _currentPage;
    }
    return _furthestSeenPage > _currentPage ? _furthestSeenPage : _currentPage;
  }

  /// Tells AniList this chapter has been read, once it has been.
  ///
  /// The reader's half of the player's `_maybeReportTrackers`, and deliberately
  /// the same design: a threshold rather than the first page, one report per
  /// chapter however many times that threshold is crossed, nothing awaited on
  /// a path the reader is on, and no error surfaced. A tracker being down, a
  /// token having expired or there being no network at all must cost the
  /// reader nothing — they are reading, not syncing.
  ///
  /// AniList only. MyAnimeList's client here speaks anime endpoints and anime
  /// ids exclusively, so a manga's `idMal` sent through it would write chapters
  /// onto an unrelated anime; see MalTracker's own note. That is also why the
  /// detail page keeps MAL off manga titles.
  ///
  /// Incognito covers the trackers for the reason it covers history: pushing
  /// the chapter to somebody's public list while hiding it locally would put
  /// the record in the one place the reader cannot quietly clear.
  ///
  /// The ledger is marked before the write is sent, not after it succeeds, so
  /// a write that fails — offline, expired token, tracker down — is not tried
  /// again for the rest of the sitting. That is the player's rule too, and for
  /// its reason: one chapter is one event. Once the threshold is crossed it
  /// stays crossed, so without the ledger every later save on this chapter —
  /// every scroll, every page turn, the write on the way out — would send the
  /// chapter again, and somebody reading back and forth over the end would aim
  /// a burst of them at a tracker that is already not answering. None of it is
  /// ever shown to them. The chapter is picked up again on the next sitting,
  /// where the ledger starts empty.
  void _maybeReportChapter() {
    if (_hive.isIncognito) return;
    if (widget.args.contentUrl.trim().isEmpty) return;

    final read = _html != null
        ? ChapterProgress.isProseRead(_novelPermille)
        : ChapterProgress.isComicRead(
            furthestPage: _furthestVisiblePage,
            pageCount: _pageCount,
          );
    if (!read) return;

    // The reader's own record first, and unconditionally.
    //
    // It is deliberately NOT behind the tracker gate below. Whether a chapter
    // has been read is a fact about this device and this list; whether anybody
    // was told about it is a different question with its own preconditions —
    // an account, a connection, a title the tracker recognises — and tying the
    // two together meant the list could only show progress to somebody signed
    // in to AniList.
    //
    // Nor behind the once-per-session ledger: that exists to stop a tracker
    // hearing twice, and [ChapterReadStore.mark] is idempotent, so re-reading
    // a finished chapter writes nothing and costs nothing.
    unawaited(
      _readStore.mark(widget.args.provider, widget.args.contentUrl, [
        widget.args.chapters[_chapterIndex].episode,
      ]),
    );

    // Asked before the ledger is marked: a chapter finished while no tracker
    // is connected must still be reportable if one is connected later in the
    // same sitting.
    final anilist = getIt<AnilistTracker>();
    if (!anilist.isConnected) return;

    final number = _progress.chapterToReport(
      widget.args.chapters[_chapterIndex].episode,
    );
    if (number == null) return;

    unawaited(
      anilist
          .reportChapter(
            provider: widget.args.provider,
            contentUrl: widget.args.contentUrl,
            title: widget.args.title,
            chapterNumber: number,
          )
          .catchError((Object _) => null),
    );
  }

  void _toggleOverlay() => setState(() => _showOverlay = !_showOverlay);

  void _seekNovel(int permille) {
    if (!_novelScrollController.hasClients) return;
    final position = _novelScrollController.position;
    _novelScrollController.jumpTo(
      position.maxScrollExtent * permille.clamp(0, 1000) / 1000,
    );
  }

  void _scrollNovel(int direction) {
    if (!_novelScrollController.hasClients) return;
    final position = _novelScrollController.position;
    _novelScrollController.animateTo(
      (position.pixels + direction * position.viewportDimension * 0.85).clamp(
        0.0,
        position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _goToPage(int page) {
    if (_html != null) {
      _seekNovel(page);
      return;
    }
    // Home/End can arrive before a chapter has loaded.
    if (_pageCount == 0) return;
    final clamped = page.clamp(0, _pageCount - 1);
    if (_spread) {
      final slot = _slotForPage(clamped);
      if (!_spreadController.hasClients) return;
      _spreadController.animateToPage(
        slot,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
      _page.value = _pageForSlot(slot);
    } else if (_mode == 'horizontal') {
      if (_pageController?.hasClients != true) return;
      _pageController!.animateToPage(
        clamped,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    } else {
      _jumpVerticalTo(clamped);
    }
    if (!_spread) _page.value = clamped;
    _scheduleSave();
  }

  void _goNextPage() {
    if (_loading) return;
    if (_html != null) {
      _scrollNovel(1);
      return;
    }
    if (_spread) {
      final slot = _slotForPage(_currentPage) + 1;
      slot < _spreadSlots.length
          ? _goToPage(_pageForSlot(slot))
          : _nextChapter();
      return;
    }
    _currentPage < _pageCount - 1
        ? _goToPage(_currentPage + 1)
        : _nextChapter();
  }

  void _goPrevPage() {
    if (_loading) return;
    if (_html != null) {
      _scrollNovel(-1);
      return;
    }
    if (_spread) {
      final slot = _slotForPage(_currentPage) - 1;
      slot >= 0 ? _goToPage(_pageForSlot(slot)) : _prevChapter();
      return;
    }
    _currentPage > 0 ? _goToPage(_currentPage - 1) : _prevChapter();
  }

  void _nextChapter() {
    if (_chapterIndex < _chapters.length - 1) {
      _loadChapter(_chapterIndex + 1);
    } else {
      _snack('manga.last_chapter'.tr());
    }
  }

  void _prevChapter() {
    if (_chapterIndex > 0) {
      _loadChapter(_chapterIndex - 1);
    } else {
      _snack('manga.first_chapter'.tr());
    }
  }

  void _setMode(String mode) {
    if (mode == _mode) return;
    final page = _currentPage;
    _hive.saveReaderMode(widget.args.contentUrl, mode);
    if (mode == 'horizontal') {
      _pageController?.dispose();
      _pageController = PageController(keepPage: false, initialPage: page);
    } else {
      _initialIndex = page;
    }
    setState(() {
      _mode = mode;
      _syncSpreadLayout();
    });
  }

  void _toggleRtl() {
    final next = !_rtl;
    _hive.saveReaderRtl(widget.args.contentUrl, next);
    setState(() => _rtl = next);
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 1)),
    );
  }

  void _handleTapZone(TapUpDetails d) {
    if (_html != null || _mode == 'vertical') {
      _toggleOverlay();
      return;
    }
    final w = MediaQuery.sizeOf(context).width;
    final x = d.localPosition.dx;
    if (x < w * 0.3) {
      _rtl ? _goNextPage() : _goPrevPage();
    } else if (x > w * 0.7) {
      _rtl ? _goPrevPage() : _goNextPage();
    } else {
      _toggleOverlay();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scaffold = Scaffold(
      backgroundColor: _backgroundColor,
      body: Stack(
        children: [
          Positioned.fill(child: _content()),
          if (isDesktopPlatform &&
              _showOverlay &&
              !_loading &&
              _error == null) ...[
            _pageArrow(left: true),
            _pageArrow(left: false),
          ],
          if (_showOverlay) _topBar(),
          if (isDesktopPlatform && !_showOverlay) _persistentClose(),
          if (_showOverlay && !_loading && _error == null) _bottomBar(),
        ],
      ),
    );
    if (!isDesktopPlatform) return scaffold;
    return Focus(autofocus: true, onKeyEvent: _onKey, child: scaffold);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final k = event.logicalKey;
    if (k == LogicalKeyboardKey.escape) {
      if (context.canPop()) context.pop();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight ||
        k == LogicalKeyboardKey.arrowDown ||
        k == LogicalKeyboardKey.pageDown ||
        k == LogicalKeyboardKey.space) {
      _goNextPage();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowLeft ||
        k == LogicalKeyboardKey.arrowUp ||
        k == LogicalKeyboardKey.pageUp) {
      _goPrevPage();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.home) {
      _goToPage(0);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.end) {
      _goToPage(_html != null ? 1000 : _pageCount - 1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _pageArrow({required bool left}) {
    return Align(
      alignment: left
          ? AlignmentDirectional.centerStart
          : AlignmentDirectional.centerEnd,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Material(
          color: Colors.black.withValues(alpha: 0.35),
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: IconButton(
            icon: Icon(
              left ? Icons.chevron_left : Icons.chevron_right,
              color: Colors.white,
            ),
            onPressed: left ? _goPrevPage : _goNextPage,
          ),
        ),
      ),
    );
  }

  Widget _persistentClose() {
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 4,
      left: 4,
      child: Material(
        color: Colors.black.withValues(alpha: 0.35),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: IconButton(
          tooltip: 'general.close'.tr(),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.pop(),
        ),
      ),
    );
  }

  Widget _content() {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: _accent, strokeWidth: 2),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.broken_image_outlined,
                color: Colors.white38,
                size: 44,
              ),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _accent),
                onPressed: () =>
                    _loadChapter(_chapterIndex, startPage: _currentPage),
                child: Text('general.retry'.tr()),
              ),
            ],
          ),
        ),
      );
    }
    // Prose, not pages. Checked before the empty branch because a novel
    // legitimately has zero pages, and that used to be reported as "no pages
    // found" — which is what made every novel source in the app look broken.
    if (_html != null) return _novelReader(_html!);

    if (_pages.isEmpty) {
      return Center(
        child: Text(
          'manga.no_pages'.tr(),
          style: const TextStyle(color: Colors.white54),
        ),
      );
    }
    return _mode == 'horizontal' ? _horizontalReader() : _verticalReader();
  }

  /// A chapter of prose.
  ///
  /// Always vertical: paging a novel by screenful is a choice comic readers
  /// have because a page is a fixed unit, and prose has no such unit — a page
  /// boundary would land mid-sentence and move every time the font size did.
  ///
  /// The reader's own background and text settings apply, so a novel and a
  /// comic read as the same app rather than as one screen borrowing whatever
  /// styling its source shipped.
  Widget _novelReader(String html) {
    final onWhite = _bgPref == 'white';
    return GestureDetector(
      onTapUp: _handleTapZone,
      child: SingleChildScrollView(
        controller: _novelScrollController,
        // Comfortable measure on a phone and not edge-to-edge: text running
        // into the bezel is the single most common thing that makes a reader
        // tiring.
        padding: EdgeInsets.fromLTRB(
          20,
          MediaQuery.paddingOf(context).top + 64,
          20,
          MediaQuery.paddingOf(context).bottom + 96,
        ),
        child: NovelText(
          html: html,
          color: onWhite ? const Color(0xFF16181C) : Colors.white,
          fontSize: _novelSize,
          lineHeight: _novelLeading,
          fontFamily: _novelFamily.isEmpty ? null : _novelFamily,
          justify: _novelJustify,
          // Paragraphs need air in proportion to their leading, or a generous
          // line height closes the gap between them and the page reads as one
          // block.
          paragraphSpacing: _novelSize * _novelLeading * 0.85,
        ),
      ),
    );
  }

  Widget _verticalReader() {
    return GestureDetector(
      onTapUp: _handleTapZone,
      child: ScrollablePositionedList.builder(
        key: ValueKey('v_$_chapterIndex'),
        itemScrollController: _itemScrollController,
        itemPositionsListener: _itemPositionsListener,
        initialScrollIndex: _initialIndex.clamp(0, _pageCount),
        minCacheExtent: 2000,
        itemCount: _pages.length + 1,
        itemBuilder: (context, i) {
          if (i == _pages.length) return _chapterFooter();
          return _PageImage(
            key: ValueKey('v_${_chapterIndex}_$i'),
            page: _pages[i],
            headers: _headers,
            zoomable: false,
          );
        },
      ),
    );
  }

  /// Whether two pages are shown side by side.
  ///
  /// Only in landscape, and that is not a setting: a spread on a portrait phone
  /// is two pages at half width each, which is smaller than one page and
  /// harder to read. Offering it there would be offering a worse picture.
  bool get _spread =>
      _spreadPref &&
      _mode == 'horizontal' &&
      MediaQuery.orientationOf(context) == Orientation.landscape;

  /// The pages in each slot of the spread reader.
  ///
  /// The first page is alone. A comic's first page is its cover, and pairing it
  /// with page two puts every subsequent spread one page out of step with how
  /// the book was drawn — which is the whole reason to show two at a time.
  List<List<int>> get _spreadSlots {
    final slots = <List<int>>[];
    if (_pages.isEmpty) return slots;
    slots.add([0]);
    for (var i = 1; i < _pages.length; i += 2) {
      slots.add([i, if (i + 1 < _pages.length) i + 1]);
    }
    return slots;
  }

  Widget _horizontalReader() {
    if (_spread) return _spreadReader();
    return Stack(
      children: [
        PageView.builder(
          key: ValueKey('horizontal_$_chapterIndex'),
          controller: _pageController,
          reverse: _rtl,
          itemCount: _pages.length,
          onPageChanged: (i) {
            _page.value = i;
            _scheduleSave();
          },
          itemBuilder: (context, i) => Center(
            child: _PageImage(
              key: ValueKey('h_${_chapterIndex}_$i'),
              page: _pages[i],
              headers: _headers,
              zoomable: true,
            ),
          ),
        ),
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapUp: _handleTapZone,
          ),
        ),
      ],
    );
  }

  /// Two pages at once, the way the book was drawn.
  ///
  /// A double-page spread is a single illustration in a lot of comics, and
  /// reading it one half at a time loses the picture. This is what every
  /// dedicated reader does in landscape and what the app was missing.
  Widget _spreadReader() {
    final slots = _spreadSlots;
    return Stack(
      children: [
        PageView.builder(
          key: ValueKey('spread_$_chapterIndex'),
          // Its own controller: the page-per-screen one counts pages and this
          // counts slots, so sharing it would put the reader at slot 40 of 20.
          controller: _spreadController,
          reverse: _rtl,
          itemCount: slots.length,
          onPageChanged: (slot) {
            // Reported as the first page of the slot, so progress, resume and
            // the page counter all stay in pages — the unit everything else in
            // this class already speaks.
            _page.value = slots[slot].first;
            _scheduleSave();
          },
          itemBuilder: (context, slot) {
            final indices = _rtl ? slots[slot].reversed.toList() : slots[slot];
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final i in indices)
                  Flexible(
                    child: _PageImage(
                      key: ValueKey('s_${_chapterIndex}_$i'),
                      page: _pages[i],
                      headers: _headers,
                      // Not zoomable in a spread: a pinch would zoom one half
                      // out from under the other.
                      zoomable: false,
                    ),
                  ),
              ],
            );
          },
        ),
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapUp: _handleTapZone,
          ),
        ),
      ],
    );
  }

  Widget _chapterFooter() {
    final hasNext = _chapterIndex < _chapters.length - 1;
    final nextLabel = hasNext
        ? widget.args.chapters[_chapterIndex + 1].label
        : null;
    final onWhite = _bgPref == 'white';
    final muted = onWhite ? Colors.black54 : Colors.white54;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 48, 20, 60),
      child: Column(
        children: [
          Icon(
            hasNext ? Icons.check_circle_outline : Icons.done_all_rounded,
            color: onWhite ? Colors.black26 : Colors.white30,
            size: 34,
          ),
          const SizedBox(height: 12),
          Text(
            hasNext ? 'manga.chapter_ended'.tr() : 'manga.last_chapter'.tr(),
            style: TextStyle(color: muted, fontSize: 13),
          ),
          if (hasNext) ...[
            const SizedBox(height: 20),
            Material(
              color: _accent,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _nextChapter,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 230),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'manga.next_chapter'.tr().toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6,
                              ),
                            ),
                            if (nextLabel != null && nextLabel.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  nextLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _topBar() {
    final ch = widget.args.chapters[_chapterIndex];
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.paddingOf(context).top + 4,
          bottom: 8,
          left: 4,
          right: 8,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black.withValues(alpha: 0.85), Colors.transparent],
          ),
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => context.pop(),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.args.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    ch.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            _downloadButton(ch),
            // Only when there is somewhere to go. A provider with no web page
            // for this chapter gets no button rather than a button that
            // apologises.
            if (_chapterOnSite case final uri?)
              IconButton(
                tooltip: 'manga.open_on_site'.tr(),
                icon: const Icon(
                  Icons.open_in_new_rounded,
                  color: Colors.white,
                ),
                onPressed: () => _openOnSite(uri),
              ),
            IconButton(
              tooltip: 'manga.chapters'.tr(),
              icon: const Icon(Icons.format_list_bulleted, color: Colors.white),
              onPressed: _openChapterList,
            ),
            IconButton(
              tooltip: 'general.settings'.tr(),
              icon: const Icon(Icons.tune, color: Colors.white),
              onPressed: _openSettingsSheet,
            ),
            if (isDesktopPlatform)
              ValueListenableBuilder<bool>(
                valueListenable: DesktopWindow.immersive,
                builder: (_, imm, _) => imm
                    ? const Padding(
                        padding: EdgeInsetsDirectional.only(start: 4),
                        child: WindowButtons(),
                      )
                    : const SizedBox.shrink(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _downloadButton(EpisodeEntity ch) {
    if (_html != null) {
      return Tooltip(
        message: 'manga.novel_download_unavailable'.tr(),
        child: const IconButton(
          icon: Icon(Icons.download_outlined, color: Colors.white38),
          onPressed: null,
        ),
      );
    }
    final id = DownloadRequest.mangaChapterId(
      contentUrl: widget.args.contentUrl,
      provider: widget.args.provider,
      chapterRef: ch.mediaRef,
    );
    return ValueListenableBuilder<int>(
      valueListenable: _downloads.revision,
      builder: (context, _, _) {
        final item = _downloads.byId(id);
        final status = item?.status;
        if (status == DownloadStatus.downloading) {
          return SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  value: item?.progress,
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            ),
          );
        }
        final done = _localChapter || status == DownloadStatus.completed;
        return IconButton(
          icon: Icon(
            done ? Icons.download_done_rounded : Icons.download_outlined,
            color: Colors.white,
          ),
          onPressed: done ? null : _downloadCurrentChapter,
        );
      },
    );
  }

  Future<void> _downloadCurrentChapter() async {
    if (_pages.isEmpty) return;
    final ch = widget.args.chapters[_chapterIndex];
    // The pages are already resolved on screen, so they travel with the
    // request rather than being fetched again — a chapter's page urls are
    // short-lived, and re-resolving one that is open is a round trip for an
    // answer we are looking at.
    final outcome = await _enqueue(
      DownloadRequest.mangaChapter(
        contentUrl: widget.args.contentUrl,
        provider: widget.args.provider,
        title: widget.args.title,
        thumbnailUrl: widget.args.thumbnail,
        headers: _headers,
        pageUrls: _pages.map((p) => p.imageUrl).toList(),
        imageHeaders: [
          for (final page in _pages)
            {
              ...page.headers,
              if (page.cookie?.isNotEmpty == true) 'Cookie': page.cookie!,
            },
        ],
        chapterRef: ch.mediaRef,
        chapterIndex: _chapterIndex,
        episodeNumber: ch.episode,
        episodeLabel: ch.label,
      ),
    );
    if (!mounted) return;
    _snack(downloadOutcomeMessage(outcome));
  }

  /// The chapter list, with a spine and a way to search it.
  ///
  /// It was six hundred identical rows and a scrollbar. Reaching chapter 300
  /// meant dragging until the numbers looked right, and there was nothing to
  /// type into — which for the one list in this app that routinely runs to
  /// four figures is the wrong shape entirely.
  ///
  /// Two things. Headings, from the source's own labels where they carry a
  /// volume and from chapter-number ranges where they do not — see
  /// [groupChapters], which never renumbers anything, because the index is the
  /// identity the rest of the reader is keyed on. And a filter, which is how
  /// somebody who knows the number gets there in one move.
  void _openChapterList() {
    showAdaptiveModal<void>(
      context: context,
      backgroundColor: const Color(0xFF161616),
      isScrollControlled: true,
      showDragHandle: !isDesktopPlatform,
      builder: (_) => _ChapterListSheet(
        chapters: _chapters,
        current: _chapterIndex,
        accent: _accent,
        onPick: (i) {
          Navigator.of(context).pop();
          if (i != _chapterIndex) _loadChapter(i);
        },
      ),
    );
  }

  /// This chapter's page on the source's own website, or null when there is
  /// none to open.
  ///
  /// The chapter's own url first, the title's second. A Mihon or Aniyomi
  /// extension stores both as paths relative to its `baseUrl`, so the hosts
  /// resolve them there and send an absolute one up; a backend provider has an
  /// absolute `contentUrl` and no per-chapter page, which is why the fallback
  /// exists rather than the action disappearing for every provider that is not
  /// an extension.
  Uri? get _chapterOnSite {
    for (final candidate in [
      widget.args.chapters[_chapterIndex].webUrl,
      widget.args.contentUrl,
    ]) {
      final text = candidate?.trim() ?? '';
      if (text.isEmpty) continue;
      final uri = Uri.tryParse(text);
      if (uri == null) continue;
      if (uri.scheme != 'http' && uri.scheme != 'https') continue;
      if (uri.host.isEmpty) continue;
      return uri;
    }
    return null;
  }

  Future<void> _openOnSite(Uri uri) async {
    // Out of the app on purpose: the point is to see the chapter the way the
    // source publishes it — its own images, its own comments, its own report
    // button — which an in-app webview would only half do.
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('errors.no_browser'.tr())));
    }
  }

  void _openSettingsSheet() {
    showAdaptiveModal<void>(
      context: context,
      backgroundColor: const Color(0xFF161616),
      showDragHandle: true,
      builder: (_) => StatefulBuilder(
        builder: (context, setSheet) => SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_html == null) ...[
                  Text(
                    'manga.reading_mode'.tr(),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  _segmented(
                    options: {
                      'vertical': 'manga.mode_continuous'.tr(),
                      'horizontal': 'manga.mode_paged'.tr(),
                    },
                    value: _mode,
                    onChanged: (v) {
                      _setMode(v);
                      setSheet(() {});
                    },
                  ),
                  if (_mode == 'horizontal') ...[
                    const SizedBox(height: 18),
                    Text(
                      'manga.direction'.tr(),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _segmented(
                      options: {
                        'ltr': 'manga.dir_ltr'.tr(),
                        'rtl': 'manga.dir_rtl'.tr(),
                      },
                      value: _rtl ? 'rtl' : 'ltr',
                      onChanged: (v) {
                        final wantRtl = v == 'rtl';
                        if (wantRtl != _rtl) _toggleRtl();
                        setSheet(() {});
                      },
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'manga.spread'.tr(),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Said plainly rather than discovered: the switch does nothing
                    // in portrait, and a control that appears to do nothing is one
                    // people conclude is broken.
                    Text(
                      'manga.spread_desc'.tr(),
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _segmented(
                      options: {
                        'off': 'general.off'.tr(),
                        'on': 'general.on'.tr(),
                      },
                      value: _spreadPref ? 'on' : 'off',
                      onChanged: (v) {
                        final want = v == 'on';
                        if (want == _spreadPref) return;
                        setState(() {
                          _spreadPref = want;
                          _syncSpreadLayout();
                        });
                        _hive.setReaderSpread(want);
                        setSheet(() {});
                      },
                    ),
                  ],
                ],
                if (_html != null) ...[
                  const SizedBox(height: 18),
                  Text(
                    'manga.text_size'.tr(),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  _novelSlider(
                    value: _novelSize,
                    min: 13,
                    max: 26,
                    divisions: 13,
                    label: _novelSize.round().toString(),
                    onChanged: (v) {
                      setSheet(() {});
                      setState(() => _novelSize = v);
                      _hive.saveNovelFontSize(v);
                    },
                  ),
                  Text(
                    'manga.line_height'.tr(),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  _novelSlider(
                    value: _novelLeading,
                    min: 1.2,
                    max: 2.2,
                    divisions: 10,
                    label: _novelLeading.toStringAsFixed(2),
                    onChanged: (v) {
                      setSheet(() {});
                      setState(() => _novelLeading = v);
                      _hive.saveNovelLineHeight(v);
                    },
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'manga.typeface'.tr(),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  _segmented(
                    options: {
                      '': 'manga.typeface_default'.tr(),
                      'serif': 'manga.typeface_serif'.tr(),
                      'monospace': 'manga.typeface_mono'.tr(),
                    },
                    value: _novelFamily,
                    onChanged: (v) {
                      _hive.saveNovelFontFamily(v);
                      setState(() => _novelFamily = v);
                      setSheet(() {});
                    },
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'manga.alignment'.tr(),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  _segmented(
                    options: {
                      'left': 'manga.align_left'.tr(),
                      'justify': 'manga.align_justify'.tr(),
                    },
                    value: _novelJustify ? 'justify' : 'left',
                    onChanged: (v) {
                      final want = v == 'justify';
                      _hive.saveNovelJustify(want);
                      setState(() => _novelJustify = want);
                      setSheet(() {});
                    },
                  ),
                ],
                const SizedBox(height: 18),
                Text(
                  'manga.background'.tr(),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 8),
                _segmented(
                  options: {
                    'black': 'manga.bg_black'.tr(),
                    'gray': 'manga.bg_gray'.tr(),
                    'white': 'manga.bg_white'.tr(),
                  },
                  value: _bgPref,
                  onChanged: (v) {
                    _hive.saveReaderBackground(v);
                    setState(() => _bgPref = v);
                    setSheet(() {});
                  },
                ),
                if (!isDesktopPlatform) ...[
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      const Icon(
                        Icons.brightness_6_outlined,
                        color: Colors.white54,
                        size: 18,
                      ),
                      Expanded(
                        child: Slider(
                          activeColor: _accent,
                          inactiveColor: Colors.white24,
                          min: 0.05,
                          max: 1.0,
                          value: _brightness.clamp(0.05, 1.0),
                          onChanged: (v) {
                            setSheet(() => _brightness = v);
                            setState(() => _brightness = v);
                            SystemControls.setBrightness(v);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// A labelled slider for the prose settings, sized to sit in the sheet.
  Widget _novelSlider({
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String label,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        Expanded(
          child: Slider(
            activeColor: _accent,
            inactiveColor: Colors.white24,
            min: min,
            max: max,
            divisions: divisions,
            value: value.clamp(min, max),
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            label,
            textAlign: TextAlign.end,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _segmented({
    required Map<String, String> options,
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: options.entries.map((e) {
          final selected = e.key == value;
          return Expanded(
            child: HoverTap(
              onTap: () => onChanged(e.key),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: selected ? _accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(
                  e.value,
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.white60,
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _bottomBar() {
    final hasPrevChapter = _chapterIndex > 0;
    final hasNextChapter = _chapterIndex < _chapters.length - 1;
    final isNovel = _html != null;
    final maxPage = isNovel
        ? 1000.0
        : (_pageCount - 1).clamp(0, 9999).toDouble();
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.paddingOf(context).bottom + 8,
          top: 10,
          left: 8,
          right: 8,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black.withValues(alpha: 0.85), Colors.transparent],
          ),
        ),
        child: Row(
          children: [
            IconButton(
              icon: Icon(
                Icons.skip_previous_rounded,
                color: hasPrevChapter ? Colors.white : Colors.white24,
              ),
              onPressed: hasPrevChapter ? _prevChapter : null,
            ),
            Expanded(
              child: ValueListenableBuilder<int?>(
                valueListenable: _dragging,
                builder: (context, drag, _) => ValueListenableBuilder<int>(
                  valueListenable: isNovel ? _novelProgress : _page,
                  builder: (context, page, _) {
                    final display = (drag ?? page).clamp(0, maxPage.toInt());
                    return Row(
                      children: [
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 2.5,
                              activeTrackColor: _accent,
                              inactiveTrackColor: Colors.white24,
                              thumbColor: _accent,
                              overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 14,
                              ),
                            ),
                            child: Slider(
                              min: 0,
                              max: maxPage,
                              value: display.toDouble(),
                              onChanged: isNovel || _pageCount > 1
                                  ? (v) => _dragging.value = v.round()
                                  : null,
                              onChangeEnd: (v) {
                                final target = v.round();
                                _dragging.value = null;
                                _goToPage(target);
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isNovel
                              ? '${(display / 10).round()}%'
                              : '${display + 1}/$_pageCount',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            IconButton(
              icon: Icon(
                Icons.skip_next_rounded,
                color: hasNextChapter ? Colors.white : Colors.white24,
              ),
              onPressed: hasNextChapter ? _nextChapter : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _PageImage extends StatefulWidget {
  const _PageImage({
    super.key,
    required this.page,
    required this.headers,
    required this.zoomable,
  });

  final MangaPageEntity page;
  final Map<String, String> headers;
  final bool zoomable;

  @override
  State<_PageImage> createState() => _PageImageState();
}

class _PageImageState extends State<_PageImage> {
  /// The manga screens used to carry their own private blue. There is one
  /// accent in the app now, and the user chooses it.
  static Color get _accent => AppColors.primary;
  int _retry = 0;

  /// The file this page was drawn from, once there is one.
  ///
  /// A downloaded page is already a path. A network page becomes one as soon as
  /// it has been fetched, because [CachedNetworkImage] writes it to disk on the
  /// way in — so the sharp zoom below works for both without downloading
  /// anything twice. Null until then, which is the same thing as "not zoomable
  /// yet".
  String? _sourcePath;

  @override
  void initState() {
    super.initState();
    _resolveSource();
  }

  @override
  void didUpdateWidget(_PageImage old) {
    super.didUpdateWidget(old);
    if (old.page.imageUrl != widget.page.imageUrl) {
      _sourcePath = null;
      _resolveSource();
    }
  }

  Future<void> _resolveSource() async {
    if (!widget.zoomable || !PageTiles.isSupported) return;
    final url = widget.page.imageUrl;
    if (!url.startsWith('http')) {
      if (mounted) setState(() => _sourcePath = url);
      return;
    }
    try {
      final file = await DefaultCacheManager().getFileFromCache(
        widget.page.cacheKey ?? url,
      );
      if (!mounted || file == null) return;
      setState(() => _sourcePath = file.file.path);
    } catch (_) {
      // No cached file yet. The page still draws; it just zooms the way it
      // always did until the next build finds one.
    }
  }

  /// Chapter headers plus this page's host-scoped cookies, if it has any.
  Map<String, String> get _imageHeaders {
    final cookie = widget.page.cookie;
    return mergeHttpHeaders([
      widget.headers,
      widget.page.headers,
      if (cookie != null && cookie.isNotEmpty) {'Cookie': cookie},
    ]);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // Decode to the page's actual column width; two-page spreads should not
      // allocate two full-screen decoded images.
      final width = constraints.maxWidth.isFinite
          ? constraints.maxWidth
          : MediaQuery.sizeOf(context).width;
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final cacheW = (width * dpr).round();

      final url = widget.page.imageUrl;
      final isLocal = !url.startsWith('http');

      final Widget img = isLocal
          ? Image.file(
              File(url),
              key: ValueKey('$url#$_retry'),
              fit: BoxFit.fitWidth,
              width: width,
              cacheWidth: cacheW,
              errorBuilder: (_, _, _) => _errorTile(width),
            )
          : CachedNetworkImage(
              key: ValueKey('$url#$_retry'),
              imageUrl: url,
              cacheKey: widget.page.cacheKey,
              // The page's own cookies win over anything in the chapter headers:
              // they are scoped to this image's host, which the shared headers
              // are not. Without them a Cloudflare-gated source serves the page
              // list fine and then 403s every image.
              httpHeaders: _imageHeaders,
              fit: BoxFit.fitWidth,
              width: width,
              memCacheWidth: cacheW,
              fadeInDuration: const Duration(milliseconds: 120),
              placeholder: (_, _) => Container(
                width: width,
                height: width * 1.4,
                color: Colors.white.withValues(alpha: 0.02),
                child: Center(
                  child: CircularProgressIndicator(
                    color: _accent,
                    strokeWidth: 1.8,
                  ),
                ),
              ),
              errorWidget: (_, _, _) => _errorTile(width),
            );

      if (!widget.zoomable) return img;
      // Zoomed, the image above is a bitmap decoded at column width being
      // magnified — which is exactly when a dense page or small lettering turns
      // to mush. [TiledZoom] re-reads the part that is on screen from the file
      // at the size it is being shown at, and falls back to precisely this
      // InteractiveViewer wherever it cannot.
      return TiledZoom(
        sourcePath: _sourcePath,
        maxScale: 4,
        child: SizedBox(width: width, child: img),
      );
    },
  );

  Widget _errorTile(double width) => HoverTap(
    onTap: () async {
      await CachedNetworkImage.evictFromCache(
        widget.page.imageUrl,
        cacheKey: widget.page.cacheKey,
      );
      if (mounted) setState(() => _retry++);
    },
    child: Container(
      width: width,
      height: 220,
      color: Colors.white.withValues(alpha: 0.03),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.refresh_rounded, color: Colors.white38, size: 30),
          const SizedBox(height: 8),
          Text(
            'manga.tap_to_reload'.tr(),
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    ),
  );
}

/// The chapter list: headings, a filter, and the current chapter in view.
///
/// Stateful because of the filter. A sheet that rebuilds the whole reader on
/// every keystroke would be the wrong thing twice over — the reader is holding
/// decoded pages.
class _ChapterListSheet extends StatefulWidget {
  const _ChapterListSheet({
    required this.chapters,
    required this.current,
    required this.accent,
    required this.onPick,
  });

  final List<EpisodeEntity> chapters;
  final int current;
  final Color accent;
  final ValueChanged<int> onPick;

  @override
  State<_ChapterListSheet> createState() => _ChapterListSheetState();
}

class _ChapterListSheetState extends State<_ChapterListSheet> {
  final TextEditingController _filter = TextEditingController();
  String _query = '';

  /// Past this many, reading the list is slower than typing at it.
  static const int _filterThreshold = 25;

  bool get _hasFilter => widget.chapters.length >= _filterThreshold;

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  /// The rows to draw: a heading, then its chapters, then the next heading.
  ///
  /// Flattened here rather than nested, so the whole thing stays one lazy
  /// list — a thousand chapters in a Column of Columns is a thousand rows laid
  /// out before the sheet can open.
  List<Object> get _rows {
    final q = _query.trim().toLowerCase();
    final rows = <Object>[];
    for (final group in groupChapters(widget.chapters)) {
      final hits = [
        for (final i in group.indices)
          if (q.isEmpty || widget.chapters[i].label.toLowerCase().contains(q))
            i,
      ];
      if (hits.isEmpty) continue;
      // A heading over a filtered list still says where the hits came from,
      // which is most of what somebody scanning for "12" wants to know.
      if (group.label.isNotEmpty || group.volume != null) rows.add(group);
      rows.addAll(hits);
    }
    return rows;
  }

  Widget _heading(ChapterGroup group) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
    child: Text(
      group.volume != null
          ? 'manga.volume_n'.tr(args: ['${group.volume}'])
          : (group.label.isEmpty ? 'manga.other_chapters'.tr() : group.label),
      style: const TextStyle(
        color: Colors.white38,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.9,
      ),
    ),
  );

  Widget _tile(int i) {
    final ch = widget.chapters[i];
    final selected = i == widget.current;
    return ListTile(
      dense: true,
      selected: selected,
      selectedTileColor: widget.accent.withValues(alpha: 0.12),
      leading: Icon(
        selected ? Icons.play_arrow_rounded : Icons.menu_book_outlined,
        color: selected ? widget.accent : Colors.white38,
        size: 20,
      ),
      title: Text(
        ch.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: selected ? widget.accent : Colors.white,
          fontSize: 13.5,
        ),
      ),
      onTap: () => widget.onPick(i),
    );
  }

  Widget _list(ScrollController? controller) {
    final rows = _rows;
    if (rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'manga.no_chapter_match'.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white38, fontSize: 13),
          ),
        ),
      );
    }
    return ListView.builder(
      controller: controller,
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final row = rows[i];
        return row is ChapterGroup ? _heading(row) : _tile(row as int);
      },
    );
  }

  Widget _field() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    child: TextField(
      controller: _filter,
      onChanged: (v) => setState(() => _query = v),
      style: const TextStyle(color: Colors.white, fontSize: 13.5),
      decoration: InputDecoration(
        isDense: true,
        hintText: 'manga.find_chapter'.tr(),
        prefixIcon: const Icon(Icons.search_rounded, size: 18),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                tooltip: 'general.clear'.tr(),
                icon: const Icon(Icons.close_rounded, size: 16),
                onPressed: () {
                  _filter.clear();
                  setState(() => _query = '');
                },
              ),
      ),
    ),
  );

  Widget _title() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Text(
      'manga.chapters'.tr(),
      style: const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (isDesktopPlatform) {
      return SizedBox(
        width: 360,
        height: 480,
        child: Column(
          children: [
            _title(),
            if (_hasFilter) _field(),
            Expanded(child: _list(null)),
          ],
        ),
      );
    }
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      builder: (context, scroll) => Column(
        children: [
          _title(),
          if (_hasFilter) _field(),
          Expanded(child: _list(scroll)),
        ],
      ),
    );
  }
}
