import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/widgets/item_appear.dart';
import 'package:soplay/core/tv/tv.dart';
import 'package:soplay/features/detail/domain/entities/detail_args.dart';
import 'package:soplay/features/home/domain/entities/movie.dart';
import 'package:soplay/features/home/presentation/widgets/home_shared_widgets.dart';
import 'package:soplay/features/search/domain/entities/genre_entity.dart';
import 'package:soplay/features/search/presentation/blocs/search_bloc.dart';
import 'package:soplay/features/search/presentation/widgets/search_result_card.dart';

class SearchContentView extends StatelessWidget {
  const SearchContentView({
    super.key,
    required this.state,
    required this.scrollController,
    required this.topPad,
    required this.bottomPad,
    required this.onRetry,
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
    return CustomScrollView(
      controller: scrollController,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
    );
  }

  List<Widget> _body(BuildContext context) {
    switch (state.status) {
      case SearchStatus.loading:
        return [const _SearchSkeletonGrid()];
      case SearchStatus.error:
        return [
          SliverFillRemaining(
            hasScrollBody: false,
            child: _SearchErrorView(
              kind: state.errorKind,
              message: state.errorMessage,
              onRetry: onRetry,
            ),
          ),
        ];
      case SearchStatus.empty:
        return [
          SliverFillRemaining(
            hasScrollBody: false,
            child: _SearchEmptyView(
              criteria: state.criteria,
              suggestions: state.suggestions,
              onSuggestion: onSuggestion,
              onTryAllSources: onTryAllSources,
              onSearchTorrents: onSearchTorrents,
            ),
          ),
        ];
      case SearchStatus.idle:
        return [
          SliverToBoxAdapter(
            child: _SearchIdleView(
              recent: state.recent,
              genres: state.genres,
              genresLoading: state.genresLoading,
              onSuggestion: onSuggestion,
              onGenre: onGenre,
              onRemoveRecent: onRemoveRecent,
              onClearRecents: onClearRecents,
            ),
          ),
        ];
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
                query: state.criteria.label,
                suggestions: state.suggestions,
                onSuggestion: onSuggestion,
                onTryAllSources: onTryAllSources,
                onSearchTorrents: onSearchTorrents,
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
            ),
        ];
    }
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
        delegate: SliverChildBuilderDelegate(
          (context, i) {
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
          },
          childCount: items.length,
        ),
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
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate(
          (context, i) => const ShimmerWrapper(
            child: HomeSkeletonBox(
              width: double.infinity,
              height: double.infinity,
              radius: 10,
            ),
          ),
          childCount: columns * 3,
        ),
        gridDelegate: searchGridDelegate(context),
      ),
    );
  }
}

class _SearchIdleView extends StatelessWidget {
  const _SearchIdleView({
    required this.recent,
    required this.genres,
    required this.genresLoading,
    required this.onSuggestion,
    required this.onGenre,
    required this.onRemoveRecent,
    required this.onClearRecents,
  });

  final List<String> recent;
  final List<GenreEntity> genres;
  final bool genresLoading;
  final ValueChanged<String> onSuggestion;
  final ValueChanged<String> onGenre;
  final ValueChanged<String> onRemoveRecent;
  final VoidCallback onClearRecents;

  @override
  Widget build(BuildContext context) {
    if (recent.isEmpty && genres.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 80),
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
              Text(
                'search.hint'.tr(),
                style: const TextStyle(
                  color: AppColors.textHint,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (recent.isNotEmpty) ...[
            Row(
              children: [
                Expanded(child: _SectionTitle('search.recent'.tr())),
                _TextAction(
                  label: 'search.clear_filter'.tr(),
                  onTap: onClearRecents,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
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
            const SizedBox(height: 26),
          ],
          if (genres.isNotEmpty) ...[
            _SectionTitle('search.categories'.tr()),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final g in genres)
                  _Chip(
                    label: g.name.isNotEmpty ? g.name : g.slug,
                    onTap: () => onGenre(g.slug),
                  ),
              ],
            ),
          ] else if (genresLoading)
            const ShimmerWrapper(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  HomeSkeletonBox(width: 92, height: 34, radius: 10),
                  HomeSkeletonBox(width: 68, height: 34, radius: 10),
                  HomeSkeletonBox(width: 110, height: 34, radius: 10),
                  HomeSkeletonBox(width: 80, height: 34, radius: 10),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SearchEmptyView extends StatelessWidget {
  const _SearchEmptyView({
    required this.criteria,
    required this.suggestions,
    required this.onSuggestion,
    required this.onTryAllSources,
    this.onSearchTorrents,
  });

  final SearchCriteria criteria;
  final List<String> suggestions;
  final ValueChanged<String> onSuggestion;
  final VoidCallback onTryAllSources;
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
            'search.no_results_for'.tr(namedArgs: {'query': criteria.label}),
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 15),
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
  const _SearchErrorView({
    required this.kind,
    required this.message,
    required this.onRetry,
  });

  final SearchFailureKind kind;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final (icon, title) = switch (kind) {
      SearchFailureKind.network => (
          Icons.wifi_off_rounded,
          'errors.network'.tr(),
        ),
      SearchFailureKind.source => (
          Icons.extension_off_rounded,
          'search.source_failed'.tr(),
        ),
      SearchFailureKind.unknown => (
          Icons.error_outline_rounded,
          'search.search_failed'.tr(),
        ),
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
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 15),
            textAlign: TextAlign.center,
          ),
          if (message.isNotEmpty && kind != SearchFailureKind.network) ...[
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
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: AppColors.textHint,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
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
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: AppColors.textHint),
            const SizedBox(width: 6),
          ],
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (onRemove != null) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onRemove,
              child: const Icon(
                Icons.close_rounded,
                size: 13,
                color: AppColors.textHint,
              ),
            ),
          ],
        ],
      ),
    );

    if (isTvPlatform) {
      return TvFocusable(onPressed: onTap, borderRadius: 10, child: chip);
    }
    return GestureDetector(onTap: onTap, child: chip);
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
          Text(
            label,
            style: TextStyle(
              color: AppColors.primary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
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
