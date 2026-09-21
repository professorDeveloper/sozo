import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:soplay/core/content/catalogue.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/tv/tv.dart';
import 'package:soplay/core/widgets/item_appear.dart';
import 'package:soplay/features/detail/domain/entities/detail_args.dart';
import 'package:soplay/features/home/domain/entities/home_section_entity.dart';
import 'package:soplay/features/home/domain/entities/movie.dart';
import 'package:soplay/features/home/presentation/bloc/home/home_bloc.dart';
import 'package:soplay/features/home/presentation/bloc/home/home_state.dart';
import 'package:soplay/features/home/presentation/widgets/home_shared_widgets.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_bloc.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_state.dart';
import 'package:soplay/features/search/domain/entities/genre_entity.dart';
import 'package:soplay/features/search/presentation/widgets/genre_tile.dart';
import 'package:soplay/features/search/presentation/widgets/search_result_card.dart';

/// What the search tab shows before a word is typed.
///
/// It used to be a magnifying glass and a hint, then a row of genre names once
/// the provider had any. Now it is somewhere to start from: what was searched
/// last, what is trending on the source in use, and the genres as a grid of
/// covers — the three ways somebody who has not decided yet finds something.
///
/// Slivers rather than one widget, and the difference is the genre grid. As a
/// `shrinkWrap` GridView inside a single box adapter it was laid out in full on
/// the first frame: every tile built, every cover requested, and two dozen
/// entrance animations played out below the fold where nobody saw them — all
/// before the tab had drawn once. A real [SliverGrid] builds the rows the
/// viewport asks for and nothing else, so the covers download as they are
/// scrolled to and the stagger runs where it can be seen.
List<Widget> searchLandingSlivers(
  BuildContext context, {
  required List<String> recent,
  required List<GenreEntity> genres,
  required bool genresLoading,
  required bool genresFailed,
  required ValueChanged<String> onSuggestion,
  required ValueChanged<String> onGenre,
  required ValueChanged<String> onRemoveRecent,
  required VoidCallback onClearRecents,
  required VoidCallback onRetryGenres,
}) {
  final width = MediaQuery.sizeOf(context).width;
  final columns = width >= 900 ? 4 : (width >= 600 ? 3 : 2);

  return [
    if (recent.isNotEmpty)
      SliverToBoxAdapter(
        child: _RecentSearches(
          recent: recent,
          onSuggestion: onSuggestion,
          onRemoveRecent: onRemoveRecent,
          onClearRecents: onClearRecents,
        ),
      ),
    const SliverToBoxAdapter(child: _SourceRail()),
    // The way in to the streaming services.
    //
    // They had none. The page and its browse screen were built, routed and
    // translated, and then the rail that used to reach them came off Home —
    // correctly, because a rail is not where a whole catalogue belongs — and
    // nothing replaced it. A feature no screen links to is a feature that has
    // been removed.
    //
    // Here rather than on Home because of what it answers: "where can I watch
    // this" is a search, not a shelf. It is one row and it fetches nothing —
    // the services and the region load when the page opens, not when the
    // search tab does.
    const SliverToBoxAdapter(child: _StreamingServicesEntry()),
    if (genres.isNotEmpty) ...[
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: _SectionTitle('search.categories'.tr()),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverGrid(
          gridDelegate: genreGridDelegate(columns),
          delegate: SliverChildBuilderDelegate((context, i) {
            final g = genres[i];
            return ItemAppear(
              index: i,
              columns: columns + 1,
              staggerLimit: 24,
              child: GenreTile(
                label: g.name.isNotEmpty ? g.name : g.slug,
                image: g.image,
                index: i,
                onTap: () {
                  // A genre tile replaces the whole screen with a browse of
                  // that genre, which is as much of a departure as opening a
                  // title — and the tile's ink alone does not say so.
                  HapticFeedback.selectionClick();
                  onGenre(g.slug);
                },
              ),
            );
          }, childCount: genres.length),
        ),
      ),
    ] else if (genresLoading)
      // The same heading and the same grid, greyed out.
      //
      // It used to be two columns at 1.85 with ten points of spacing and no
      // heading, against three columns at 1.5 with eight and a heading — so
      // the moment the genres landed the section changed column count, tile
      // shape and height at once, and everything above it that the reader had
      // started on moved. A skeleton is only worth having if what replaces it
      // lands in the same place.
      // One sweep across the heading and the tiles together, rather than one
      // per tile on its own clock — see [SearchCardSkeleton]'s grid.
      SliverToBoxAdapter(
        child: ShimmerWrapper(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                child: SizedBox(
                  height: _sectionTitleHeight(context),
                  child: const Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: HomeSkeletonBox(width: 96, height: 14, radius: 4),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  gridDelegate: genreGridDelegate(columns),
                  itemCount: (columns + 1) * 3,
                  itemBuilder: (_, _) => const HomeSkeletonBox(
                    width: double.infinity,
                    height: double.infinity,
                    radius: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      )
    else if (genresFailed)
      // The state that had nowhere to go. `genresFailed` was computed and put
      // on the state and then read by nothing at all, so a failed genre call
      // simply removed the Categories section: on a device with recents the
      // only way to browse this source vanished, with no reason given and no
      // way to ask again.
      SliverToBoxAdapter(child: _GenresUnavailable(onRetry: onRetryGenres))
    else if (recent.isEmpty)
      // Nothing to start from at all: the old empty state, kept for the
      // source that offers neither genres nor a home.
      const SliverToBoxAdapter(child: _NothingToStartFrom()),
  ];
}

/// The genre grid's shape, used by the grid and by the skeleton that stands in
/// for it.
///
/// One more column than the posters use, and a shorter tile. At two columns and
/// 1.85 each genre was a landscape card the size of a small poster, and a
/// source with forty-one genres filled several screens with them — a browsing
/// aid taking more room than the thing it helps you browse. Three across at 1.5
/// keeps the artwork legible while the whole set fits in a screen and a half.
///
/// Shared rather than written twice because it was written twice, with
/// different numbers, and the difference was a layout jump.
SliverGridDelegate genreGridDelegate(int columns) =>
    SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columns + 1,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.5,
    );

/// The height one [_SectionTitle] occupies, so a skeleton standing in for a
/// heading reserves exactly the line the heading will take — at whatever text
/// size the reader has chosen, which is the part a hard-coded number misses.
double _sectionTitleHeight(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(18) * 1.15;

/// One row, into the streaming services.
///
/// Built out of the same parts as the rest of this screen — a section title in
/// the same weight, a surface card, the app's own press feedback — so it reads
/// as another place to start rather than as an advertisement for a feature.
class _StreamingServicesEntry extends StatelessWidget {
  const _StreamingServicesEntry();

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              Icons.subscriptions_rounded,
              size: 20,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'watch.services_title'.tr(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'watch.services_entry_hint'.tr(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textHint,
                    fontSize: 11.5,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          const Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: AppColors.textHint,
          ),
        ],
      ),
    );

    void open() => context.push('/watch-services');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: isTvPlatform
          ? TvFocusable(onPressed: open, borderRadius: 14, child: card)
          : HoverTap(
              onTap: open,
              borderRadius: 14,
              scale: 1.01,
              haptic: true,
              child: card,
            ),
    );
  }
}

