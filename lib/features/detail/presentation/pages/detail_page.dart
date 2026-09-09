import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/tv/tv.dart';
import 'package:soplay/features/banners/domain/entities/banner_item.dart';
import 'package:soplay/features/banners/presentation/widgets/banners_carousel.dart';
import 'package:soplay/features/cloudflare/cloudflare_solver.dart';
import 'package:soplay/features/detail/domain/download_choices.dart';
import 'package:soplay/features/detail/domain/usecases/resolve_media_usecase.dart';
import 'package:soplay/features/detail/domain/entities/detail_args.dart';
import 'package:soplay/features/detail/domain/entities/detail_entity.dart';
import 'package:soplay/core/extensions/provider_media_kind.dart';
import 'package:soplay/features/detail/domain/entities/episodes_args.dart';
import 'package:soplay/features/detail/domain/entities/playback_entity.dart';
import 'package:soplay/features/detail/domain/entities/player_args.dart';
import 'package:soplay/features/detail/presentation/blocs/detail_bloc/detail_bloc.dart';
import 'package:soplay/features/detail/presentation/blocs/episodes_bloc/episodes_bloc.dart';
import 'package:soplay/features/detail/presentation/blocs/favorite_bloc/favorite_bloc.dart';
import 'package:soplay/features/detail/presentation/blocs/favorite_bloc/favorite_event.dart';
import 'package:soplay/features/detail/presentation/blocs/favorite_bloc/favorite_state.dart';
import 'package:soplay/features/history/data/history_service.dart';
import 'package:soplay/features/tracker/data/follow_service.dart';
import 'package:soplay/features/tracker/domain/entities/followed_title.dart';
import 'package:soplay/features/my_list/data/datasources/my_list_local_data_source.dart';
import 'package:soplay/features/my_list/data/private_list_service.dart';
import 'package:soplay/features/my_list/domain/entities/favorite_entity.dart';
import 'package:soplay/features/private_list/presentation/private_unlock.dart';
import 'package:share_plus/share_plus.dart';
import 'package:soplay/features/detail/presentation/widgets/player_engine_sheet.dart';
import 'package:soplay/features/detail/presentation/widgets/detail_relations_tab.dart';
import 'package:soplay/features/detail/presentation/widgets/alternate_source_sheet.dart';
import 'package:soplay/features/detail/presentation/widgets/detail_cast_tab.dart';
import 'package:soplay/features/detail/presentation/widgets/detail_comments_tab.dart';
import 'package:soplay/features/detail/presentation/widgets/detail_hero.dart';
import 'package:soplay/features/detail/presentation/widgets/detail_info.dart';
import 'package:soplay/features/detail/presentation/widgets/detail_more_menu.dart';
import 'package:soplay/features/detail/presentation/widgets/detail_related.dart';
import 'package:soplay/features/detail/presentation/widgets/detail_screenshots.dart';
import 'package:soplay/features/detail/presentation/widgets/detail_skeleton.dart';
import 'package:soplay/features/detail/presentation/widgets/detail_circle_button.dart';
import 'package:soplay/features/detail/presentation/widgets/detail_preview_skeleton.dart';
import 'package:soplay/core/widgets/app_tab_bar.dart';
import 'package:soplay/core/widgets/poster_hero.dart';
import 'package:soplay/features/home/domain/entities/movie.dart';
import 'package:soplay/features/detail/domain/entities/media_resolve_entity.dart';
import 'package:soplay/features/download/domain/entities/download_request.dart';
import 'package:soplay/features/download/domain/usecases/enqueue_download_usecase.dart';
import 'package:soplay/features/download/presentation/download_messages.dart';
import 'package:showcaseview/showcaseview.dart';

class DetailPage extends StatelessWidget {
  const DetailPage({super.key, required this.args});
  final DetailArgs args;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) =>
              getIt<DetailBloc>()
                ..add(DetailLoad(args.contentUrl, provider: args.provider)),
        ),
        BlocProvider(create: (_) => getIt<EpisodesBloc>()),
        BlocProvider(create: (_) => getIt<FavoriteBloc>()),
      ],
      child: _DetailScaffold(
        contentUrl: args.contentUrl,
        provider: args.provider,
        autoPlay: args.autoPlay,
        resumeEpisodeIndex: args.resumeEpisodeIndex,
        preview: args.preview,
        heroTag: args.heroTag,
      ),
    );
  }
}

class _DetailScaffold extends StatelessWidget {
  const _DetailScaffold({
    required this.contentUrl,
    this.provider,
    this.autoPlay = false,
    this.resumeEpisodeIndex,
    this.preview,
    this.heroTag,
  });
  final String contentUrl;
  final String? provider;
  final bool autoPlay;
  final int? resumeEpisodeIndex;

