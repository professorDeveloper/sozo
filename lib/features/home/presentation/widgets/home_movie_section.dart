import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/widgets/item_appear.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/widgets/poster_hero.dart';
import 'package:soplay/features/detail/domain/entities/detail_args.dart';
import 'package:soplay/features/home/domain/entities/movie.dart';
import 'package:soplay/features/home/domain/entities/view_all.dart';
import 'package:soplay/features/home/presentation/widgets/home_shared_widgets.dart';
import 'package:soplay/features/home/presentation/widgets/home_ui_helpers.dart';

import 'package:soplay/core/presentation/widgets/kaizoku_badge.dart';
import 'package:soplay/core/presentation/widgets/kaizoku_media_card.dart';
import 'package:soplay/core/theme/kaizoku_colors.dart';

class MovieSection extends StatelessWidget {
  const MovieSection({
    super.key,
    required this.title,
    required this.movies,
    this.isHighlighted = false,
    required this.type,
    required this.slug,
    this.onSeeAll,
  });

  final String title;
  final String type;
  final String slug;
  final List<MovieEntity> movies;
  final bool isHighlighted;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The padding is INSIDE the InkWell: outside it, the tappable strip
          // was only as tall as the title text (~19dp).
          HomeSectionTapTarget(
            onTap: () {
              if (onSeeAll != null) {
                onSeeAll!();
                return;
              }
              context.push(
                '/view-all',
                extra: ViewAllEntity(type: type, slug: slug, name: title),
              );
            },
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(17, 18, 20, 14),
              child: Row(
                children: [
                  // Shin Kaizoku glowing crimson accent tick
                  Container(
                    width: 3.5,
                    height: isHighlighted ? 20 : 16,
                    decoration: BoxDecoration(
                      color: KaizokuColors.neonCrimson,
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: [
                        BoxShadow(
                          color: KaizokuColors.neonCrimson.withValues(alpha: isHighlighted ? 0.75 : 0.45),
                          blurRadius: isHighlighted ? 8 : 5,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: KaizokuColors.textHigh,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: isHighlighted
                        ? KaizokuColors.neonCrimson
                        : KaizokuColors.textMuted,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            height: isDesktopPlatform ? 255 : 195,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              // Don't clip the hover scale/ring on desktop.
              clipBehavior:
                  isDesktopPlatform ? Clip.none : Clip.hardEdge,
              padding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: isDesktopPlatform ? 4 : 0,
              ),
              itemCount: movies.length > 16 ? 16 : movies.length,
              itemBuilder: (_, index) => ItemAppear(
                index: index,
                // A rail scrolls sideways, so its cards come in from the edge
                // they are travelling from, one after the other.
                axis: Axis.horizontal,
                child: _MovieCard(
                  movie: movies[index],
                  // Section slug + position: unique on screen even when two
                  // rows carry the same title, and stable across a rebuild.
                  heroTag: 'poster:$slug:$index',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MovieCard extends StatelessWidget {
  const _MovieCard({required this.movie, this.heroTag});

  final MovieEntity movie;
  final String? heroTag;

  void _openDetail(BuildContext context) {
    if (movie.url.isNotEmpty) {
      context.push(
        '/detail',
        extra: DetailArgs(
          contentUrl: movie.url,
          preview: movie,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final desktop = isDesktopPlatform;
    final width = desktop ? 152.0 : 118.0;
    final quality = primaryQuality(movie);

    return Container(
      width: width,
      margin: EdgeInsets.symmetric(horizontal: desktop ? 6 : 4),
      child: KaizokuMediaCard(
        title: movieTitle(movie),
        imageUrl: movie.thumbnail,
        subtitle: movie.year != null ? '${movie.year}' : null,
        ratio: KaizokuCardRatio.poster,
        badgeText: quality,
        badgeVariant: KaizokuBadgeVariant.primary,
        tagText: movie.rating != null ? '★ ${movie.rating}' : null,
        onTap: () => _openDetail(context),
      ),
    );
  }
}

class CollectionLoadingRow extends StatelessWidget {
  const CollectionLoadingRow({super.key});

  @override
  Widget build(BuildContext context) {
    final desktop = isDesktopPlatform;
    final cardW = desktop ? 152.0 : 110.0;
    final posterH = desktop ? 225.0 : 155.0;
    final radius = desktop ? 12.0 : 10.0;
    return ShimmerWrapper(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 18, 16, 10),
        child: SizedBox(
          height: posterH + (desktop ? 40 : 5),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: 6,
            itemBuilder: (_, i) => Padding(
              padding: EdgeInsetsDirectional.only(end: desktop ? 12 : 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  HomeSkeletonBox(
                    width: cardW,
                    height: posterH,
                    radius: radius,
                  ),
                  if (desktop) ...[
                    const SizedBox(height: 10),
                    HomeSkeletonBox(width: cardW * 0.8, height: 13, radius: 4),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
