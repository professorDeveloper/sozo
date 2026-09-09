import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/navigation/app_tab.dart';
import 'package:soplay/core/navigation/nav_controller.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/theme/app_theme.dart';
import 'package:soplay/core/tv/tv.dart';
import 'package:soplay/features/banners/domain/entities/banner_item.dart';
import 'package:soplay/features/banners/presentation/bloc/banners_bloc.dart';
import 'package:soplay/features/banners/presentation/widgets/banners_carousel.dart';
import 'package:soplay/features/history/data/history_service.dart';
import 'package:soplay/features/history/domain/entities/history_item.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:soplay/features/home/domain/entities/hero_slide.dart';
import 'package:soplay/features/home/domain/entities/home_section_entity.dart';
import 'package:soplay/features/home/presentation/bloc/home/home_bloc.dart';
import 'package:soplay/features/home/presentation/bloc/home/home_event.dart';
import 'package:soplay/features/home/domain/home_rail.dart';
import 'package:soplay/features/home/presentation/widgets/home_banner.dart';
import 'package:soplay/features/home/presentation/widgets/home_history_section.dart';
import 'package:soplay/features/home/presentation/widgets/home_live_tv_section.dart';
import 'package:soplay/features/home/presentation/widgets/home_movie_section.dart';
import 'package:soplay/features/home/presentation/widgets/home_state_views.dart';
import 'package:soplay/features/search/domain/entities/genre_entity.dart';

import 'package:soplay/features/home/domain/catalogue_status.dart';
import '../bloc/home/home_state.dart';
import 'genre_card.dart';

bool _isMyListSection(HomeSectionEntity section) {
  final hay = '${section.key} ${section.viewAll.type} ${section.viewAll.slug}'
      .toLowerCase();
  return hay.contains('my-list') ||
      hay.contains('mylist') ||
      hay.contains('my_list') ||
      hay.contains('favorite') ||
      hay.contains('favourite') ||
      hay.contains('watchlist');
}

class HomeContent extends StatefulWidget {
  const HomeContent({
    super.key,
    required this.catalogue,
    required this.blurProgress,
  });

  /// Ready or failed. Home renders either way — see [CatalogueStatus].
  final CatalogueStatus catalogue;

  /// Owned by HomePage (which mounts the top bar once, outside the bloc
  /// builder); we only publish our scroll progress into it.
  final ValueNotifier<double> blurProgress;

  @override
  State<HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends State<HomeContent> {
  late final ScrollController _scrollController;
  final HistoryService _historyService = getIt<HistoryService>();
  List<HistoryItem> _historyItems = const [];

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_handleScroll);
    _historyService.revision.addListener(_loadHistory);
    _loadHistory();
    TelegramPromo.maybeShow(context);
  }

  void _loadHistory() {
    final items = _historyService.getAll();
    if (!mounted) return;
    setState(() => _historyItems = items);
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final next = ((_scrollController.offset - 250) / 150).clamp(0.0, 1.0);
    if ((next - widget.blurProgress.value).abs() < 0.02) return;
    widget.blurProgress.value = next;
  }

  @override
  void dispose() {
    _historyService.revision.removeListener(_loadHistory);
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;

    return BlocProvider<BannersBloc>(
      create: (_) =>
          getIt<BannersBloc>()..add(BannersLoad(BannerPlacement.homeTop)),
      child: _HomeContentBody(
        catalogue: widget.catalogue,
        topPad: topPad,
        scrollController: _scrollController,
        historyItems: _historyItems,
        onRefresh: () async {
          context.read<HomeBloc>().add(HomeLoad(silent: true));
          await Future.wait([
            context.read<HomeBloc>().stream.firstWhere(
              (state) => state is HomeLoaded || state is HomeError,
            ),
            Future<void>.delayed(const Duration(milliseconds: 850)),
          ]);
          _loadHistory();
        },
      ),
    );
  }
}

class _HomeContentBody extends StatelessWidget {
  const _HomeContentBody({
    required this.catalogue,
    required this.topPad,
    required this.scrollController,
    required this.historyItems,
    required this.onRefresh,
  });

  final CatalogueStatus catalogue;
  final double topPad;
  final ScrollController scrollController;
  final List<HistoryItem> historyItems;
  final Future<void> Function() onRefresh;

  /// The loaded catalogue, or null when it failed. Every read below goes
  /// through this, so a failure cannot be mistaken for empty data.
  HomeLoaded? get _loaded =>
      catalogue is CatalogueReady ? (catalogue as CatalogueReady).data : null;

  List<HeroSlide> _composeSlides(List<BannerItem> cmsBanners) {
    final data = _loaded;
    return [
      if (data != null)
        for (final m in data.homeData.banner) MovieHeroSlide(m),
      for (final b in cmsBanners) BannerHeroSlide(b),
    ];
  }

