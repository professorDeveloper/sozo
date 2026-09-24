import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/anilist/presentation/widgets/anilist_brand.dart';
import 'package:soplay/features/trakt/data/trakt_hub_models.dart';
import 'package:soplay/features/trakt/data/trakt_service.dart';
import 'package:soplay/features/trakt/presentation/trakt_brand.dart';
import 'package:soplay/features/trakt/presentation/trakt_connect_sheet.dart';
import 'package:soplay/features/trakt/presentation/trakt_hub_controller.dart';
import 'package:soplay/features/trakt/presentation/trakt_hub_widgets.dart';

/// The viewer's Trakt, inside the app: what is next, the watchlist, the
/// history, what airs soon, what Trakt suggests, what they rated and what
/// everyone is watching — and every title opens here, on the catalogue page
/// that finds a source for it.
class TraktHubPage extends StatefulWidget {
  const TraktHubPage({super.key});

  @override
  State<TraktHubPage> createState() => _TraktHubPageState();
}

enum _Tab { upNext, watchlist, history, calendar, forYou, ratings, trending }

class _TraktHubPageState extends State<TraktHubPage>
    with SingleTickerProviderStateMixin {
  final TraktService _service = getIt<TraktService>();
  late final TraktHubController _hub = TraktHubController(service: _service);
  late final TabController _tabs = TabController(
    length: _Tab.values.length,
    vsync: this,
  );

  @override
  void initState() {
    super.initState();
    _service.addListener(_onService);
    _hub.addListener(_onChange);
    _tabs.addListener(_onTab);
    _loadVisible();
  }

  @override
  void dispose() {
    _service.removeListener(_onService);
    _hub.removeListener(_onChange);
    _tabs.removeListener(_onTab);
    _tabs.dispose();
    _hub.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  /// Connecting from the prompt on this screen fills it in.
  void _onService() {
    if (!mounted) return;
    setState(() {});
    if (_service.isConnected) _loadVisible();
  }

  void _onTab() {
    if (!_tabs.indexIsChanging) _loadVisible();
  }

  void _loadVisible({bool force = false}) {
    if (!_service.isConnected) return;
    _hub.loadStats(force: force);
    switch (_Tab.values[_tabs.index]) {
      case _Tab.upNext:
        _hub.loadUpNext(force: force);
      case _Tab.watchlist:
        _hub.loadWatchlist(force: force);
      case _Tab.history:
        _hub.loadHistory(force: force);
      case _Tab.calendar:
        _hub.loadCalendar(force: force);
      case _Tab.forYou:
        _hub.loadRecommendations(force: force);
      case _Tab.ratings:
        _hub.loadRatings(force: force);
      case _Tab.trending:
        _hub.loadTrending(force: force);
    }
  }

  Future<void> _refresh() async => _loadVisible(force: true);

  String _tabLabel(_Tab t) => switch (t) {
    _Tab.upNext => 'trakt.tab_up_next'.tr(),
    _Tab.watchlist => 'trakt.tab_watchlist'.tr(),
    _Tab.history => 'trakt.tab_history'.tr(),
    _Tab.calendar => 'trakt.tab_calendar'.tr(),
    _Tab.forYou => 'trakt.tab_for_you'.tr(),
    _Tab.ratings => 'trakt.tab_ratings'.tr(),
    _Tab.trending => 'trakt.tab_trending'.tr(),
  };

  @override
  Widget build(BuildContext context) {
    if (!_service.isConnected) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          surfaceTintColor: Colors.transparent,
          title: const Text('Trakt'),
        ),
        body: AnilistConnectPrompt(
          message: 'trakt.hub_connect_prompt'.tr(),
          actionLabel: 'trakt.connect'.tr(),
          busy: false,
          onConnect: () => TraktConnectSheet.show(context),
          accent: kTraktRed,
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: NestedScrollView(
        headerSliverBuilder: (context, inner) => [
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.background,
            surfaceTintColor: Colors.transparent,
            scrolledUnderElevation: 0,
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const TraktLogo(size: 22),
                const SizedBox(width: 8),
                const Text(
                  'Trakt',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'anilist.refresh'.tr(),
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_rounded, size: 20),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: _ProfileHeader(service: _service, hub: _hub),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabBarDelegate(
              TabBar(
                controller: _tabs,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                indicatorColor: kTraktRed,
                indicatorSize: TabBarIndicatorSize.label,
                labelColor: AppColors.textPrimary,
                unselectedLabelColor: AppColors.textSecondary,
                dividerColor: Colors.transparent,
                labelStyle: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
                tabs: [for (final t in _Tab.values) Tab(text: _tabLabel(t))],
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabs,
          children: [
            _UpNextTab(hub: _hub, onRefresh: _refresh),
            _WatchlistTab(hub: _hub, onRefresh: _refresh),
            _HistoryTab(hub: _hub, onRefresh: _refresh),
            _CalendarTab(hub: _hub, onRefresh: _refresh),
            _PosterPairTab(
              hub: _hub,
              movies: _hub.recommendedMovies,
              shows: _hub.recommendedShows,
              onRefresh: _refresh,
              empty: 'trakt.empty_recs'.tr(),
              recommendations: true,
            ),
            _RatingsTab(hub: _hub, onRefresh: _refresh),
            _PosterPairTab(
              hub: _hub,
              movies: _hub.trendingMovies,
              shows: _hub.trendingShows,
              onRefresh: _refresh,
              empty: 'trakt.empty_trending'.tr(),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  _TabBarDelegate(this.tabBar);

  final TabBar tabBar;

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      ColoredBox(color: AppColors.background, child: tabBar);

  @override
  bool shouldRebuild(_TabBarDelegate old) => old.tabBar != tabBar;
}

/// The viewer, over the art of what they watched last, and their numbers.
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.service, required this.hub});

  final TraktService service;
  final TraktHubController hub;

  String? get _backdrop {
    for (final list in [
      hub.playback.items,
      hub.upNext.items,
      hub.history.items,
    ]) {
      for (final e in list) {
        final art = e.media.fanart;
        if (art != null) return art;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final viewer = service.viewer;
    final stats = hub.stats;
    final backdrop = _backdrop;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          children: [
            Positioned.fill(
              child: backdrop == null
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            kTraktRed.withValues(alpha: 0.32),
                            AppColors.surface,
                          ],
                        ),
                      ),
                    )
                  : CachedNetworkImage(imageUrl: backdrop, fit: BoxFit.cover),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.35),
                      Colors.black.withValues(alpha: 0.86),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: kTraktRed,
                          shape: BoxShape.circle,
                        ),
                        child: CircleAvatar(
                          radius: 26,
                          backgroundColor: AppColors.surfaceVariant,
                          backgroundImage: (viewer?.avatarUrl ?? '').isEmpty
                              ? null
                              : CachedNetworkImageProvider(viewer!.avatarUrl!),
                          child: (viewer?.avatarUrl ?? '').isEmpty
                              ? const Icon(
                                  Icons.person_rounded,
                                  color: Colors.white70,
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (viewer?.name ?? '').isNotEmpty
                                  ? viewer!.name
                                  : (viewer?.slug ?? ''),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if ((viewer?.slug ?? '').isNotEmpty)
                              Text(
                                '@${viewer!.slug}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12.5,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _Stat(
                        value: stats?.moviesWatched,
                        label: 'trakt.stat_movies'.tr(),
                      ),
                      _Stat(
                        value: stats?.episodesWatched,
                        label: 'trakt.stat_episodes'.tr(),
                      ),
                      _Stat(
                        value: stats?.hours,
                        label: 'trakt.stat_hours'.tr(),
                      ),
                      _Stat(
                        value: stats?.ratings,
                        label: 'trakt.stat_ratings'.tr(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final int? value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Text(
              value == null ? '–' : compactCount(value!),
              key: ValueKey(value),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}

// ─── shared tab scaffolding ─────────────────────────────────────────────────

/// Loading, failure and emptiness for a tab, in one place; [builder] gets
/// the rest.
Widget _sectionBody(
  List<TraktSection> sections, {
  required String empty,
  required Future<void> Function() onRefresh,
  required Widget Function() builder,
}) {
  final loading = sections.any((s) => s.loading);
  final loaded = sections.any((s) => s.loaded);
  final hasItems = sections.any((s) => s.items.isNotEmpty);
  if (!hasItems &&
      (loading || !loaded) &&
      sections.every((s) => s.error == null)) {
    return const Center(
      child: CircularProgressIndicator(strokeWidth: 2, color: kTraktRed),
    );
  }
  final error = sections.map((s) => s.error).whereType<String>().firstOrNull;
  if (!hasItems && error != null) {
    return AnilistScrollableMessage(
      message: AnilistStateMessage(
        icon: Icons.cloud_off_rounded,
        text: error,
        actionLabel: 'anilist.retry'.tr(),
        onAction: onRefresh,
        accent: kTraktRed,
      ),
    );
  }
  if (!hasItems) {
    return RefreshIndicator(
      color: kTraktRed,
      onRefresh: onRefresh,
      child: AnilistScrollableMessage(
        message: AnilistStateMessage(
          icon: Icons.inbox_rounded,
          text: empty,
          accent: kTraktRed,
        ),
      ),
    );
  }
  return RefreshIndicator(
    color: kTraktRed,
    backgroundColor: AppColors.surface,
    onRefresh: onRefresh,
    child: builder(),
  );
}

SliverGridDelegate get _posterGrid =>
    const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 132,
      mainAxisSpacing: 14,
      crossAxisSpacing: 12,
      childAspectRatio: 0.52,
    );

void _toast(BuildContext context, String? error, String done) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(error ?? done), behavior: SnackBarBehavior.floating),
  );
}

// ─── Up next ────────────────────────────────────────────────────────────────

class _UpNextTab extends StatelessWidget {
  const _UpNextTab({required this.hub, required this.onRefresh});

  final TraktHubController hub;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return _sectionBody(
      [hub.playback, hub.upNext],
      empty: 'trakt.all_caught_up'.tr(),
      onRefresh: onRefresh,
      builder: () => CustomScrollView(
        slivers: [
          if (hub.playback.items.isNotEmpty) ...[
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              sliver: SliverToBoxAdapter(
                child: TraktSectionHeader('trakt.continue_watching'.tr()),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 196,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  scrollDirection: Axis.horizontal,
                  itemCount: hub.playback.items.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, i) {
                    final e = hub.playback.items[i];
                    return TraktPlaybackCard(
                      entry: e,
                      onTap: () => openTraktTitle(context, e.media),
                      onRemove: () async {
                        final err = await hub.removePlayback(e);
                        if (context.mounted) {
                          _toast(context, err, 'trakt.removed'.tr());
                        }
                      },
                    );
                  },
                ),
              ),
            ),
          ],
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            sliver: SliverToBoxAdapter(
              child: TraktSectionHeader(
                'trakt.next_up'.tr(),
                trailing: hub.upNext.loading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: kTraktRed,
                        ),
                      )
                    : null,
              ),
            ),
          ),
          if (hub.upNext.loaded && hub.upNext.items.isEmpty)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverToBoxAdapter(
                child: Text(
                  'trakt.all_caught_up'.tr(),
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 28),
            sliver: SliverList.separated(
              itemCount: hub.upNext.items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final e = hub.upNext.items[i];
                final busy = hub.busy.contains(e.media.traktId);
                return TraktEntryRow(
                  entry: e,
                  showProgress: true,
                  caption: 'trakt.episodes_progress'.tr(
                    args: ['${e.completed ?? 0}', '${e.aired ?? 0}'],
                  ),
                  onTap: () =>
                      TraktItemSheet.show(context, entry: e, controller: hub),
                  trailing: busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: kTraktRed,
                          ),
                        )
                      : IconButton(
                          tooltip: 'trakt.action_mark_next'.tr(
                            args: [e.episode?.code ?? ''],
                          ),
                          onPressed: () async {
                            final err = await hub.markWatched(e);
                            if (context.mounted) {
                              _toast(context, err, 'trakt.marked'.tr());
                            }
                          },
                          icon: const Icon(
                            Icons.check_circle_outline_rounded,
                            color: kTraktRed,
                            size: 26,
                          ),
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Watchlist ──────────────────────────────────────────────────────────────

enum _Kind { all, movies, shows }

class _KindFilter extends StatelessWidget {
  const _KindFilter({required this.value, required this.onChanged});

  final _Kind value;
  final ValueChanged<_Kind> onChanged;

  @override
  Widget build(BuildContext context) {
    String label(_Kind k) => switch (k) {
      _Kind.all => 'trakt.filter_all'.tr(),
      _Kind.movies => 'trakt.filter_movies'.tr(),
      _Kind.shows => 'trakt.filter_shows'.tr(),
    };
    return Wrap(
      spacing: 8,
      children: [
        for (final k in _Kind.values)
          ChoiceChip(
            label: Text(label(k)),
            selected: value == k,
            onSelected: (_) => onChanged(k),
            showCheckmark: false,
            selectedColor: kTraktRed.withValues(alpha: 0.22),
            backgroundColor: AppColors.surface,
            side: BorderSide(
              color: value == k ? kTraktRed : AppColors.border,
              width: 0.8,
            ),
            labelStyle: TextStyle(
              color: value == k
                  ? AppColors.textPrimary
                  : AppColors.textSecondary,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
      ],
    );
  }
}

bool _matches(_Kind k, TraktEntry e) => switch (k) {
  _Kind.all => true,
  _Kind.movies => e.isMovie,
  _Kind.shows => !e.isMovie,
};

class _WatchlistTab extends StatefulWidget {
  const _WatchlistTab({required this.hub, required this.onRefresh});

  final TraktHubController hub;
  final Future<void> Function() onRefresh;

  @override
  State<_WatchlistTab> createState() => _WatchlistTabState();
}

class _WatchlistTabState extends State<_WatchlistTab> {
  _Kind _kind = _Kind.all;

  @override
  Widget build(BuildContext context) {
    final hub = widget.hub;
    final items = [
      for (final e in hub.watchlist.items)
        if (_matches(_kind, e)) e,
    ];
    return _sectionBody(
      [hub.watchlist],
      empty: 'trakt.empty_watchlist'.tr(),
      onRefresh: widget.onRefresh,
      builder: () => CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            sliver: SliverToBoxAdapter(
              child: _KindFilter(
                value: _kind,
                onChanged: (k) => setState(() => _kind = k),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 28),
            sliver: SliverGrid.builder(
              gridDelegate: _posterGrid,
              itemCount: items.length,
              itemBuilder: (context, i) {
                final e = items[i];
                return TraktPosterTile(
                  entry: e,
                  busy: hub.busy.contains(e.media.traktId),
                  badge: e.media.rating != null && e.media.rating! > 0
                      ? TraktBadge(
                          label: e.media.rating!.toStringAsFixed(1),
                          icon: Icons.star_rounded,
                          color: AppColors.rating,
                        )
                      : null,
                  onTap: () => openTraktTitle(context, e.media),
                  onLongPress: () => TraktItemSheet.show(
                    context,
                    entry: e,
                    controller: hub,
                    inWatchlist: true,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── History ────────────────────────────────────────────────────────────────

class _HistoryTab extends StatelessWidget {
  const _HistoryTab({required this.hub, required this.onRefresh});

  final TraktHubController hub;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final items = hub.history.items;
    return _sectionBody(
      [hub.history],
      empty: 'trakt.empty_history'.tr(),
      onRefresh: onRefresh,
      builder: () => NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.pixels > n.metrics.maxScrollExtent - 600) {
            hub.loadMoreHistory();
          }
          return false;
        },
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 28),
          itemCount: items.length + (hub.history.more ? 1 : 0),
          itemBuilder: (context, i) {
            if (i == items.length) {
              return const Padding(
                padding: EdgeInsets.all(18),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: kTraktRed,
                    ),
                  ),
                ),
              );
            }
            final e = items[i];
            final at = e.at;
            final prev = i == 0 ? null : items[i - 1].at;
            final newDay =
                at != null &&
                (prev == null ||
                    prev.year != at.year ||
                    prev.month != at.month ||
                    prev.day != at.day);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (newDay) TraktSectionHeader(dayLabel(context, at)),
                if (!newDay) const SizedBox(height: 10),
                TraktEntryRow(
                  entry: e,
                  caption: at == null ? null : clock(context, at),
                  onTap: () => TraktItemSheet.show(
                    context,
                    entry: e,
                    controller: hub,
                    extraActions: [
                      TraktSheetAction(
                        icon: Icons.history_toggle_off_rounded,
                        label: 'trakt.action_remove_history'.tr(),
                        destructive: true,
                        run: () => hub.removeHistory(e),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ─── Calendar ───────────────────────────────────────────────────────────────

class _CalendarTab extends StatelessWidget {
  const _CalendarTab({required this.hub, required this.onRefresh});

  final TraktHubController hub;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final items = hub.calendar.items;
    return _sectionBody(
      [hub.calendar],
      empty: 'trakt.empty_calendar'.tr(),
      onRefresh: onRefresh,
      builder: () => ListView.builder(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 28),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final e = items[i];
          final at = e.at;
          final prev = i == 0 ? null : items[i - 1].at;
          final newDay =
              at != null &&
              (prev == null ||
                  prev.year != at.year ||
                  prev.month != at.month ||
                  prev.day != at.day);
          final premiere = e.episode?.number == 1;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (newDay) TraktSectionHeader(dayLabel(context, at)),
              if (!newDay) const SizedBox(height: 10),
              TraktEntryRow(
                entry: e,
                caption: at == null
                    ? null
                    : [
                        clock(context, at),
                        if (e.media.network != null) e.media.network!,
                      ].join(' · '),
                trailing: premiere
                    ? AnilistChip(
                        label: e.episode!.season == 1
                            ? 'trakt.series_premiere'.tr()
                            : 'trakt.season_premiere'.tr(),
                        color: kTraktRed,
                        filled: true,
                      )
                    : null,
                onTap: () =>
                    TraktItemSheet.show(context, entry: e, controller: hub),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─── For you / Trending ─────────────────────────────────────────────────────

class _PosterPairTab extends StatefulWidget {
  const _PosterPairTab({
    required this.hub,
    required this.movies,
    required this.shows,
    required this.onRefresh,
    required this.empty,
    this.recommendations = false,
  });

  final TraktHubController hub;
  final TraktSection movies;
  final TraktSection shows;
  final Future<void> Function() onRefresh;
  final String empty;
  final bool recommendations;

  @override
  State<_PosterPairTab> createState() => _PosterPairTabState();
}

class _PosterPairTabState extends State<_PosterPairTab> {
  _Kind _kind = _Kind.movies;

  @override
  Widget build(BuildContext context) {
    final hub = widget.hub;
    final items = switch (_kind) {
      _Kind.movies => widget.movies.items,
      _Kind.shows => widget.shows.items,
      _Kind.all => [...widget.movies.items, ...widget.shows.items],
    };
    return _sectionBody(
      [widget.movies, widget.shows],
      empty: widget.empty,
      onRefresh: widget.onRefresh,
      builder: () => CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            sliver: SliverToBoxAdapter(
              child: _KindFilter(
                value: _kind,
                onChanged: (k) => setState(() => _kind = k),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 28),
            sliver: SliverGrid.builder(
              gridDelegate: _posterGrid,
              itemCount: items.length,
              itemBuilder: (context, i) {
                final e = items[i];
                return TraktPosterTile(
                  entry: e,
                  busy: hub.busy.contains(e.media.traktId),
                  badge: e.media.rating != null && e.media.rating! > 0
                      ? TraktBadge(
                          label: e.media.rating!.toStringAsFixed(1),
                          icon: Icons.star_rounded,
                          color: AppColors.rating,
                        )
                      : null,
                  onTap: () => openTraktTitle(context, e.media),
                  onLongPress: () => TraktItemSheet.show(
                    context,
                    entry: e,
                    controller: hub,
                    inWatchlist: widget.recommendations ? false : null,
                    extraActions: [
                      if (widget.recommendations)
                        TraktSheetAction(
                          icon: Icons.visibility_off_outlined,
                          label: 'trakt.action_not_interested'.tr(),
                          destructive: true,
                          run: () => hub.hideRecommendation(e.media),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Ratings ────────────────────────────────────────────────────────────────

class _RatingsTab extends StatefulWidget {
  const _RatingsTab({required this.hub, required this.onRefresh});

  final TraktHubController hub;
  final Future<void> Function() onRefresh;

  @override
  State<_RatingsTab> createState() => _RatingsTabState();
}

class _RatingsTabState extends State<_RatingsTab> {
  _Kind _kind = _Kind.all;

  @override
  Widget build(BuildContext context) {
    final hub = widget.hub;
    final items = [
      for (final e in hub.ratings.items)
        if (_matches(_kind, e)) e,
    ];
    final dist = hub.stats?.distribution ?? const <int, int>{};
    final peak = dist.values.fold<int>(0, (a, b) => a > b ? a : b);
    return _sectionBody(
      [hub.ratings],
      empty: 'trakt.empty_ratings'.tr(),
      onRefresh: widget.onRefresh,
      builder: () => CustomScrollView(
        slivers: [
          if (peak > 0)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              sliver: SliverToBoxAdapter(
                child: _Distribution(dist: dist, peak: peak),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            sliver: SliverToBoxAdapter(
              child: _KindFilter(
                value: _kind,
                onChanged: (k) => setState(() => _kind = k),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 28),
            sliver: SliverGrid.builder(
              gridDelegate: _posterGrid,
              itemCount: items.length,
              itemBuilder: (context, i) {
                final e = items[i];
                return TraktPosterTile(
                  entry: e,
                  busy: hub.busy.contains(e.media.traktId),
                  badge: TraktBadge(
                    label: '${e.rating ?? '–'}',
                    icon: Icons.favorite_rounded,
                    color: kTraktRed,
                  ),
                  onTap: () => openTraktTitle(context, e.media),
                  onLongPress: () =>
                      TraktItemSheet.show(context, entry: e, controller: hub),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// How the viewer's scores spread over 1..10.
class _Distribution extends StatelessWidget {
  const _Distribution({required this.dist, required this.peak});

  final Map<int, int> dist;
  final int peak;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: SizedBox(
        height: 92,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var s = 1; s <= 10; s++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: (dist[s] ?? 0) / peak),
                        duration: const Duration(milliseconds: 500),
                        curve: Curves.easeOutCubic,
                        builder: (_, v, _) => Container(
                          height: 4 + 58 * v,
                          decoration: BoxDecoration(
                            color: kTraktRed.withValues(alpha: 0.35 + 0.65 * v),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$s',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
