import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/widgets/item_appear.dart';
import 'package:soplay/core/tv/tv.dart';
import 'package:soplay/features/detail/domain/entities/detail_args.dart';
import 'package:soplay/features/home/domain/entities/movie.dart';
import 'package:soplay/features/home/presentation/widgets/home_shared_widgets.dart';
import 'package:soplay/features/search/presentation/blocs/search_bloc.dart';
import 'package:soplay/features/search/presentation/widgets/search_landing.dart';
import 'package:soplay/features/search/presentation/widgets/search_result_card.dart';
import 'package:soplay/features/sources/domain/source_failure.dart';
import 'package:soplay/features/support/presentation/widgets/support_suggestion.dart';
import 'package:soplay/features/support/data/support_models.dart';

class SearchContentView extends StatelessWidget {
  const SearchContentView({
    super.key,
    required this.state,
    required this.scrollController,
    required this.topPad,
    required this.bottomPad,
    required this.onRetry,
    required this.onRetryMore,
    required this.onRefresh,
    required this.onSuggestion,
    required this.onGenre,
    required this.onRemoveRecent,
    required this.onClearRecents,
    required this.onTryAllSources,
    this.onSearchTorrents,
  });

  final SearchState state;
  final ScrollController scrollController;
  final double topPad;
  final double bottomPad;
  final VoidCallback onRetry;

  /// Asks for the next page again after one failed. Separate from [onRetry]:
  /// that re-runs the whole search from page one and would throw away every
  /// row the reader has already scrolled past.
  final VoidCallback onRetryMore;

  /// Runs the same search again and completes when it has landed. The
  /// indicator holds its spinner for as long as this future does, so it has to
  /// outlive the dispatch rather than returning the moment the event is added.
  final Future<void> Function() onRefresh;

  final ValueChanged<String> onSuggestion;
  final ValueChanged<String> onGenre;
  final ValueChanged<String> onRemoveRecent;
  final VoidCallback onClearRecents;
  final VoidCallback onTryAllSources;

  /// Sends the current query to the torrent search. Null where torrents are
  /// unavailable (iOS, desktop), so the option is simply absent rather than
  /// present and failing.
  final VoidCallback? onSearchTorrents;

