import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/detail/domain/entities/detail_args.dart';
import 'package:soplay/features/home/domain/entities/movie.dart';
import 'package:soplay/features/home/domain/entities/view_all.dart';
import 'package:soplay/features/home/presentation/widgets/home_shared_widgets.dart';
import 'package:soplay/features/home/presentation/widgets/home_ui_helpers.dart';

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
          InkWell(
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
              padding: const EdgeInsets.fromLTRB(17, 18, 20, 14),
              child: Row(
                children: [
                  // The accent tick is on EVERY row now, not only the
                  // highlighted one — it is the mark that carries the chosen
                  // colour down the whole of Home. Highlighted rows keep their
                  // distinction by being taller and gradient-filled.
                  Container(
                    width: 3,
                    height: isHighlighted ? 19 : 15,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: isHighlighted
                            ? [AppColors.primaryLight, AppColors.primary]
                            : [
                                AppColors.primary,
                                AppColors.primary.withValues(alpha: 0.55),
                              ],
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: isHighlighted
                        ? AppColors.primary
                        : AppColors.textHint,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            height: isDesktopPlatform ? 300 : 195,
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
              itemBuilder: (_, index) => _MovieCard(movie: movies[index]),
            ),
          ),
        ],
      ),
    );
  }
}

class _MovieCard extends StatefulWidget {
  const _MovieCard({required this.movie});

  final MovieEntity movie;

  @override
  State<_MovieCard> createState() => _MovieCardState();
}

class _MovieCardState extends State<_MovieCard> {
  bool _hover = false;

  void _openDetail() {
    final movie = widget.movie;
    if (movie.url.isNotEmpty) {
      context.push(
        '/detail',
        extra: DetailArgs(contentUrl: movie.url, preview: movie),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final movie = widget.movie;
    final quality = primaryQuality(movie);
    final desktop = isDesktopPlatform;

    // Sozo-Desktop item sizing/styling on desktop; untouched on mobile.
    final width = desktop ? 152.0 : 118.0;
    final radius = desktop ? 12.0 : 10.0;

    final cover = Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        // foregroundDecoration paints the hover ring OVER the poster, so the
        // image stays full-bleed (no permanent inset gap) when not hovered.
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(
            color: desktop && _hover
                ? AppColors.textPrimary
                : Colors.transparent,
            width: 2.5,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Stack(
            fit: StackFit.expand,
            children: [
              HomeNetworkImage(
                url: movie.thumbnail,
                borderRadius: BorderRadius.zero,
                placeholderIcon: Icons.movie_outlined,
              ),
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SizedBox(
                  height: 40,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Color(0x99000000), Color(0x00000000)],
                      ),
                    ),
                  ),
                ),
              ),
              if (quality != null)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      quality,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    final content = SizedBox(
      width: width,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: desktop ? 6 : 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            cover,
            SizedBox(height: desktop ? 10 : 6),
            FixedTextLines(
              fontSize: desktop ? 15 : 11.5,
              lineHeight: desktop ? 1.3 : 1.25,
              lines: desktop ? 2 : 1,
              child: Text(
                movieTitle(movie),
                maxLines: desktop ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: desktop ? 15 : 11.5,
                  fontWeight: desktop ? FontWeight.w800 : FontWeight.w600,
                  height: desktop ? 1.3 : 1.25,
                ),
              ),
            ),
            SizedBox(height: desktop ? 6 : 0),
            FixedTextLines(
              fontSize: desktop ? 12.5 : 10,
              lineHeight: 1.3,
              child: movie.year == null
                  ? null
                  : Row(
                      children: [
                        if (desktop) ...[
                          const Icon(
                            Icons.calendar_today_rounded,
                            size: 12,
                            color: AppColors.textHint,
                          ),
                          const SizedBox(width: 5),
                        ],
                        Text(
                          movie.year.toString(),
                          style: TextStyle(
                            color: desktop
                                ? AppColors.textHint
                                : AppColors.textSecondary,
                            fontSize: desktop ? 12.5 : 10,
                            fontWeight: desktop
                                ? FontWeight.w600
                                : FontWeight.w400,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );

    if (!desktop) {
      return HoverTap(onTap: _openDetail, child: content);
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: _openDetail,
        child: AnimatedScale(
          scale: _hover ? 1.06 : 1.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: content,
        ),
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
              padding: EdgeInsets.only(right: desktop ? 12 : 8),
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
