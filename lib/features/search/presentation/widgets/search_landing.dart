import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:soplay/core/content/catalogue.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/tv/tv.dart';
import 'package:soplay/core/widgets/item_appear.dart';
import 'package:soplay/features/detail/domain/entities/detail_args.dart';
import 'package:soplay/features/home/domain/entities/movie.dart';
import 'package:soplay/features/home/presentation/bloc/home/home_bloc.dart';
import 'package:soplay/features/home/presentation/bloc/home/home_state.dart';
import 'package:soplay/features/home/presentation/widgets/home_shared_widgets.dart';
import 'package:soplay/features/search/domain/entities/genre_entity.dart';
import 'package:soplay/features/search/presentation/widgets/genre_tile.dart';
import 'package:soplay/features/search/presentation/widgets/search_result_card.dart';

/// What the search tab shows before a word is typed.
///
/// It used to be a magnifying glass and a hint, then a row of genre names once
/// the provider had any. Now it is somewhere to start from: what was searched
/// last, what is trending on the source in use, and the genres as a grid of
/// covers — the three ways somebody who has not decided yet finds something.
class SearchLanding extends StatelessWidget {
  const SearchLanding({
    super.key,
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
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 900 ? 4 : (width >= 600 ? 3 : 2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (recent.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
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
          const SizedBox(height: 10),
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
        const _TrendingRail(),
        if (genres.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _SectionTitle('search.categories'.tr()),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.85,
              ),
              itemCount: genres.length,
              itemBuilder: (context, i) {
                final g = genres[i];
                return ItemAppear(
                  index: i,
                  columns: columns,
                  staggerLimit: 24,
                  child: GenreTile(
                    label: g.name.isNotEmpty ? g.name : g.slug,
                    image: g.image,
                    index: i,
                    onTap: () => onGenre(g.slug),
                  ),
                );
              },
            ),
          ),
        ] else if (genresLoading)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: ShimmerWrapper(
              child: GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                crossAxisCount: columns,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.85,
                children: [
                  for (var i = 0; i < 6; i++)
                    const HomeSkeletonBox(
                      width: double.infinity,
                      height: double.infinity,
                      radius: 14,
                    ),
                ],
              ),
            ),
          )
        else if (recent.isEmpty)
          // Nothing to start from at all: the old empty state, kept for the
          // source that offers neither genres nor a home.
          Padding(
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
          ),
      ],
    );
  }
}

/// The first rail of the home that is loaded — what is trending on the source
/// or catalogue in use — so the search tab is not a blank page waiting for a
/// word. Nothing while Home is still loading or has failed: a rail of its own
/// would be a second request for the same list.
class _TrendingRail extends StatelessWidget {
  const _TrendingRail();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<HomeBloc, HomeState>(
      buildWhen: (a, b) =>
          a is HomeLoaded != b is HomeLoaded || b is HomeLoaded,
      builder: (context, state) {
        if (state is! HomeLoaded) return const SizedBox.shrink();
        final sections = state.homeData.sections
            .where((s) => s.items.length >= 4)
            .toList();
        // What everyone is watching, not what this viewer has saved: the
        // personal rails a home can lead with are the search tab's least
        // useful answer to "what should I look for".
        bool personal(String k) =>
            k.contains('list') ||
            k.contains('continue') ||
            k.contains('history') ||
            k.contains('recent');
        bool trending(String k) => k.contains('trend') || k.contains('popular');
        final rail =
            sections.where((s) => trending(s.key.toLowerCase())).firstOrNull ??
            sections.where((s) => !personal(s.key.toLowerCase())).firstOrNull;
        if (rail == null) return const SizedBox.shrink();
        final items = rail.items.take(15).toList();
        final catalogue = Catalogue.fromId(state.homeData.provider);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: _SectionTitle(
                catalogue != null
                    ? '${rail.label} · ${catalogue.labelKey.tr()}'
                    : rail.label,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 214,
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
                      width: 118,
                      provider: movie.provider.isEmpty ? null : movie.provider,
                      onTap: () => _open(context, movie),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 22),
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
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
      padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: AppColors.textSecondary),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (onRemove != null) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onRemove,
              child: const Padding(
                padding: EdgeInsets.all(2),
                child: Icon(
                  Icons.close_rounded,
                  size: 15,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ] else
            const SizedBox(width: 4),
        ],
      ),
    );
    if (isTvPlatform) {
      return TvFocusable(onPressed: onTap, borderRadius: 10, child: chip);
    }
    return GestureDetector(onTap: onTap, child: chip);
  }
}