  @override
  Widget build(BuildContext context) {
    // No top bar here — HomePage mounts it once above this subtree.
    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: AppColors.surface,
      edgeOffset: topPad + 10,
      displacement: topPad + 10,
      strokeWidth: 2.6,
      onRefresh: onRefresh,
      child: BlocBuilder<BannersBloc, BannersState>(
        builder: (context, bannersState) {
          final slides = _composeSlides(bannersState.items);
          final showHero = slides.isNotEmpty || bannersState.loading;

          final loaded = _loaded;
          final sectionSlivers = <Widget>[
            if (loaded != null)
            for (final section in loaded.homeData.sections)
              if (section.items.isNotEmpty)
                SliverToBoxAdapter(
                  child: RepaintBoundary(
                    child: MovieSection(
                      title: section.label,
                      movies: section.items,
                      type: section.viewAll.type,
                      slug: section.viewAll.slug,
                      onSeeAll: _isMyListSection(section)
                          ? () => getIt<NavController>().goToId(TabId.myList)
                          : null,
                    ),
                  ),
                ),
          ];

          // Unchanged in meaning, with one addition: a FAILED catalogue is
          // never "empty". Empty means the source returned nothing and there is
          // genuinely nothing to show; failed means we could not ask, and the
          // strip below has to be reachable to say so.
          final isEmpty = catalogue is CatalogueReady &&
              !showHero &&
              historyItems.isEmpty &&
              (loaded?.genres.isEmpty ?? true) &&
              sectionSlivers.isEmpty;
          if (isEmpty) {
            return CustomScrollView(
              controller: scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: EdgeInsets.only(top: topPad + 56),
                    child: HomeEmptyView(onRefresh: onRefresh),
                  ),
                ),
              ],
            );
          }

          // Sponsor/CMS banner strip mid-feed (home_middle placement). It
          // self-collapses when the placement has no active banners, and its
          // view/click tracking is guest-safe (no auth required).
          if (sectionSlivers.isNotEmpty) {
            final mid = (sectionSlivers.length / 2)
                .ceil()
                .clamp(1, sectionSlivers.length);
            sectionSlivers.insert(
              mid,
              const SliverToBoxAdapter(
                child: BannersCarousel(
                  placement: BannerPlacement.homeMiddle,
                ),
              ),
            );
          }

          // The bands, in the order this install put them in. Each one still
          // decides for itself whether it has anything to show — reordering
          // never makes an empty rail appear, and hiding one is separate from
          // it being empty.
          final hive = getIt<HiveService>();
          final rails = visibleRails(
            sanitizeRailOrder(hive.getHomeRailOrder()),
            hive.getHomeRailHidden(),
          );

          Iterable<Widget> sliversFor(HomeRail rail) sync* {
            switch (rail) {
              case HomeRail.hero:
                if (showHero) {
                  yield SliverToBoxAdapter(
                    child: HomeBanner(
                      slides: slides,
                      topPadding: topPad,
                      showSkeleton:
                          (loaded?.homeData.banner.isEmpty ?? true) &&
                              bannersState.loading,
                    ),
                  );
                }
              case HomeRail.resume:
                if (historyItems.isNotEmpty) {
                  yield SliverToBoxAdapter(
                    child: RepaintBoundary(
                      child: HistorySection(items: historyItems),
                    ),
                  );
                }
              case HomeRail.genres:
                if (loaded != null && loaded.genres.isNotEmpty) {
                  yield SliverToBoxAdapter(
                    child: RepaintBoundary(
                      child: _GenreSection(genres: loaded.genres),
                    ),
                  );
                }
              case HomeRail.liveTv:
                // Loads itself and renders nothing until it has channels, so a
                // backend with no line-up leaves Home unchanged.
                yield const SliverToBoxAdapter(
                  child: RepaintBoundary(child: LiveTvSection()),
                );
              case HomeRail.catalogue:
                if (loaded != null && loaded.collectionLoading) {
                  yield const SliverToBoxAdapter(child: CollectionLoadingRow());
                }
                yield* sectionSlivers;
            }
          }

          // The hero sits under the status bar when it is first. Moved down, it
          // is an ordinary rail and something else needs that clearance —
          // otherwise the top band renders behind the clock.
          final needsTopPad = rails.first != HomeRail.hero || !showHero;

          return CustomScrollView(
            controller: scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (needsTopPad)
                SliverToBoxAdapter(child: SizedBox(height: topPad + 56)),
              // Above the rails, because it explains why some of them are
              // missing. Everything below it is local and still works.
              if (catalogue case CatalogueFailed(:final message))
                SliverToBoxAdapter(child: HomeErrorStrip(message: message)),
              for (final rail in rails) ...sliversFor(rail),
              SliverToBoxAdapter(
                child: SizedBox(
                  // Clear the floating nav capsule: desktop pill (~66+18) and
                  // mobile glass capsule (62 bar + 12 gap + safe area).
                  height: isDesktopPlatform
                      ? 100
                      : MediaQuery.paddingOf(context).bottom + 88,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _GenreSection extends StatelessWidget {
  const _GenreSection({required this.genres});

  final List<GenreEntity> genres;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(17, 18, 16, 14),
            child: Text(
              "home.genres".tr(),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
          ),
          SizedBox(
            height: isDesktopPlatform ? 90 : 72,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              // Don't clip the hover scale on desktop, as MovieSection does.
              clipBehavior: isDesktopPlatform ? Clip.none : Clip.hardEdge,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: genres.length,
              itemBuilder: (_, i) => GenreCard(genre: genres[i]),
            ),
          ),
        ],
      ),
    );
  }
}