class _RecentSearches extends StatelessWidget {
  const _RecentSearches({
    required this.recent,
    required this.onSuggestion,
    required this.onRemoveRecent,
    required this.onClearRecents,
  });

  final List<String> recent;
  final ValueChanged<String> onSuggestion;
  final ValueChanged<String> onRemoveRecent;
  final VoidCallback onClearRecents;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Row(
            children: [
              Expanded(child: _SectionTitle('search.recent'.tr())),
              _TextAction(
                label: 'search.clear_filter'.tr(),
                onTap: onClearRecents,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final q in recent)
                _Chip(
                  label: q,
                  icon: Icons.history_rounded,
                  onTap: () => onSuggestion(q),
                  onRemove: () => onRemoveRecent(q),
                ),
            ],
          ),
        ),
        const SizedBox(height: 22),
      ],
    );
  }
}

/// The last resort: a source with no genres, no rail and nothing searched
/// before.
///
/// It checks the rail itself rather than trusting the caller, because the
/// caller cannot see one: the rail is decided inside a [BlocBuilder] on the
/// home, so "neither genres nor a home" — which is what this branch has always
/// claimed to mean — used to be only half tested. A source with no genres and
/// no history but a perfectly good home drew a screenful of posters and then,
/// underneath them, a large magnifying glass saying there was nothing here.
///
/// The sentence is its own, where it used to be the search field's
/// placeholder. Borrowed up here that placeholder told you to search in a box
/// you were already looking at, and it offered films and series on a manga
/// source.
/// The shape of the shelf that is coming, while the home is still answering.
///
/// A heading bar and a row of posters at the sizes the real rail uses, so the
/// screen does not jump when the answer arrives.
class _RailSkeleton extends StatelessWidget {
  const _RailSkeleton();