  @override
  Widget build(BuildContext context) {
    // Pull to refresh, with Home's exact colours, offsets and stroke. Nineteen
    // feature screens already answer the gesture and search — the tab people
    // pull on hardest, because it is the one showing a source that may simply
    // have been having a bad minute — was not one of them. Matching Home's
    // numbers rather than the Material defaults is the point: the two tabs are
    // one swipe apart and a differently placed spinner reads as a different
    // app.
    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: AppColors.surface,
      edgeOffset: topPad + 10,
      displacement: topPad + 10,
      strokeWidth: 2.6,
      onRefresh: onRefresh,
      child: CustomScrollView(
        controller: scrollController,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        // A short result set has nothing to overscroll, and RefreshIndicator
        // only sees the gesture on a scrollable that lets it start.
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: topPad)),
          if (state.status == SearchStatus.refreshing)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 2,
                child: LinearProgressIndicator(
                  minHeight: 2,
                  color: AppColors.primary,
                  backgroundColor: Colors.transparent,
                ),
              ),
            ),
          ..._body(context),
          SliverToBoxAdapter(child: SizedBox(height: bottomPad + 90)),
        ],
      ),
    );
  }

  List<Widget> _body(BuildContext context) {
    switch (state.status) {
      case SearchStatus.loading:
        return [const _SearchSkeletonGrid()];
      case SearchStatus.error:
        // A failure with results already on screen is a banner, not a takeover.
        // One flaky response while somebody is still typing used to replace a
        // perfectly good grid with a full-page error.
        if (state.items.isNotEmpty) {
          return [
            SliverToBoxAdapter(
              child: _SearchErrorBanner(
                message: state.failure?.headline ?? '',
                onRetry: onRetry,
              ),
            ),
            SearchResultsGrid(items: state.items),
          ];
        }
        return [
          SliverFillRemaining(
            hasScrollBody: false,
            child: _SearchErrorView(failure: state.failure, onRetry: onRetry),
          ),
        ];
      case SearchStatus.empty:
        return [
          SliverFillRemaining(
            hasScrollBody: false,
            child: _SearchEmptyView(
              criteria: state.criteria,
              label: state.criteriaLabel,
              suggestions: state.suggestions,
              onSuggestion: onSuggestion,
              onTryAllSources: onTryAllSources,
              onSearchTorrents: onSearchTorrents,
              onClearGenre: () => onGenre(''),
            ),
          ),
        ];
      case SearchStatus.idle:
        return searchLandingSlivers(
          context,
          recent: state.recent,
          genres: state.genres,
          genresLoading: state.genresLoading,
          genresFailed: state.genresFailed,
          onSuggestion: onSuggestion,
          onGenre: onGenre,
          onRemoveRecent: onRemoveRecent,
          onClearRecents: onClearRecents,
          onRetryGenres: onRetry,
        );
      case SearchStatus.loaded:
      case SearchStatus.refreshing:
        return [
          // Results that do not answer the question still get shown — one of
          // them may be the aliased match no scorer can recognise — but they
          // get shown with the way out attached. Without this the search tab
          // was a dead end: a grid of the wrong thing, no error, and the "try
          // all sources" offer locked behind an empty result the source was
          // never going to return.
          if (state.weakResults)
            SliverToBoxAdapter(
              child: _WeakResultsBanner(
                query: state.criteriaLabel,
                suggestions: state.suggestions,
                onSuggestion: onSuggestion,
                onTryAllSources: onTryAllSources,
                onSearchTorrents: onSearchTorrents,
              ),
            ),
          // What the grid below is, said once: how many rows answered, and
          // which filter produced them. A genre browse used to be unlabelled
          // and unescapable — the chip in the header lit up, the grid changed,
          // and the only way back was to guess that the filter sheet had a
          // Clear button in it.
          SliverToBoxAdapter(
            child: _SearchCriteriaStrip(
              count: state.items.length,
              hasMore: state.hasMore,
              genre: state.genreName,
              onClearGenre: () => onGenre(''),
            ),
          ),
          SearchResultsGrid(items: state.items),
          if (state.isLoadingMore)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: CircularProgressIndicator(
                    color: AppColors.primary,
                    strokeWidth: 2,
                  ),
                ),
              ),
            )
          else if (state.loadMoreFailure != null)
            SliverToBoxAdapter(
              child: _LoadMoreFailedFooter(
                failure: state.loadMoreFailure!,
                onRetry: onRetryMore,
              ),
            ),
        ];
    }
  }
}

/// The end of the list, when the next page did not arrive.
///
/// Where the spinner was. It has to be as quiet as the spinner it replaces —
/// the results above it are fine and the reader is in the middle of reading
/// them — but it has to be there, because the alternative is what shipped: a
/// spinner that appeared, vanished and left the reader to work out whether the
/// list had ended or the source had.
class _LoadMoreFailedFooter extends StatelessWidget {
  const _LoadMoreFailedFooter({required this.failure, required this.onRetry});

  final SourceFailure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 16, 32, 28),
      child: Column(
        children: [
          Text(
            failure.headline,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textHint, fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          _ActionChip(
            icon: Icons.refresh_rounded,
            label: 'search.load_more'.tr(),
            onTap: onRetry,
          ),
        ],
      ),
    );
  }
}

/// A failure reported over results that are still worth looking at.
class _SearchErrorBanner extends StatelessWidget {
  const _SearchErrorBanner({required this.message, required this.onRetry});

  final String? message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 18,
              color: AppColors.errorLight,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message ?? 'general.error'.tr(),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12.5,
                ),
              ),
            ),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: Text('general.retry'.tr())),
          ],
        ),
      ),
    );
  }
}

/// The one results grid for the feature. Cross-search's merged view uses it too.
class SearchResultsGrid extends StatelessWidget {
  const SearchResultsGrid({super.key, required this.items});