/// One-shot gate for the "Join our Telegram" sheet.
///
/// WHY THIS EXISTS (the "two sheets at once" bug):
/// the sheet used to be pushed straight from `_HomeContentState.initState`,
/// which tied the decision to the lifetime of a WIDGET instead of to the app
/// session. [HomeContent] is destroyed and rebuilt on every
/// `HomeLoading`/`HomeError` -> `HomeLoaded` transition of the app-level
/// `HomeBloc` (see `home_page.dart`), and a modal route is NOT torn down when
/// the widget that pushed it is disposed — so a second mount pushed a second
/// sheet on top of the first one, which was still sitting on the Navigator.
///
/// These statics live for the whole isolate, so the gate survives any rebuild,
/// remount, tab reorder or nav-style change. [_claimed] is taken BEFORE the
/// post-frame gap, so two mounts inside the SAME frame can never both get past
/// it.
class TelegramPromo {
  TelegramPromo._();

  static const String _channelUrl = 'https://t.me/sozoApp';

  /// The promo has already been shown (or deliberately skipped) this launch.
  static bool _claimed = false;

  /// A promo sheet is on the Navigator right now.
  static bool _open = false;

  /// Show the promo at most once per app launch, and never while one is open.
  static void maybeShow(BuildContext context) {
    if (_claimed || _open) return;

    final hive = getIt<HiveService>();
    if (hive.hasTelegramPromoSeen) {
      _claimed = true;
      return;
    }

    // Claim the slot synchronously: a second HomeContent mounting later in this
    // same frame hits this guard before we ever reach the frame callback.
    _claimed = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // The mount that claimed the slot is already gone (a bloc state flip tore
      // it down mid-frame). Release the claim so the next mount can show it —
      // still exactly one sheet, just one frame later.
      if (!context.mounted) {
        _claimed = false;
        return;
      }
      // Re-read: the persisted flag may have landed during the frame gap.
      if (hive.hasTelegramPromoSeen || _open) return;

      _open = true;
      showAdaptiveModal<void>(
        context: context,
        backgroundColor: AppColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => _TelegramPromoSheet(
          onJoin: () {
            Navigator.of(ctx).pop();
            launchUrl(
              Uri.parse(_channelUrl),
              mode: LaunchMode.externalApplication,
            );
          },
          onDismiss: (dontShowAgain) {
            if (dontShowAgain) hive.markTelegramPromoSeen();
            Navigator.of(ctx).pop();
          },
          // Persist on every toggle (including untick) so the checkbox still
          // works when the sheet is closed by a swipe or a barrier tap, which
          // never routes through onDismiss.
          onDontShowAgain: hive.setTelegramPromoSeen,
        ),
        // Covers every close path: button, swipe, barrier tap, system back.
      ).whenComplete(() => _open = false);
    });
  }
}

class _TelegramPromoSheet extends StatefulWidget {
  const _TelegramPromoSheet({
    required this.onJoin,
    required this.onDismiss,
    required this.onDontShowAgain,
  });

  final VoidCallback onJoin;
  final void Function(bool dontShowAgain) onDismiss;
  final void Function(bool dontShowAgain) onDontShowAgain;

  @override
  State<_TelegramPromoSheet> createState() => _TelegramPromoSheetState();
}

class _TelegramPromoSheetState extends State<_TelegramPromoSheet> {
  bool _dontShow = false;

  void _toggleDontShow() {
    setState(() => _dontShow = !_dontShow);
    widget.onDontShowAgain(_dontShow);
  }

  @override
  Widget build(BuildContext context) {
    final dontShowRow = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: _dontShow ? const Color(0xFF2AABEE) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: _dontShow ? const Color(0xFF2AABEE) : AppColors.textHint,
              width: 1.5,
            ),
          ),
          child: _dontShow
              ? const Icon(Icons.check_rounded, color: Colors.white, size: 12)
              : null,
        ),
        const SizedBox(width: 8),
        Text(
          'home.dont_show_again'.tr(),
          style: const TextStyle(color: AppColors.textHint, fontSize: 12),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFF2AABEE),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.telegram, color: Colors.white, size: 32),
          ),
          const SizedBox(height: 14),
          Text(
            'home.telegram_promo_title'.tr(),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'home.telegram_promo_subtitle'.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: widget.onJoin,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2AABEE),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(kButtonRadius),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.telegram, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'home.telegram_join_channel'.tr(),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          // Android TV: the Join button is an ElevatedButton and focusable for
          // free, but this opt-out sat on a bare GestureDetector, so a remote
          // could never tick it. Off TV the GestureDetector below is the
          // original one.
          if (isTvPlatform)
            TvFocusable(
              onPressed: _toggleDontShow,
              borderRadius: 8,
              scale: 1.0,
              child: dontShowRow,
            )
          else
            GestureDetector(onTap: _toggleDontShow, child: dontShowRow),
        ],
      ),
    );
  }
}