  /// What the caller already knew about this title — poster, name, year.
  /// Enough to draw the top of the page before the request lands.
  final MovieEntity? preview;
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    // Read once into a local so it promotes: `preview` is a public field, and
    // Dart only promotes private ones.
    final preview = this.preview;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: BlocListener<DetailBloc, DetailState>(
          listenWhen: (prev, curr) {
            if (curr is! DetailLoaded) return false;
            if (prev is! DetailLoaded) return true;
            return prev.detail.contentUrl != curr.detail.contentUrl ||
                prev.detail.isFavorited != curr.detail.isFavorited;
          },
          listener: (context, state) {
            if (state is DetailLoaded) {
              context.read<FavoriteBloc>().add(
                FavoriteLoad(
                  contentUrl: state.detail.contentUrl,
                  provider: state.detail.provider,
                  isFavorited: state.detail.isFavorited,
                ),
              );
            }
          },
          child: BlocBuilder<DetailBloc, DetailState>(
            builder: (context, state) {
              return switch (state) {
                // A shimmer here threw away what the caller already handed
                // us. The poster, the title and the year came in with the tap
                // and are correct; only the description, cast and episodes are
                // genuinely unknown. Showing grey boxes over all of it also
                // gave the Hero nothing to land on, so the poster flew out of
                // the grid and vanished into a placeholder.
                DetailInitial() || DetailLoading() => Stack(
                  children: [
                    if (preview != null)
                      DetailPreviewSkeleton(
                        preview: preview,
                        heroTag: heroTag,
                      )
                    else
                      const DetailSkeleton(),
                    _BackOnlyBar(onBack: () => _goBack(context)),
                  ],
                ),
                // Built on DetailLoaded alone.
                //
                // There used to be a second skeleton here, held until
                // FavoriteBloc left FavoriteInitial — but FavoriteLoad is only
                // dispatched from the listener above, as an async event, so
                // there was ALWAYS at least one shimmer frame after the real
                // detail was already in memory. The poster finished its flight
                // into a header that then blinked back to grey.
                //
                // Nothing downstream needed the wait: the top bar has its own
                // BlocBuilder<FavoriteBloc> and already branches on
                // showListAction. It also removes a latent lock-up — a silent
                // DetailLoaded refresh that skips DetailLoading would strand
                // the page on the skeleton for good.
                DetailLoaded(:final detail) =>
                  Builder(
                    builder: (context) {
                      return _DetailView(
                        detail: detail,
                        provider: provider,
                        autoPlay: autoPlay,
                        resumeEpisodeIndex: resumeEpisodeIndex,
                        heroTag: heroTag,
                      );
                    },
                  ),
                DetailError(:final message) => _ErrorView(
                  message: message,
                  onRetry: () => context.read<DetailBloc>().add(
                    DetailLoad(contentUrl, provider: provider),
                  ),
                  onSolveCloudflare: isCloudflareError(message)
                      ? () async {
                          final bloc = context.read<DetailBloc>();
                          final prov =
                              provider ??
                              getIt<HiveService>().getCurrentProvider();
                          final ok = await requestCloudflareSolve(
                            context,
                            prov,
                          );
                          if (ok) {
                            bloc.add(
                              DetailLoad(contentUrl, provider: provider),
                            );
                          }
                        }
                      : null,
                  onBack: () => _goBack(context),
                ),
                _ => const SizedBox.shrink(),
              };
            },
          ),
        ),
      ),
    );
  }

  void _goBack(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/main');
    }
  }
}

class _DetailView extends StatefulWidget {
  const _DetailView({
    required this.detail,
    this.provider,
    this.autoPlay = false,
    this.resumeEpisodeIndex,
    this.heroTag,
  });
  final DetailEntity detail;
  final String? provider;
  final bool autoPlay;
  final int? resumeEpisodeIndex;
  final String? heroTag;

  @override
  State<_DetailView> createState() => _DetailViewState();
}