  final List<MovieEntity> items;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate((context, i) {
          final movie = items[i];
          return ItemAppear(
            index: i,
            columns: searchGridColumns(MediaQuery.sizeOf(context).width),
            child: SearchResultCard(
              movie: movie,
              // Position, not url: cross-search merges several sources, so the
              // same title legitimately appears more than once in one grid.
              heroTag: 'search:$i',
              // Results can carry a provider of their own — opening them
              // against the app's "current" provider is how a result that
              // looked fine in the grid failed to load its detail page.
              provider: movie.provider.isEmpty ? null : movie.provider,
              onTap: () {
                if (movie.url.isEmpty) return;
                context.push(
                  '/detail',
                  extra: DetailArgs(
                    contentUrl: movie.url,
                    preview: movie,
                    provider: movie.provider.isEmpty ? null : movie.provider,
                    heroTag: 'search:$i',
                  ),
                );
              },
            ),
          );
        }, childCount: items.length),
        gridDelegate: searchGridDelegate(context),
      ),
    );
  }
}

class _SearchSkeletonGrid extends StatelessWidget {
  const _SearchSkeletonGrid();

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = searchGridColumns(width);
    // One shimmer over the whole grid, not one per tile.
    //
    // Twenty-one [ShimmerWrapper]s meant twenty-one AnimationControllers and
    // twenty-one shader layers, each sweeping its own tile on its own clock —
    // so the screen read as a field of separately blinking rectangles rather
    // than as one surface with a highlight crossing it. A single wrapper is one
    // controller, one sweep, and it travels the way a sweep is supposed to:
    // across the grid.
    //
    // The grid is shrink-wrapped, which for real content would be wrong — it
    // lays every child out at once — but there are three rows of it, they hold
    // no images and they run no entrance animations, and laying them out is the
    // price of the single sweep.
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      sliver: SliverToBoxAdapter(
        child: ShimmerWrapper(
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: searchGridDelegate(context),
            itemCount: columns * 3,
            itemBuilder: (_, _) => const SearchCardSkeleton(),
          ),
        ),
      ),
    );
  }
}

class _SearchEmptyView extends StatelessWidget {
  const _SearchEmptyView({
    required this.criteria,
    required this.label,
    required this.suggestions,
    required this.onSuggestion,
    required this.onTryAllSources,
    required this.onClearGenre,
    this.onSearchTorrents,
  });

  final SearchCriteria criteria;

  /// [criteria] in words. Taken rather than derived because the slug-to-name
  /// lookup needs the genre list, which lives on the state.
  final String label;

  final List<String> suggestions;
  final ValueChanged<String> onSuggestion;
  final VoidCallback onTryAllSources;

  /// Drops the genre and goes back to the landing screen.
  final VoidCallback onClearGenre;

  final VoidCallback? onSearchTorrents;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 60, 32, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.search_off_rounded,
            color: AppColors.textHint,
            size: 52,
          ),
          const SizedBox(height: 14),
          Text(
            'search.no_results_for'.tr(namedArgs: {'query': label}),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 15,
            ),
            textAlign: TextAlign.center,
          ),
          // Titles that exist, before the sources that might carry them. A
          // misspelling is the most common reason a search finds nothing, and
          // no amount of asking more sources fixes a word — where "narutoo"
          // returns nothing everywhere, "Naruto" returns everything.
          if (suggestions.isNotEmpty)
            _DidYouMean(suggestions: suggestions, onTap: onSuggestion),
          if (criteria.text.isNotEmpty) ...[
            const SizedBox(height: 20),
            _ActionChip(
              icon: Icons.travel_explore_rounded,
              label: 'search.try_all_sources'.tr(),
              onTap: onTryAllSources,
            ),
            // Torrents are the honest last resort, and this is the moment they
            // are worth offering: the catalogue sources have all been asked and
            // none of them has it. Offering it earlier would push people onto
            // BitTorrent for titles that stream fine.
            if (onSearchTorrents != null) ...[
              const SizedBox(height: 10),
              _ActionChip(
                icon: Icons.hub_rounded,
                label: 'search.try_torrents'.tr(),
                onTap: onSearchTorrents!,
              ),
            ],
          ],
          // A genre that returns nothing had no way out at all: the offers
          // above are all text-search offers, so the screen was an empty page
          // with an icon on it. The filter that emptied it is the one thing
          // there is to undo.
          if (criteria.text.isEmpty && criteria.genre.isNotEmpty) ...[
            const SizedBox(height: 20),
            _ActionChip(
              icon: Icons.filter_alt_off_rounded,
              label: 'search.clear_genre'.tr(),
              onTap: onClearGenre,
            ),
          ],
        ],
      ),
    );
  }
}