  @override
  Widget build(BuildContext context) {
    // Every number here is the loaded rail's number, not an approximation of
    // it: same top padding, same heading line, same gap, same card width, same
    // card height, same trailing gap. A skeleton that is close but not equal is
    // a layout jump with a shimmer in front of it — 112-wide cards 168 tall
    // under a 13-point line stood in for 118-wide cards whose height is
    // computed from the caption, and the genre grid below moved by the
    // difference the moment the posters arrived.
    return ShimmerWrapper(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 2),
            child: SizedBox(
              height: _sectionTitleHeight(context),
              child: const Align(
                alignment: AlignmentDirectional.centerStart,
                child: HomeSkeletonBox(width: 148, height: 14, radius: 4),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: searchCardHeight(_railCardWidth, context),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: 5,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, _) => const HomeSkeletonBox(
                width: _railCardWidth,
                height: double.infinity,
                radius: 10,
              ),
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _NothingToStartFrom extends StatelessWidget {
  const _NothingToStartFrom();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<HomeBloc, HomeState>(
      builder: (context, state) {
        // While the home is still in flight, nothing here.
        //
        // This message is a claim about what the source HAS, and until the
        // home answers the app does not know: saying it on `HomeLoading` put
        // "nothing to browse" on screen for as long as the source took, then
        // replaced it with a shelf of posters — the app calling itself a liar
        // a second later. The waiting is shown by [_SourceRail]'s skeleton,
        // which sits directly above this and now draws during the load, so a
        // second skeleton here would be the same wait reported twice.
        if (state is! HomeLoaded) return const SizedBox.shrink();
        if (searchRailSection(state.homeData.sections) != null) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(top: 60),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.search_rounded,
                  color: AppColors.textHint.withValues(alpha: 0.45),
                  size: 68,
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    'search.nothing_to_browse'.tr(),
                    style: const TextStyle(
                      color: AppColors.textHint,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Whether a home rail is the source's popularity row.
///
/// The key is the half a source writes for machines and the label is the half
/// it writes for people, and neither is reliable alone: some sources key the
/// row `home` and only the name "Trending now" says what it is, others name it
/// in a language this check cannot read and only the key `trending` does. Both
/// are read, and a miss costs nothing worse than the generic heading.
bool _readsAsPopular(String key, String label) {
  final signal = '$key $label'.toLowerCase();
  return signal.contains('trend') || signal.contains('popular');
}

/// The home rail the search tab borrows, or null when the home has none worth
/// borrowing.
///
/// Four items is the floor because this is a poster row: three covers and a
/// gap read as a shelf that failed to load rather than as a suggestion. What
/// everyone is watching wins over what this viewer saved — the personal rails
/// a home can lead with are the search tab's least useful answer to "what
/// should I look for".
HomeSectionEntity? searchRailSection(List<HomeSectionEntity> sections) {
  final shelves = sections.where((s) => s.items.length >= 4).toList();
  bool personal(String k) =>
      k.contains('list') ||
      k.contains('continue') ||
      k.contains('history') ||
      k.contains('recent');
  return shelves.where((s) => _readsAsPopular(s.key, s.label)).firstOrNull ??
      shelves.where((s) => !personal(s.key.toLowerCase())).firstOrNull;
}

/// The heading over [searchRailSection]'s posters.
///
/// What a source calls this row is the source's own business, and for one of
/// them the answer is "Homepage" — which on the search tab reads as a section
/// named after a page, and on the next source along reads as something else
/// entirely. So the row's name is never shown here. It is only ever read, by
/// [_readsAsPopular], as evidence about what the row holds, and the heading
/// itself is the app's own sentence.
///
/// That sentence names [source], because which source the next search will go
/// to is the most useful fact on this screen and it is the one the old heading
/// got right — except for plain sources, which it left unnamed altogether.
/// When even the name is unknown the heading says what the shelf is for
/// instead, since a nameless shelf is worse than a general one.
String searchRailHeading({
  required String railKey,
  required String railLabel,
  required String source,
}) {
  if (source.isEmpty) return 'search.rail_no_source'.tr();
  final key = _readsAsPopular(railKey, railLabel)
      ? 'search.rail_popular_on'
      : 'search.rail_browse_on';
  return key.tr(namedArgs: {'source': source});
}

/// A shelf from the source that is about to be searched, so the search tab is
/// not a blank page waiting for a word. Nothing while Home is still loading or
/// has failed: a shelf of its own would be a second request for the same list.
class _SourceRail extends StatelessWidget {
  const _SourceRail();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<HomeBloc, HomeState>(
      // Any change of state changes this section's shape — including the one
      // the old condition could not see. `a is HomeLoaded != b is HomeLoaded`
      // is false for HomeLoading -> HomeError, so a home that failed left the
      // skeleton below shimmering for the rest of the session.
      buildWhen: (a, b) => a.runtimeType != b.runtimeType || b is HomeLoaded,
      builder: (context, state) {
        // A shape while the home is in flight, nothing once it has failed.
        //
        // Returning nothing during the load was the search tab's first of two
        // jumps: the landing drew with no rail in it, the reader started
        // reading the genres, and a second later a shelf of posters opened
        // above them and pushed everything down a quarter of a screen. The
        // skeleton reserves that space, so the posters arrive into it.
        if (state is HomeError) return const SizedBox.shrink();
        if (state is! HomeLoaded) return const _RailSkeleton();
        final rail = searchRailSection(state.homeData.sections);
        if (rail == null) return const SizedBox.shrink();
        final items = rail.items.take(15).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 2),
              child: _RailHeading(
                rail: rail,
                // The provider the posters came from, not the one that is
                // current: during a source switch the two disagree for as long
                // as the new home takes to arrive, and naming the incoming
                // source over the outgoing source's posters is a lie the user
                // can see.
                providerId: state.homeData.provider,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              // Measured, not guessed. A flat 214 was some nine points short of
              // what a 118-wide card actually needs, and the caption under a
              // poster is the inflexible part of that card — so the shortfall
              // came out of the POSTER, which stopped being a 2:3 rectangle and
              // cropped further into the artwork at every text size above the
              // default. [searchCardHeight] is the card's own arithmetic.
              height: searchCardHeight(_railCardWidth, context),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, i) {
                  final movie = items[i];
                  return ItemAppear(
                    index: i,
                    axis: Axis.horizontal,
                    child: SearchResultCard(
                      movie: movie,
                      width: _railCardWidth,
                      provider: movie.provider.isEmpty ? null : movie.provider,
                      onTap: () => _open(context, movie),
                    ),
                  );
                },
              ),
            ),
            // No trailing gap: the next heading's own top padding is the
            // space between them. Both had one, and the two stacked into a
            // band of empty screen wide enough to read as a missing section.
            const SizedBox(height: 4),
          ],
        );
      },
    );
  }

  void _open(BuildContext context, MovieEntity movie) {
    if (movie.url.isEmpty) return;
    context.push(
      '/detail',
      extra: DetailArgs(
        contentUrl: movie.url,
        preview: movie,
        provider: movie.provider.isEmpty ? null : movie.provider,
      ),
    );
  }
}

/// Poster width in the rail. Named because the row's height is derived from it.
const double _railCardWidth = 118;

/// Separated from the rail so that the provider list — which the source's name
/// has to be looked up in, and which reloads on its own schedule — is listened
/// to by one line of text rather than by fifteen posters.
class _RailHeading extends StatelessWidget {
  const _RailHeading({required this.rail, required this.providerId});

