import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/anilist/presentation/widgets/anilist_linked_badge.dart';
import 'package:soplay/features/home/domain/entities/movie.dart';
import 'package:soplay/features/home/presentation/widgets/home_shared_widgets.dart';
import 'package:soplay/core/widgets/poster_hero.dart';

const double _posterRatio = 2 / 3;
const double _captionHeight = 48;

/// Poster grid shared by single-source and cross-source search.
///
/// Column count comes from the actual width, not the platform: an Android
/// tablet, an iPad and a TV are all "mobile" to [isDesktopPlatform] and used to
/// get three enormous columns. The extent is computed rather than expressed as
/// an aspect ratio so the poster keeps a true 2:3 and the caption strip is the
/// same height everywhere.
SliverGridDelegate searchGridDelegate(
  BuildContext context, {
  double horizontalPadding = 32,
  double spacing = 10,
}) {
  final width = MediaQuery.sizeOf(context).width;
  final columns = searchGridColumns(width);
  final tile = (width - horizontalPadding - spacing * (columns - 1)) / columns;
  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: columns,
    crossAxisSpacing: spacing,
    mainAxisSpacing: 16,
    mainAxisExtent: tile / _posterRatio + _captionHeight,
  );
}

int searchGridColumns(double width) {
  if (width < 420) return 3;
  if (width < 620) return 4;
  if (width < 900) return 5;
  if (width < 1200) return 6;
  return 7;
}

double searchCardHeight(double tileWidth) =>
    tileWidth / _posterRatio + _captionHeight;

class SearchResultCard extends StatelessWidget {
  const SearchResultCard({
    super.key,
    required this.movie,
    required this.onTap,
    this.provider,
    this.sourceLabel,
    this.sourceCount = 1,
    this.width,
    this.heroTag,
  });

  final MovieEntity movie;
  final VoidCallback onTap;

  /// The source this hit came from — passed on to the detail page so a result
  /// never opens against the app's "current" provider by accident.
  final String? provider;

  /// Human-readable source name, shown when several sources are on screen.
  final String? sourceLabel;

  /// How many sources carry this title. > 1 draws the merge pill.
  final int sourceCount;

  final double? width;

  /// Ties this poster to the detail page's header so it flies rather than the
  /// page appearing from nothing. Null leaves the card exactly as it was.
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    final subtitle = sourceLabel ?? (movie.year != null ? '${movie.year}' : '');

    final card = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Only the artwork flies. The AniList badge and the rating pill
              // stay with the grid — a 9pt pill interpolated up to header size
              // reads as a glitch, not a transition.
              PosterHero(
                tag: heroTag,
                url: movie.thumbnail,
                child: HomeNetworkImage(
                  url: movie.thumbnail,
                  borderRadius: BorderRadius.circular(10),
                  placeholderIcon: Icons.movie_rounded,
                ),
              ),
              Positioned(
                top: 6,
                left: 6,
                child: AnilistLinkedBadge(
                  contentUrl: movie.url,
                  provider: provider,
                ),
              ),
              if (movie.rating != null)
                Positioned(
                  top: 6,
                  right: 6,
                  child: _Pill(
                    color: Colors.black.withValues(alpha: 0.72),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.star_rounded,
                          color: AppColors.rating,
                          size: 10,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${movie.rating}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (sourceCount > 1)
                Positioned(
                  left: 6,
                  bottom: 6,
                  child: _Pill(
                    color: AppColors.primary.withValues(alpha: 0.92),
                    child: Text(
                      'search.sources_n'.tr(args: ['$sourceCount']),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          movie.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 12,
            height: 1.15,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (subtitle.isNotEmpty)
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textHint,
              fontSize: 10.5,
              height: 1.2,
            ),
          ),
      ],
    );

    final tappable = HoverTap(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: card,
    );

    return width == null ? tappable : SizedBox(width: width, child: tappable);
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(5),
    ),
    child: child,
  );
}