/// Shown above results that the source returned but that do not match.
///
/// Deliberately not an error and not a dismissal of what is below it. The
/// source answered; it just answered with something else, and the honest thing
/// is to say so once and point at the sources that were not asked.
class _WeakResultsBanner extends StatelessWidget {
  const _WeakResultsBanner({
    required this.query,
    required this.suggestions,
    required this.onSuggestion,
    required this.onTryAllSources,
    this.onSearchTorrents,
  });

  final String query;
  final List<String> suggestions;
  final ValueChanged<String> onSuggestion;
  final VoidCallback onTryAllSources;
  final VoidCallback? onSearchTorrents;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 4, 14, 12),
      padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.info_outline_rounded,
                size: 18,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'search.weak_results'.tr(namedArgs: {'query': query}),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          if (suggestions.isNotEmpty)
            _DidYouMean(
              suggestions: suggestions,
              onTap: onSuggestion,
              compact: true,
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ActionChip(
                icon: Icons.travel_explore_rounded,
                label: 'search.try_all_sources'.tr(),
                onTap: onTryAllSources,
              ),
              if (onSearchTorrents != null)
                _ActionChip(
                  icon: Icons.hub_rounded,
                  label: 'search.try_torrents'.tr(),
                  onTap: onSearchTorrents!,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Real titles for a query that found nothing useful.
///
/// These come from metadata catalogues, not from the sources — AniList and
/// TMDB know what things are called, which is the question actually being
/// answered here. A source can only ever say "not here"; only a catalogue can
/// say "the word is Naruto".
///
/// Capped at four. This appears under an unhelpful result, and a long list of
/// alternatives at that moment reads as the app arguing rather than helping.
class _DidYouMean extends StatelessWidget {
  const _DidYouMean({
    required this.suggestions,
    required this.onTap,
    this.compact = false,
  });

  final List<String> suggestions;
  final ValueChanged<String> onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: compact ? 10 : 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'search.did_you_mean'.tr(),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: compact ? WrapAlignment.start : WrapAlignment.center,
            children: [
              for (final title in suggestions.take(4))
                _ActionChip(
                  icon: Icons.north_east_rounded,
                  label: title,
                  onTap: () => onTap(title),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SearchErrorView extends StatelessWidget {
  const _SearchErrorView({required this.failure, required this.onRetry});

  final SourceFailure? failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final kind = failure?.kind ?? SourceFailureKind.unknown;
    // The headline is already a sentence for every kind the classifier
    // recognises, so it IS the title; `detail` is the raw line that used to be
    // the title. For an unrecognised failure there is no sentence to show, and
    // a generic one over a technical line still beats the line alone.
    final title = kind == SourceFailureKind.unknown
        ? 'search.search_failed'.tr()
        : (failure?.headline ?? 'search.search_failed'.tr());
    final message = kind == SourceFailureKind.unknown
        ? (failure?.headline ?? '')
        : (failure?.detail ?? '');
    final icon = switch (kind) {
      SourceFailureKind.unreachable => Icons.wifi_off_rounded,
      SourceFailureKind.gone => Icons.link_off_rounded,
      SourceFailureKind.blocked => Icons.shield_outlined,
      SourceFailureKind.rateLimited => Icons.hourglass_empty_rounded,
      // Updating the SOURCE, not the app — a different picture from
      // [incompatible], which is the one that asks for a newer Sozo.
      SourceFailureKind.outdated => Icons.update_rounded,
      SourceFailureKind.incompatible => Icons.system_update_alt_rounded,
      SourceFailureKind.broken => Icons.extension_off_rounded,
      SourceFailureKind.unknown => Icons.error_outline_rounded,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 60, 32, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.textHint, size: 52),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 15,
            ),
            textAlign: TextAlign.center,
          ),
          if (message.isNotEmpty && kind != SourceFailureKind.unreachable) ...[
            const SizedBox(height: 8),
            Text(
              message,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textHint, fontSize: 12.5),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 20),
          _ActionChip(
            icon: Icons.refresh_rounded,
            label: 'general.retry'.tr(),
            onTap: onRetry,
            autofocus: true,
          ),
          const SizedBox(height: 8),
          SupportSuggestion(
            screen: 'search',
            category: SupportCategory.content,
            error: message,
          ),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.autofocus = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          // Flexible, because the label is a translation. These chips sit in a
          // 32-point-inset column on a 320-point phone, which leaves a little
          // over 200 for the text — and the app ships twelve languages, one of
          // which routinely needs half again what English does. An overflow
          // stripe across the only control on an empty screen is worse than a
          // clipped word.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    // Android TV: this is often the only control on the screen, so it has to be
    // a focus stop or the remote has no way out.
    if (isTvPlatform) {
      return TvFocusable(
        onPressed: onTap,
        borderRadius: 10,
        autofocus: autofocus,
        child: content,
      );
    }
    return GestureDetector(onTap: onTap, child: content);
  }
}

/// One line between the header and the grid: how many rows there are, and the
/// filter that produced them.
///
/// Both halves earn their place. The count is the only acknowledgement the
/// search gets — the grid just appears, and on a source that returns four rows
/// for a popular title the honest reading is "this source has four", not "the
/// search is still going". The pill is the way back: a genre browse changes the
/// whole screen from a control in a modal sheet, and until now nothing on the
/// screen it changed said which genre, or offered to undo it.
class _SearchCriteriaStrip extends StatelessWidget {
  const _SearchCriteriaStrip({
    required this.count,
    required this.hasMore,
    required this.genre,
    required this.onClearGenre,
  });

  final int count;

  /// More pages exist, so [count] is what has arrived rather than what there
  /// is. Worth the separate phrasing: "12 results" under a list that grows to
  /// 200 as you scroll is a number that was never true.
  final bool hasMore;

  /// The active genre, in words. Empty when the search is a plain text search.
  final String genre;

  final VoidCallback onClearGenre;

  @override
  Widget build(BuildContext context) {
    final label = hasMore
        ? 'search.results_so_far'.tr(args: ['$count'])
        : 'search.results_n'.tr(args: ['$count']);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textHint,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.1,
              ),
            ),
          ),
          if (genre.isNotEmpty)
            _GenreCriteriaPill(genre: genre, onClear: onClearGenre),
        ],
      ),
    );
  }
}

/// The active genre, and the × that removes it.
///
/// Weight rather than colour: this is a statement of what is on screen, not an
/// action being offered, so it reads as a label with an affordance on it rather
/// than as a button. The surface tint is the app's own card fill.
class _GenreCriteriaPill extends StatelessWidget {
  const _GenreCriteriaPill({required this.genre, required this.onClear});

  final String genre;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: const EdgeInsetsDirectional.fromSTEB(10, 5, 6, 5),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.textHint.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.filter_alt_rounded,
            size: 13,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 5),
          // A long genre name must not push the × off the row, and must not
          // make this pill wide enough to squeeze the count out of the line.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Text(
              genre,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 2),
          Icon(
            Icons.close_rounded,
            size: 15,
            color: AppColors.textSecondary.withValues(alpha: 0.9),
          ),
        ],
      ),
    );

    if (isTvPlatform) {
      return TvFocusable(onPressed: onClear, borderRadius: 999, child: content);
    }
    return Semantics(
      button: true,
      label: 'search.clear_genre'.tr(),
      child: HoverTap(
        onTap: onClear,
        borderRadius: 999,
        scale: 1.03,
        haptic: true,
        child: content,
      ),
    );
  }
}