  final HomeSectionEntity rail;
  final String providerId;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProviderBloc, ProviderState>(
      builder: (context, state) => _SectionTitle(
        searchRailHeading(
          railKey: rail.key,
          railLabel: rail.label,
          source: _sourceName(state),
        ),
      ),
    );
  }

  /// A catalogue answers for itself; everything else has to be found in the
  /// installed list, and until that list has loaded there is no name to give.
  String _sourceName(ProviderState state) {
    final catalogue = Catalogue.fromId(providerId);
    if (catalogue != null) return catalogue.labelKey.tr();
    if (state is! ProviderLoaded) return '';
    return state.providers.where((p) => p.id == providerId).firstOrNull?.name ??
        '';
  }
}

/// A row heading.
///
/// White and full size, not an 11pt letter-spaced grey caption. The old style
/// is what a form uses to label a field — it sat *above* the content and read
/// as metadata about it. On a browsing screen the heading is part of the
/// content: it is what tells you what the row of artwork under it IS, and at
/// 11pt in [AppColors.textHint] it was the quietest thing on a screen of
/// posters. Sentence case for the same reason — SHOUTED SMALL CAPS is a label,
/// a sentence is a name.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(
      color: AppColors.textPrimary,
      fontSize: 18,
      fontWeight: FontWeight.w800,
      height: 1.15,
      // Slightly tight, which is what stops a large weight reading as shouting.
      letterSpacing: -0.3,
    ),
  );
}

