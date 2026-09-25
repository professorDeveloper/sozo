import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/anilist/presentation/widgets/anilist_linked_badge.dart';
import 'package:soplay/features/home/domain/entities/movie.dart';
import 'package:soplay/features/home/presentation/widgets/home_shared_widgets.dart';
import 'package:soplay/core/widgets/poster_hero.dart';

const double _posterRatio = 2 / 3;

/// The height the caption strip under a poster needs: the 6pt gap, two lines
/// of the 12pt title at a line height of 1.15, and one line of the 10.5pt
/// subtitle at 1.2 — the caption exactly as it is built below.
///
/// Derived rather than declared, because as a flat 48 it was only correct at
/// the default text size. One notch up on the system text slider and the grid
/// still handed every tile 48dp for a caption that now wanted 58.
///
/// Nothing was clipped by that — the caption is the inflexible part of the
/// card's Column and the poster above it is the [Expanded] one, so the ten
/// missing points came out of the POSTER instead. Every cover in the grid lost
/// height it was owed, stopped being a 2:3 rectangle, and cropped further into
/// the artwork the larger the text got; at accessibility sizes the poster is
/// squeezed hard while the tile it sits in never grows. Reserving the caption's
/// real height is what keeps the poster the shape the grid was built around.
///
/// [context] is optional only because one caller outside this feature has no
/// BuildContext to give; without it the caption falls back to its unscaled
/// height and the poster is squeezed again at large text sizes.
double _captionHeight(BuildContext? context) {
  final scaler = context == null
      ? TextScaler.noScaling
      : MediaQuery.textScalerOf(context);
  return 6 + scaler.scale(12) * 1.15 * 2 + scaler.scale(10.5) * 1.2;
}

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
    mainAxisExtent: tile / _posterRatio + _captionHeight(context),
  );
}

int searchGridColumns(double width) {
  if (width < 420) return 3;
  if (width < 620) return 4;
  if (width < 900) return 5;
  if (width < 1200) return 6;
  return 7;
}

double searchCardHeight(double tileWidth, [BuildContext? context]) =>
    tileWidth / _posterRatio + _captionHeight(context);

/// [SearchResultCard]'s shape, greyed out.
///
/// The old skeleton was one rectangle filling the whole grid cell, caption
/// space included — a solid slab where the card has a 2:3 poster and three
/// lines of text. So the wait looked nothing like the result: the poster
/// appeared to shrink as the real cards landed, and the caption area went from
/// filled to empty, which is a change of shape on every tile at once.
///
/// The caption is built out of the same [FixedTextLines] boxes and the same
/// numbers as the card's own — 12pt at 1.15 over two lines, then 10.5 at 1.2 —
/// so it reserves what the card reserves at any text size.
class SearchCardSkeleton extends StatelessWidget {
  const SearchCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: HomeSkeletonBox(
            width: double.infinity,
            height: double.infinity,
            radius: 10,
          ),
        ),
        SizedBox(height: 6),
        FixedTextLines(
          fontSize: 12,
          lineHeight: 1.15,
          lines: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonLine(width: double.infinity),
              SizedBox(height: 5),
              // Short: a title that wraps rarely fills its second line, and a
              // full-width second bar reads as a block of text rather than as a
              // title waiting to arrive.
              SkeletonLine(width: 52),
            ],
          ),
        ),
        FixedTextLines(
          fontSize: 10.5,
          lineHeight: 1.2,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: SkeletonLine(width: 28),
          ),
        ),
      ],
    );
  }
}

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
              // Directional, not physical. Arabic is the app's largest
              // translation and it mirrors the whole card, so a badge pinned
              // to `left` ends up over the middle of the title's artwork
              // rather than in the corner it was designed for.
              PositionedDirectional(
                top: 6,
                start: 6,
                child: AnilistLinkedBadge(
                  contentUrl: movie.url,
                  provider: provider,
                ),
              ),
              if (movie.rating != null)
                PositionedDirectional(
                  top: 6,
                  end: 6,
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
                PositionedDirectional(
                  start: 6,
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
      // Opening a title is the tap on this screen that commits to something,
      // which is the bar HoverTap's opt-in haptic sets. It is opt-in and off by
      // default, so the card has to ask: the search grid and the trending rail
      // both reach the detail page through here and neither was being felt.
      haptic: true,
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