class _DetailViewState extends State<_DetailView>
    with TickerProviderStateMixin {
  late final TabController _tabController;
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _bodyPlayKey = GlobalKey();
  final GlobalKey _tabStripKey = GlobalKey();

  /// The three-dot button, so its menu can hang off it.
  final GlobalKey _moreButtonKey = GlobalKey();

  /// Scroll offset at which the tab strip reaches the app bar and pins.
  /// Measured while scrolling; stays infinite until then so that a tab switch
  /// before any scrolling never moves the page.
  double _tabsPinOffset = double.infinity;

  final GlobalKey _listActionShowcaseKey = GlobalKey();
  late final String _showcaseScope = 'detail-private-${identityHashCode(this)}';
  ShowcaseView? _showcaseView;
  bool _privateShowcaseStarted = false;

  final ValueNotifier<double> _collapse = ValueNotifier<double>(0);

  /// Whether the header is still near enough the top for a flight to make
  /// sense on the way back.
  ///
  /// The Hero stays in the tree while the page is scrolled — invisible under
  /// the scrim, but with an unchanged global rect. Pressing back from there
  /// animated a full-opacity poster out of nothing near the top edge, into a
  /// grid the viewer could not see. Dropping the tag makes Hero find no
  /// partner and the pop falls back to the route's own fade, which is what a
  /// scrolled page should do.
  ///
  /// Read when a flight STARTS, so flipping it mid-scroll costs one rebuild
  /// rather than one per frame.
  final ValueNotifier<bool> _heroActive = ValueNotifier<bool>(true);
  final ValueNotifier<bool> _showPill = ValueNotifier<bool>(false);

  late final List<String> _tabs;
  late final bool _hasCast;
  late final bool _hasShots;
  double _collapseRange = 1;
  bool _autoPlayTriggered = false;
  bool _isFollowing = false;

  @override
  void initState() {
    super.initState();
    _hasCast =
        widget.detail.cast.isNotEmpty ||
        (widget.detail.director?.trim().isNotEmpty ?? false);
    _hasShots = widget.detail.screenshots.isNotEmpty;
    _isFollowing = getIt<FollowService>().isFollowed(widget.detail.contentUrl);
    _tabs = [
      'Similar',
      // Always offered, because whether there is anything to show cannot be
      // known without asking AniList — and asking on every detail load would
      // pay for it on every title nobody opens the tab for.
      'Relations',
      if (_hasCast) 'Cast',
      'Comments',
      if (_hasShots) 'Screenshots',
    ];
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(_onTabChanged);
    _scrollController.addListener(_onScroll);
    _showcaseView = ShowcaseView.register(
      scope: _showcaseScope,
      blurValue: 1.5,
      overlayColor: Colors.black,
      overlayOpacity: 0.76,
      skipIfTargetNotPresent: true,
      onFinish: _markPrivateShowcaseSeen,
      onDismiss: (_) => _markPrivateShowcaseSeen(),
    );
    if (widget.autoPlay && !_autoPlayTriggered) {
      _autoPlayTriggered = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onPrimaryAction();
      });
    }
    _maybeShowPrivateShowcase();
  }

  void _maybeShowPrivateShowcase() {
    if (_privateShowcaseStarted ||
        getIt<HiveService>().hasSeenPrivateShowcase) {
      return;
    }
    _privateShowcaseStarted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Future<void>.delayed(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        _showcaseView?.startShowCase([_listActionShowcaseKey]);
        _markPrivateShowcaseSeen();
      });
    });
  }

  void _markPrivateShowcaseSeen() {
    if (getIt<HiveService>().hasSeenPrivateShowcase) return;
    unawaited(getIt<HiveService>().markPrivateShowcaseSeen());
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) return;
    if (mounted) setState(() {});
    _settleOnTabs();
  }

  /// Tabs differ wildly in height — thirty related posters against an empty
  /// cast list. Switching while scrolled deep into a tall tab left the scroll
  /// position past the end of the short one, and the viewport snapped. Riding
  /// back to the tab strip lands on a position every tab can hold.
  void _settleOnTabs() {
    if (!_scrollController.hasClients) return;
    if (!_tabsPinOffset.isFinite) return;
    if (_scrollController.offset <= _tabsPinOffset) return;
    _scrollController.animateTo(
      _tabsPinOffset,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  double _swipeAccum = 0;

  void _onSwipeStart(DragStartDetails _) {
    _swipeAccum = 0;
  }

  void _onSwipeUpdate(DragUpdateDetails details) {
    _swipeAccum += details.primaryDelta ?? 0;
  }

  void _onSwipeEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final distance = _swipeAccum;
    final i = _tabController.index;
    final goNext = (velocity < -80) || (distance < -40);
    final goPrev = (velocity > 80) || (distance > 40);
    if (goNext && i < _tabs.length - 1) {
      _tabController.animateTo(i + 1);
    } else if (goPrev && i > 0) {
      _tabController.animateTo(i - 1);
    }
    _swipeAccum = 0;
  }

  void _onScroll() {
    final offset = _scrollController.offset;
    final v = (offset / _collapseRange).clamp(0.0, 1.0);
    if ((v - _collapse.value).abs() > 0.005) {
      _collapse.value = v;
    }

    // Assigned only on a change: a ValueNotifier notifies on every set, and
    // this one drives a rebuild of the whole header.
    final active = v < 0.4;
    if (active != _heroActive.value) _heroActive.value = active;

    final pinLine = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final stripBox =
        _tabStripKey.currentContext?.findRenderObject() as RenderBox?;
    if (stripBox != null && stripBox.hasSize) {
      final top = stripBox.localToGlobal(Offset.zero).dy;
      if (top > pinLine) _tabsPinOffset = offset + (top - pinLine);
    }

    final renderBox =
        _bodyPlayKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null && renderBox.hasSize) {
      final pos = renderBox.localToGlobal(Offset.zero);
      final topThreshold = pinLine - 4;
      final hidden = (pos.dy + renderBox.size.height) < topThreshold;
      if (hidden != _showPill.value) {
        _showPill.value = hidden;
      }
    }
  }

  @override
  void dispose() {
    _showcaseView?.unregister();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _collapse.dispose();
    _heroActive.dispose();
    _showPill.dispose();
    super.dispose();
  }

  String _tabLabel(String tab) => switch (tab) {
    'Similar' => 'detail.similar'.tr(),
    'Relations' => 'detail.relations'.tr(),
    'Cast' => 'movie.cast'.tr(),
    'Comments' => 'detail.comments'.tr(),
    'Screenshots' => 'detail.screenshots'.tr(),
    _ => tab,
  };

  Widget _buildTabContent(DetailEntity detail) {
    final tab = _tabs[_tabController.index];
    // Tabs used to cut over on the frame the index changed, which on a page
    // this dense reads as a flicker rather than a change of view. Aligned to
    // the top so the outgoing and incoming panes do not slide against each
    // other while they cross-fade.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 160),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, ?current],
      ),
      child: KeyedSubtree(
        key: ValueKey('detail-tab-$tab'),
        child: switch (tab) {
          'Similar' => DetailRelatedSection(related: detail.related),
          'Relations' => DetailRelationsTab(
            provider: detail.provider,
            contentUrl: detail.contentUrl,
            title: detail.title,
          ),
          'Cast' => DetailCastTab(cast: detail.cast, director: detail.director),
          'Comments' => DetailCommentsTab(
            provider: detail.provider,
            contentUrl: detail.contentUrl,
          ),
          'Screenshots' => DetailScreenshotsSection(
            screenshots: detail.screenshots,
          ),
          _ => const SizedBox.shrink(),
        },
      ),
    );
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/main');
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.surface,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _onPrimaryAction() {
    final state = context.read<EpisodesBloc>().state;
    if (state is EpisodesLoading) return;
    _pendingDownload = false;
    context.read<EpisodesBloc>().add(
      EpisodesLoad(widget.detail.contentUrl, provider: widget.provider),
    );
  }

  /// Play and download need the same thing first — the provider's playback
  /// payload — and it arrives asynchronously through the bloc. Rather than a
  /// second loader, the intent is remembered and the one result is routed when
  /// it lands.
  bool _pendingDownload = false;

  void _onDownloadAction() {
    final state = context.read<EpisodesBloc>().state;
    if (state is EpisodesLoading) return;
    _pendingDownload = true;
    context.read<EpisodesBloc>().add(
      EpisodesLoad(widget.detail.contentUrl, provider: widget.provider),
    );
  }

  /// Where "download" goes once the payload is in.
  ///
  /// A series does not download from here: which episodes is a real question
  /// with a real answer screen, and guessing (all of them? the next one?) is
  /// worse than showing the list where each row has its own button and several
  /// can be picked at once.
  void _handleDownload(PlaybackEntity playback) {
    if (playback.provider.opensReader || playback.isSerial) {
      if (playback.episodes.isEmpty) {
        _showSnack('detail.no_episodes'.tr());
        return;
      }
      _openEpisodes(playback);
      return;
    }
    unawaited(_downloadMovie(playback));
  }

  Future<void> _downloadMovie(PlaybackEntity playback) async {
    // Whether this is already queued, running or finished is the repository's
    // question — it is the only thing that can also tell whether a row marked
    // "downloaded" still has a file behind it. Asking here meant a stale row
    // blocked the very re-download that would have repaired it.
    var url = _pickMovieUrl(playback);
    var headers = playback.headers;

    // An embed page rather than a stream: the same resolve the player does on
    // open. Downloading the page would produce an unplayable HTML file.
    final ref = playback.episodes.isNotEmpty
        ? playback.episodes.first.mediaRef
        : '';
    final needsResolve = playback.type == 'webview-extract' ||
        url == null ||
        url.isEmpty;
    if (needsResolve && ref.isNotEmpty) {
      final result = await getIt<ResolveMediaUseCase>()(
        ref: ref,
        provider: playback.provider,
      );
      if (!mounted) return;
      if (result is Success<MediaResolveEntity> &&
          result.value.videoUrl.isNotEmpty) {
        // Same hazard as the episode list: under a directive this url is the
        // embed page, and nothing here will sniff it. Refuse with advice
        // rather than downloading an HTML file that fails on first open.
        if (!DownloadChoices.isDownloadableUrl(
          url: result.value.videoUrl,
          type: result.value.type,
          hasDirective: result.value.extractor != null,
        )) {
          _showSnack('detail.download_needs_playback'.tr());
          return;
        }
        url = result.value.videoUrl;
        headers = result.value.headers;
      }
    }

    if (url == null || url.isEmpty) {
      _showSnack('detail.download_resolve_failed'.tr());
      return;
    }

    final outcome = await getIt<EnqueueDownloadUseCase>()(
      DownloadRequest.video(
        contentUrl: widget.detail.contentUrl,
        provider: playback.provider,
        title: widget.detail.title,
        sourceUrl: url,
        thumbnailUrl: widget.detail.thumbnail,
        headers: headers,
      ),
    );
    if (!mounted) return;
    _showSnack(downloadOutcomeMessage(outcome));
  }

  void _toggleMyList() {
    context.read<FavoriteBloc>().add(
      FavoriteToggle(
        contentUrl: widget.detail.contentUrl,
        provider: widget.detail.provider,
        title: widget.detail.title,
        thumbnail: widget.detail.thumbnail ?? '',
      ),
    );
  }

  Future<void> _onMoveToPrivate() async {
    if (!await requestPrivateUnlock(context)) return;
    if (!mounted) return;

    final detail = widget.detail;
    await getIt<PrivateListService>().add(
      FavoriteEntity(
        provider: detail.provider,
        contentUrl: detail.contentUrl,
        title: detail.title,
        thumbnail: detail.thumbnail ?? '',
      ),
    );
    await getIt<MyListLocalDataSource>().removeByUrl(detail.contentUrl);
    await getIt<HistoryService>().removeByContentUrl(detail.contentUrl);
    if (!mounted) return;
    context.read<FavoriteBloc>().add(
      FavoriteLoad(
        contentUrl: detail.contentUrl,
        provider: detail.provider,
        isFavorited: false,
      ),
    );
    _showSnack('app_lock.moved_to_private'.tr());
  }

  void _showPrivateActions() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textHint,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(
                  Icons.playlist_add_rounded,
                  color: AppColors.textSecondary,
                ),
                title: Text(
                  'app_lock.move_to_my_list'.tr(),
                  style: const TextStyle(color: AppColors.textPrimary),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _moveFromPrivateToMyList();
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppColors.error,
                ),
                title: Text(
                  'app_lock.removed_from_private'.tr(),
                  style: const TextStyle(color: AppColors.error),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _removeFromPrivate();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _moveFromPrivateToMyList() async {
    final detail = widget.detail;
    await getIt<PrivateListService>().remove(detail.contentUrl);
    await getIt<MyListLocalDataSource>().add(
      FavoriteEntity(
        provider: detail.provider,
        contentUrl: detail.contentUrl,
        title: detail.title,
        thumbnail: detail.thumbnail ?? '',
      ),
    );
    if (!mounted) return;
    context.read<FavoriteBloc>().add(
      FavoriteLoad(
        contentUrl: detail.contentUrl,
        provider: detail.provider,
        isFavorited: true,
      ),
    );
    _showSnack('app_lock.move_to_my_list'.tr());
  }

  Future<void> _removeFromPrivate() async {
    final detail = widget.detail;
    await getIt<PrivateListService>().remove(detail.contentUrl);
    if (!mounted) return;
    context.read<FavoriteBloc>().add(
      FavoriteLoad(
        contentUrl: detail.contentUrl,
        provider: detail.provider,
        isFavorited: false,
      ),
    );
    _showSnack('app_lock.removed_from_private'.tr());
  }

  /// Find this title on another source, without leaving the page.
  ///
  /// It used to open the cross-search screen with the title prefilled, which
  /// works but is the long way round: search, find the row, open its detail
  /// page, press play. The sheet searches the same providers and hands back
  /// something playable, so the same intent is two taps instead of five.
  ///
  /// A series keeps its place. Whatever episode the viewer had reached here is
  /// matched by NUMBER on the other source, because two catalogues rarely agree
  /// on where a season starts — and landing someone on the wrong episode of the
  /// right show is worse than saying this source cannot continue from there.
  ///
  /// Falls back to the old screen when nothing matched, rather than leaving a
  /// dead end: cross-search casts a wider net and lets them look by hand.
  Future<void> _onFindOtherSources() async {
    final detail = widget.detail;
    final history = getIt<HistoryService>().get(detail.contentUrl);

    final args = await AlternateSourceSheet.show(
      context,
      title: detail.title,
      provider: detail.provider,
      category: getIt<HiveService>().providerCategory(detail.provider),
      episodeNumber: history?.episodeNumber,
      headers: const {},
    );
    if (!mounted) return;
    if (args == null) return;
    if (!await confirmPlayerEngine(context) || !mounted) return;
    context.push('/player', extra: args);
  }

  Future<void> _toggleFollow() async {
    final svc = getIt<FollowService>();
    if (_isFollowing) {
      await svc.unfollow(widget.detail.contentUrl);
    } else {
      final d = widget.detail;
      await svc.follow(
        FollowedTitle(
          contentUrl: d.contentUrl,
          provider: d.provider,
          title: d.title,
          thumbnail: d.thumbnail ?? '',
          year: d.year,
          addedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }
    if (!mounted) return;
    setState(() => _isFollowing = !_isFollowing);
    _showSnack(
      _isFollowing ? 'detail.following_on'.tr() : 'detail.following_off'.tr(),
    );
  }

  /// The public link to this title — the one Share sends and Copy hands over.
  String get _shareLink {
    final params = <String, String>{'url': widget.detail.contentUrl};
    final provider = widget.detail.provider.trim();
    if (provider.isNotEmpty) params['provider'] = provider;
    return Uri.https('sozo.azamov.me', '/detail', params).toString();
  }

  void _onShare() {
    Share.share('${widget.detail.title}\n$_shareLink');
  }

  void _showMoreMenu() {
    final detail = widget.detail;
    final favState = context.read<FavoriteBloc>().state;
    showDetailMoreMenu(
      context,
      anchorKey: _moreButtonKey,
      entity: FavoriteEntity(
        provider: detail.provider,
        contentUrl: detail.contentUrl,
        title: detail.title,
        thumbnail: detail.thumbnail ?? '',
      ),
      showFollow: detail.isSerial,
      isFollowing: _isFollowing,
      onToggleFollow: _toggleFollow,
      onFindSources: _onFindOtherSources,
      onShare: _onShare,
      shareUrl: _shareLink,
      // Moving a title to the private list was a long-press on the + button and
      // nothing else — a gesture the app had to run a coaching overlay to teach.
      inPrivate: favState is FavoriteReady && favState.inPrivate,
      onMoveToPrivate: _onMoveToPrivate,
      onPrivateActions: _showPrivateActions,
    );
  }

  void _handlePlayback(PlaybackEntity playback) {
    // A reading source ALWAYS goes through the chapter list, even when it
    // reports a single chapter (one-shots, and Mangayomi novels that expose one
    // entry). Falling through to the movie path would hand a chapter url to the
    // video player, which then spins forever looking for a stream that does not
    // exist.
    if (playback.provider.opensReader && playback.episodes.isNotEmpty) {
      _openEpisodes(playback);
      return;
    }
    if (playback.isSerial) {
      if (playback.episodes.isEmpty) {
        _showSnack('detail.no_episodes'.tr());
        return;
      }
      _openEpisodes(playback);
      return;
    }

    if (kDebugMode) {
      debugPrint(
        '[DETAIL] movie playback — type=${playback.type} '
        'playerSrc=${playback.playerSrc} '
        'sources=${playback.videoSources.length} '
        'ref=${playback.episodes.isNotEmpty ? playback.episodes.first.mediaRef : '-'}',
      );
    }

    final ref = playback.episodes.isNotEmpty
        ? playback.episodes.first.mediaRef
        : '';
    final needsResolve =
        playback.type == 'webview-extract' ||
        playback.playerSrc == null ||
        playback.playerSrc!.isEmpty;
    if (needsResolve && ref.isNotEmpty) {
      unawaited(_resolveAndPlayMovie(playback, ref));
      return;
    }

    _playMovieDirect(playback);
  }

  void _openEpisodes(PlaybackEntity playback) {
    context.push(
      '/episodes',
      extra: EpisodesArgs(
        title: widget.detail.title,
        contentUrl: playback.contentUrl.isNotEmpty
            ? playback.contentUrl
            : widget.detail.contentUrl,
        provider: playback.provider,
        thumbnail: widget.detail.thumbnail,
        episodes: playback.episodes,
        headers: playback.headers,
        page: playback.page,
        size: playback.size,
        total: playback.total,
        totalPages: playback.totalPages,
      ),
    );
  }

  /// The stream a movie should use: the provider's own pick, else the default
  /// accessible source, else any accessible one, else whatever exists.
  String? _pickMovieUrl(PlaybackEntity playback) {
    final direct = playback.playerSrc;
    if (direct != null && direct.isNotEmpty) return direct;

    final sources = playback.videoSources;
    for (final s in sources) {
      if (s.isDefault && s.accessible) return s.videoUrl;
    }
    for (final s in sources) {
      if (s.accessible) return s.videoUrl;
    }
    return sources.isNotEmpty ? sources.first.videoUrl : null;
  }

  Future<void> _playMovieDirect(PlaybackEntity playback) async {
    final movieUrl = _pickMovieUrl(playback);
    if (movieUrl == null || movieUrl.isEmpty) {
      _showSnack('detail.no_playable_source'.tr());
      return;
    }
    Duration resumePos = Duration.zero;
    final historyItem = getIt<HistoryService>().get(widget.detail.contentUrl);
    if (historyItem != null) {
      resumePos = Duration(milliseconds: historyItem.positionMs);
    }
    if (!await confirmPlayerEngine(context) || !mounted) return;
    context.push(
      '/player',
      extra: PlayerArgs(
        title: widget.detail.title,
        provider: playback.provider,
        headers: playback.headers,
        contentUrl: widget.detail.contentUrl,
        thumbnail: widget.detail.thumbnail,
        movieUrl: movieUrl,
        mediaRef: playback.episodes.isNotEmpty
            ? playback.episodes.first.mediaRef
            : null,
        type: playback.type,
        videoSources: playback.videoSources,
        resumePosition: resumePos,
        thumbnails: playback.thumbnails,
      ),
    );
  }

  Future<void> _resolveAndPlayMovie(PlaybackEntity playback, String ref) async {
    var dialogOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (dctx) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 18),
            TextButton(
              onPressed: () => Navigator.of(dctx).pop(),
              child: Text(
                'general.cancel'.tr(),
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
    ).whenComplete(() => dialogOpen = false);

    final result = await getIt<ResolveMediaUseCase>()(
      ref: ref,
      provider: playback.provider,
    );
    if (!mounted) return;
    if (!dialogOpen) return;
    Navigator.of(context, rootNavigator: true).pop();

    switch (result) {
      case Success(:final value):
        if (value.videoUrl.isEmpty) {
          _playMovieDirect(playback);
          return;
        }
        Duration resumePos = Duration.zero;
        final historyItem = getIt<HistoryService>().get(
          widget.detail.contentUrl,
        );
        if (historyItem != null) {
          resumePos = Duration(milliseconds: historyItem.positionMs);
        }
        if (!await confirmPlayerEngine(context) || !mounted) return;
        context.push(
          '/player',
          extra: PlayerArgs(
            title: widget.detail.title,
            provider: playback.provider,
            headers: value.headers,
            contentUrl: widget.detail.contentUrl,
            thumbnail: widget.detail.thumbnail,
            movieUrl: value.videoUrl,
            mediaRef: ref,
            type: value.type,
            // Without this the player has no directive, so a source whose url
            // is an embed page never gets sniffed and ExoPlayer is handed HTML.
            extractor: value.extractor,
            videoSources: value.videoSources,
            resumePosition: resumePos,
            thumbnails: value.thumbnails,
          ),
        );
      case Failure(:final error):
        _showSnack(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    const toolbarHeight = kToolbarHeight;

    // The header's VISIBLE height — one definition, shared with both
    // skeletons. When they disagreed, the header jumped the moment the
    // response landed: right after the poster had finished flying into it,
    // which is the worst possible moment for it to move.
    final heroHeight = detailHeroHeight(context);

    // What SliverAppBar wants is different from what the eye sees. A primary
    // app bar computes `maxExtent = topPadding + expandedHeight` itself, so
    // `expandedHeight` is the header MINUS the status bar. Passing the visible
    // height here counts the inset twice — which is what it used to do, and
    // why the header ended up ~50dp taller than the rectangle the poster had
    // just been animated into.
    final expandedHeight = heroHeight - topPad;

    // Fully collapsed at `maxExtent - minExtent`, and the two topPads cancel:
    // (topPad + expandedHeight) - (topPad + toolbarHeight).
    _collapseRange = expandedHeight - toolbarHeight;

    final detail = widget.detail;

    return MultiBlocListener(
      listeners: [
        BlocListener<EpisodesBloc, EpisodesState>(
          listenWhen: (prev, curr) => prev.runtimeType != curr.runtimeType,
          listener: (context, state) {
            if (state is EpisodesLoaded) {
              if (_pendingDownload) {
                _pendingDownload = false;
                _handleDownload(state.playback);
              } else {
                _handlePlayback(state.playback);
              }
              context.read<EpisodesBloc>().add(const EpisodesReset());
            } else if (state is EpisodesError) {
              _pendingDownload = false;
              _showSnack(state.message);
              context.read<EpisodesBloc>().add(const EpisodesReset());
            }
          },
        ),
        BlocListener<FavoriteBloc, FavoriteState>(
          listenWhen: (prev, curr) {
            if (prev is FavoriteReady && curr is FavoriteReady) {
              return prev.isLoading &&
                  !curr.isLoading &&
                  prev.isInList == curr.isInList;
            }
            return false;
          },
          listener: (context, state) {
            if (state is FavoriteReady) {
              _showSnack(
                state.isInList
                    ? 'detail.added_to_my_list'.tr()
                    : 'detail.removed_from_my_list'.tr(),
              );
            }
          },
        ),
      ],
      child: Stack(
        children: [
          CustomScrollView(
            controller: _scrollController,
            physics: const ClampingScrollPhysics(),
            slivers: [
              SliverAppBar(
                expandedHeight: expandedHeight,
                collapsedHeight: toolbarHeight,
                pinned: true,
                backgroundColor: AppColors.background,
                automaticallyImplyLeading: false,
                elevation: 0,
                scrolledUnderElevation: 0,
                toolbarHeight: toolbarHeight,
                flexibleSpace: FlexibleSpaceBar(
                  collapseMode: CollapseMode.parallax,
                  // The header is built ONCE, in `child:`, and the collapse
                  // paints a scrim over it.
                  //
                  // It used to sit inside the builder with `child:` unused, so
                  // every scroll frame reconstructed the Hero, the
                  // CachedNetworkImage, both gradients, the 26pt title and
                  // _HeroOverlayFade's ancestor walk — the whole subtree, sixty
                  // times a second, on a screen whose only change was one
                  // double.
                  //
                  // The fade is a colour alpha rather than `Opacity`. Opacity
                  // over a full-width ~500dp subtree is an offscreen
                  // compositing pass per frame; a ColoredBox is a rectangle.
                  // It also dissolves the poster INTO the page background
                  // rather than into whatever happens to be behind it.
                  //
                  // Two nested listenables on purpose. The outer one flips at
                  // most once per visit, so rebuilding the header on it costs
                  // nothing; the inner one ticks every frame and gets the
                  // header handed to it as `child`.
                  background: ValueListenableBuilder<bool>(
                    valueListenable: _heroActive,
                    builder: (_, heroActive, _) =>
                        ValueListenableBuilder<double>(
                    valueListenable: _collapse,
                    child: DetailHeroBackground(
                      thumbnail: detail.thumbnail,
                      title: detail.title,
                      heroTag: heroActive ? widget.heroTag : null,
                      trailerQuery: detail.trailerQuery,
                      // The same threshold the hero uses: once the header is
                      // mostly scrolled away there is nothing to preview, and
                      // a video decoding under a page nobody can see is
                      // battery spent on nothing.
                      trailerActive: heroActive,
                    ),
                    builder: (_, c, child) => Stack(
                      fit: StackFit.expand,
                      children: [
                        child!,
                        // IgnorePointer so the scrim never eats a tap meant
                        // for the artwork underneath it.
                        IgnorePointer(
                          child: ColoredBox(
                            color: AppColors.background.withValues(
                              alpha: c.clamp(0.0, 1.0),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: DetailContentHeader(
                  detail: detail,
                  onPrimaryAction: _onPrimaryAction,
                  onDownload: _onDownloadAction,
                  playButtonKey: _bodyPlayKey,
                ),
              ),
              // Sponsor/CMS banner (detail_top placement). Opt-in: self-collapses
              // to nothing unless an admin creates a detail_top banner. Guest-safe.
              const SliverToBoxAdapter(
                child: BannersCarousel(
                  placement: BannerPlacement.detailTop,
                  height: 130,
                  padding: EdgeInsets.fromLTRB(0, 2, 0, 10),
                  // Nothing is held open while the request is in flight. The
                  // usual answer is "no banner here", and reserving 130px for
                  // it meant every detail page opened with a void between the
                  // action row and the tabs, then closed it a few hundred
                  // milliseconds later — moving the page under the poster at
                  // the exact moment it was settling into the header.
                  reserveWhileLoading: false,
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _TabBarDelegate(
                  stripKey: _tabStripKey,
                  tabBar: AppTabBar(
                    labels: _tabs.map(_tabLabel).toList(),
                    // Detail owns the controller: the horizontal swipe at
                    // _onSwipeEnd drives it directly, and a strip that built
                    // its own would stop following the pages.
                    controller: _tabController,
                    // onChanged left null so it does not fire alongside
                    // _onTabChanged, which is already listening to the
                    // controller.
                    showDivider: false,
                    padding: EdgeInsets.zero,
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.only(
                  top: 4,
                  bottom: MediaQuery.paddingOf(context).bottom + 32,
                ),
                sliver: SliverToBoxAdapter(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: _onSwipeStart,
                    onHorizontalDragUpdate: _onSwipeUpdate,
                    onHorizontalDragEnd: _onSwipeEnd,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight:
                            (MediaQuery.sizeOf(context).height -
                                    topPad -
                                    toolbarHeight -
                                    kTextTabBarHeight -
                                    MediaQuery.paddingOf(context).bottom -
                                    36)
                                .clamp(0.0, double.infinity),
                      ),
                      child: _buildTabContent(detail),
                    ),
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: BlocBuilder<FavoriteBloc, FavoriteState>(
              buildWhen: (a, b) {
                if (a is FavoriteReady && b is FavoriteReady) {
                  return a.isInList != b.isInList ||
                      a.isLoading != b.isLoading ||
                      a.inPrivate != b.inPrivate;
                }
                return a.runtimeType != b.runtimeType;
              },
              builder: (context, favState) {
                final isInList = favState is FavoriteReady && favState.isInList;
                final inPrivate =
                    favState is FavoriteReady && favState.inPrivate;
                final showListAction = favState is FavoriteReady;
                final listActionLoading =
                    favState is FavoriteReady && favState.isLoading;
                return ValueListenableBuilder<double>(
                  valueListenable: _collapse,
                  builder: (_, c, _) => ValueListenableBuilder<bool>(
                    valueListenable: _showPill,
                    builder: (_, showPill, _) =>
                        BlocBuilder<EpisodesBloc, EpisodesState>(
                          buildWhen: (a, b) =>
                              (a is EpisodesLoading) != (b is EpisodesLoading),
                          builder: (context, state) => _AnimatedTopBar(
                            collapse: c,
                            showPill: showPill,
                            title: detail.title,
                            reader: detail.provider.opensReader,
                            isInList: isInList,
                            inPrivate: inPrivate,
                            isLoading: state is EpisodesLoading,
                            showListAction: showListAction,
                            isListActionLoading: listActionLoading,
                            listActionShowcaseKey: _listActionShowcaseKey,
                            showcaseScope: _showcaseScope,
                            onBack: _goBack,
                            onPrimaryAction: _onPrimaryAction,
                            onAddToList: _toggleMyList,
                            onMoveToPrivate: _onMoveToPrivate,
                            onPrivateActions: _showPrivateActions,
                            moreButtonKey: _moreButtonKey,
                            onMore: _showMoreMenu,
                          ),
                        ),
                  ),
                );
              },
            ),
          ),
          BlocBuilder<EpisodesBloc, EpisodesState>(
            buildWhen: (a, b) =>
                (a is EpisodesLoading) != (b is EpisodesLoading),
            builder: (_, state) {
              if (state is! EpisodesLoading) return const SizedBox.shrink();
              return const _PlaybackLoadingOverlay();
            },
          ),
        ],
      ),
    );
  }
}

class _PlaybackLoadingOverlay extends StatelessWidget {
  const _PlaybackLoadingOverlay();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.35),
        child: const Center(
          child: SizedBox(
            width: 44,
            height: 44,
            child: CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 2.8,
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedTopBar extends StatelessWidget {
  const _AnimatedTopBar({
    required this.collapse,
    required this.showPill,
    required this.title,
    required this.reader,
    required this.isInList,
    required this.inPrivate,
    required this.isLoading,
    required this.showListAction,
    required this.isListActionLoading,
    required this.listActionShowcaseKey,
    required this.showcaseScope,
    required this.moreButtonKey,
    required this.onBack,
    required this.onPrimaryAction,
    required this.onAddToList,
    required this.onMoveToPrivate,
    required this.onPrivateActions,
    required this.onMore,
  });

  final double collapse;
  final bool showPill;
  final String title;

  /// Reading source — the pill says "Read" rather than "Play".
  final bool reader;
  final bool isInList;
  final bool inPrivate;
  final bool isLoading;
  final bool showListAction;
  final bool isListActionLoading;
  final GlobalKey listActionShowcaseKey;
  final String showcaseScope;
  final GlobalKey moreButtonKey;
  final VoidCallback onBack;
  final VoidCallback onPrimaryAction;
  final VoidCallback onAddToList;
  final VoidCallback onMoveToPrivate;
  final VoidCallback onPrivateActions;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    final solidOpacity = Curves.easeIn.transform(collapse).clamp(0.0, 1.0);
    final titleOpacity = ((collapse - 0.6) / 0.3).clamp(0.0, 1.0);

    return Stack(
      children: [
        // The alpha is folded into the colours rather than wrapped in an
        // Opacity. This Container paints a fill and a hairline border and
        // nothing else, so an offscreen compositing pass per scroll frame
        // bought exactly the same pixels as multiplying two alphas.
        IgnorePointer(
          child: Container(
            height: topPad + kToolbarHeight,
            decoration: BoxDecoration(
              color: AppColors.background.withValues(
                alpha: 0.96 * solidOpacity,
              ),
              border: Border(
                bottom: BorderSide(
                  // Squared on purpose: the border used to be inside the
                  // Opacity too, so it faded with the fill AND with its own
                  // alpha. Keeping that keeps the hairline from arriving
                  // before the surface it sits on.
                  color: AppColors.divider.withValues(
                    alpha: solidOpacity * solidOpacity,
                  ),
                  width: 0.5,
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(top: topPad + 6, left: 8, right: 8),
          child: SizedBox(
            height: kToolbarHeight - 12,
            child: Row(
              children: [
                _CircleIconButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  onTap: onBack,
                  semanticLabel: 'general.back'.tr(),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Builder(
                    builder: (_) => Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      // Alpha in the text colour rather than an Opacity around
                      // it. One line of text does not need its own compositing
                      // layer, and this one was getting a fresh one on every
                      // scroll frame of the collapse.
                      style: TextStyle(
                        color: AppColors.textPrimary.withValues(
                          alpha: titleOpacity,
                        ),
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.25, 0),
                        end: Offset.zero,
                      ).animate(anim),
                      child: child,
                    ),
                  ),
                  child: showPill
                      ? Padding(
                          key: const ValueKey('pill'),
                          padding: const EdgeInsetsDirectional.only(end: 8),
                          child: _ActionPill(
                            onTap: onPrimaryAction,
                            isLoading: isLoading,
                            reader: reader,
                          ),
                        )
                      : const SizedBox(key: ValueKey('no-pill'), width: 0),
                ),
                if (showListAction) ...[
                  Showcase(
                    key: listActionShowcaseKey,
                    scope: showcaseScope,
                    description: 'app_lock.private_long_press_hint'.tr(),
                    targetBorderRadius: BorderRadius.circular(18),
                    targetPadding: const EdgeInsets.all(4),
                    child: _CircleIconButton(
                      icon: isListActionLoading
                          ? Icons.more_horiz_rounded
                          : inPrivate
                          ? Icons.lock_rounded
                          : isInList
                          ? Icons.check_rounded
                          : Icons.add_rounded,
                      iconColor: inPrivate ? AppColors.rating : Colors.white,
                      // The icon has four states and the label follows it —
                      // "Add to list" announced on a button that would in fact
                      // remove it is worse than no label.
                      semanticLabel: inPrivate
                          ? 'detail.in_private_list'.tr()
                          : isInList
                          ? 'detail.remove_from_my_list_action'.tr()
                          : 'detail.add_to_my_list_action'.tr(),
                      onTap: isListActionLoading
                          ? null
                          : inPrivate
                          ? onPrivateActions
                          : onAddToList,
                      onLongPress: isListActionLoading || inPrivate
                          ? null
                          : onMoveToPrivate,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                _CircleIconButton(
                  key: moreButtonKey,
                  icon: Icons.more_vert_rounded,
                  onTap: onMore,
                  semanticLabel: 'detail.more_options'.tr(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The header's round button, at the app's one geometry.
///
/// Kept as a named wrapper only because two call sites attach a GlobalKey to
/// it — the more-menu's popup anchor and the private-list showcase target —
/// and those keys have to ride a widget this file owns.
class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
    this.onLongPress,
    this.iconColor = Colors.white,
  });
  final IconData icon;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color iconColor;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) => DetailCircleButton(
    icon: icon,
    onTap: onTap,
    onLongPress: onLongPress,
    iconColor: iconColor,
    semanticLabel: semanticLabel,
  );
}

class _ActionPill extends StatelessWidget {
  const _ActionPill({
    required this.onTap,
    required this.isLoading,
    this.reader = false,
  });
  final VoidCallback onTap;
  final bool isLoading;

  /// Reading source — the collapsed app-bar pill mirrors the main button.
  final bool reader;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: isLoading ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isLoading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.black,
                  ),
                )
              else
                Icon(
                  reader ? Icons.menu_book_rounded : Icons.play_arrow_rounded,
                  size: reader ? 16 : 18,
                  color: Colors.black,
                ),
              const SizedBox(width: 4),
              Text(
                reader ? 'detail.read'.tr() : 'detail.play'.tr(),
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pins the tab strip under the collapsing header.
///
/// The height comes from [AppTabBar]'s own constants rather than being derived
/// here. Both detail skeletons stand in for this strip and have to match it to
/// the pixel; when each of the three carried its own arithmetic, one of them
/// used `kTextTabBarHeight` (48) against the real 46 + 2.5 + 0.5, and every
/// sliver below the pinned header sat 2pt out.
class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  const _TabBarDelegate({required this.tabBar, required this.stripKey});
  final AppTabBar tabBar;
  final GlobalKey stripKey;

  static const double _height =
      AppTabBar.stripHeight + AppTabBar.dividerHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      key: stripKey,
      color: AppColors.background,
      child: Column(
        children: [
          SizedBox(
            height: AppTabBar.stripHeight,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(start: 8),
              child: tabBar,
            ),
          ),
          Container(height: AppTabBar.dividerHeight, color: AppColors.divider),
        ],
      ),
    );
  }

  @override
  double get maxExtent => _height;

  @override
  double get minExtent => _height;

  /// Compared on what actually changes.
  ///
  /// The old version compared the TabBar instances, which are freshly
  /// allocated on every build and have no `==` — so this always returned true
  /// and only looked like an optimisation.
  @override
  bool shouldRebuild(_TabBarDelegate old) =>
      !identical(tabBar.controller, old.tabBar.controller) ||
      tabBar.labels.length != old.tabBar.labels.length;
}

class _BackOnlyBar extends StatelessWidget {
  const _BackOnlyBar({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    return Positioned(
      top: topPad + 8,
      left: 8,
      // The same button the loaded page shows. This is the one control on
      // screen across the whole load, so any difference between the two is a
      // jump in the thing the eye is already resting on.
      child: DetailCircleButton(
        icon: Icons.arrow_back_ios_new_rounded,
        onTap: onBack,
        semanticLabel: 'general.back'.tr(),
      ),
    );
  }
}

/// The back affordance on the detail error screen. On Android TV this is the
/// only way off a failed page other than the system BACK key, so it must be a
/// focus stop; a bare GestureDetector could never be reached by the D-pad.
class _ErrorBackButton extends StatelessWidget {
  const _ErrorBackButton({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final button = Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surfaceVariant,
      ),
      child: const Icon(
        Icons.arrow_back_ios_new_rounded,
        color: AppColors.textPrimary,
        size: 17,
      ),
    );

    // Off TV this returns exactly the GestureDetector that was here before.
    if (isTvPlatform) {
      return TvFocusable(
        onPressed: onBack,
        borderRadius: 19,
        autofocus: true,
        child: button,
      );
    }

    return GestureDetector(onTap: onBack, child: button);
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.onRetry,
    required this.onBack,
    this.onSolveCloudflare,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onBack;
  final Future<void> Function()? onSolveCloudflare;

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    return Padding(
      padding: EdgeInsets.only(top: topPad + 8),
      child: Column(
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(start: 8),
              child: _ErrorBackButton(onBack: onBack),
            ),
          ),
          const Spacer(),
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.textHint,
            size: 52,
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              message,
              textAlign: TextAlign.center,
              // Provider errors can be paragraphs long; unbounded they pushed
              // Retry off the bottom of the Column.
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(onPressed: onRetry, child: Text('general.retry'.tr())),
          if (onSolveCloudflare != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onSolveCloudflare,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: BorderSide(color: AppColors.border),
              ),
              icon: const Icon(Icons.shield_outlined, size: 18),
              label: Text('cloudflare.solve'.tr()),
            ),
          ],
          const Spacer(),
        ],
      ),
    );
  }
}