class _TextAction extends StatelessWidget {
  const _TextAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    if (isTvPlatform) {
      return TvFocusable(onPressed: onTap, borderRadius: 8, child: child);
    }
    return GestureDetector(onTap: onTap, child: child);
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.onTap,
    this.icon,
    this.onRemove,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final remove = onRemove;

    final text = Padding(
      // No vertical padding where there is a remove button: the 44dp box
      // beside it is what sets the chip's height in that case, and adding to
      // it would only make the chip taller than the target it exists to hold.
      padding: EdgeInsetsDirectional.fromSTEB(
        12,
        remove == null ? 8 : 0,
        remove == null ? 12 : 0,
        remove == null ? 8 : 0,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: AppColors.textSecondary),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );

    // The decoration stays on the Container and the ink goes on a transparent
    // Material above it, so the splash paints over the fill instead of being
    // hidden under it.
    final chip = Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Material(
        color: Colors.transparent,
        // InkWell rather than a bare GestureDetector, which is what this was:
        // the gesture showed nothing on press and announced nothing at all,
        // while the chip is a button that runs a search. The InkWell is both
        // the press feedback and the `button: true` that says so.
        child: InkWell(
          onTap: isTvPlatform ? null : onTap,
          borderRadius: BorderRadius.circular(10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: text),
              if (remove != null) _ChipRemove(query: label, onTap: remove),
            ],
          ),
        ),
      ),
    );

    if (isTvPlatform) {
      return TvFocusable(onPressed: onTap, borderRadius: 10, child: chip);
    }
    return chip;
  }
}

/// The × on a recent-search chip.
///
/// It was a 15px icon in 2px of padding — a 19dp target, sitting 6dp from the
/// chip's own tap area — so the common outcome of aiming at it was running the
/// search you were trying to forget. The box is 44dp square now and the icon
/// inside it is the same 15px it always was; only the reachable area grew, out
/// into padding the chip was already spending.
class _ChipRemove extends StatelessWidget {
  const _ChipRemove({required this.query, required this.onTap});

  final String query;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Merged so the label and the button land on one node rather than on a
    // Semantics wrapper with an unlabelled InkResponse nested inside it.
    return MergeSemantics(
      child: Semantics(
        button: true,
        // Which query this forgets. Every chip in the row otherwise announces
        // an identical unlabelled button, which is no help to anyone
        // navigating by screen reader.
        label: '${'general.remove'.tr()} $query',
        child: InkResponse(
          onTap: () {
            // Destructive and unconfirmed: the entry is gone the moment this
            // lands, so the tap is worth feeling.
            HapticFeedback.selectionClick();
            onTap();
          },
          radius: 22,
          child: const SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              Icons.close_rounded,
              size: 15,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Says the genre list did not load, and offers to try again.
///
/// Deliberately small. This is one section of an idle screen that still has
/// recents and a source rail on it, so a full-page error would be wrong; but
/// the section disappearing without a word was worse, because browsing is the
/// only thing this screen is for when you have nothing to type.
class _GenresUnavailable extends StatelessWidget {
  const _GenresUnavailable({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          const Icon(
            Icons.category_outlined,
            size: 18,
            color: AppColors.textHint,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'search.categories_failed'.tr(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textHint, fontSize: 12.5),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'general.retry'.tr(),
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
