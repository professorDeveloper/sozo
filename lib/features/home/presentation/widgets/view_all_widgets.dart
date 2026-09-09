import 'dart:ui';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/widgets/item_appear.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/detail/domain/entities/detail_args.dart';
import 'package:soplay/features/home/domain/entities/movie.dart';
import 'package:soplay/features/home/presentation/bloc/view_all/view_all_state.dart';
import 'package:soplay/features/home/presentation/widgets/home_shared_widgets.dart';
import 'package:soplay/features/home/presentation/widgets/home_ui_helpers.dart';
import 'package:soplay/core/widgets/poster_hero.dart';

class ViewAllAppBar extends StatelessWidget {
  const ViewAllAppBar({
    super.key,
    required this.title,
    required this.blurProgress,
  });

  final String title;
  final double blurProgress;

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final progress = blurProgress.clamp(0.0, 1.0);

    final content = Container(
      height: topPad + 56,
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.9 * progress),
        border: progress > 0.05
            ? Border(
                bottom: BorderSide(
                  color: Colors.white.withValues(alpha: 0.07 * progress),
                  width: 0.5,
                ),
              )
            : null,
      ),
      padding: EdgeInsetsDirectional.fromSTEB(4, topPad + 4, 16, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => context.pop(),
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 20,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
            ),
          ),
        ],
      ),
    );

    if (progress < 0.01) return content;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20 * progress, sigmaY: 20 * progress),
        child: content,
      ),
    );
  }
}

class ViewAllGrid extends StatelessWidget {
  const ViewAllGrid({
    super.key,
    required this.state,
    required this.scroll,
    required this.appBarH,
  });

  final ViewAllLoaded state;
  final ScrollController scroll;
  final double appBarH;

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    // A loaded-but-empty list used to render a bare page with only a title on
    // it, which reads as a screen that failed to finish loading.
    if (state.items.isEmpty) {
      return ViewAllEmptyView(topPadding: appBarH);
    }

    // Decided once for the whole grid, not per card: the caption block is a
    // fixed height so that posters in a row line up, and a card that dropped
    // the row on its own would sit 13px taller than its neighbours.
    //
    // Anime sources mostly carry no year at all, and the row was reserved
    // anyway — so every card in those grids ended with an empty strip and the
    // rows read as though something had failed to load between them.
    final showYear = state.items.any((m) => m.year != null);

    return CustomScrollView(
      controller: scroll,
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(12, appBarH + 12, 12, 0),
          sliver: SliverGrid(
            delegate: SliverChildBuilderDelegate(
              (context, index) => ItemAppear(
                index: index,
                columns: gridColumns(context),
                child: ViewAllMovieCard(
                  movie: state.items[index],
                  showYear: showYear,
                  // Position, not title: the same title can legitimately appear
                  // twice in a paged grid, and two heroes sharing one tag on
                  // screen is a hard assertion rather than a cosmetic bug.
                  heroTag: 'viewall:$index',
                ),
              ),
              childCount: state.items.length,
            ),
            gridDelegate: responsiveGridDelegate(
              mobileCrossAxisCount: 3,
              // 14 read as a gap between unrelated blocks rather than the
              // seam between two rows of one grid.
              mainAxisSpacing: 10,
              crossAxisSpacing: 8,
              childAspectRatio: 0.52,
            ),
          ),
        ),
        if (state.isLoadingMore)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
          ),
        SliverToBoxAdapter(child: SizedBox(height: bottomPad + 16)),
      ],
    );
  }
}


class ViewAllMovieCard extends StatelessWidget {
  const ViewAllMovieCard({
    super.key,
    required this.movie,
    this.heroTag,
    this.showYear = true,
  });

  final MovieEntity movie;

  /// Whether to reserve the year line. False when nothing in this grid has a
  /// year, which is most anime catalogues.
  final bool showYear;

  /// Ties this poster to the one on the detail page, so it flies rather than
  /// the page appearing from nothing. Null leaves the card as it was.
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    final quality = primaryQuality(movie);
    // The same value goes to the tile and to the shuttle: memCacheWidth is part
    // of the image-cache key, so a shuttle that measured its own width would
    // miss the cache this tile just filled and fly a blank frame.
    final decodeWidth = isDesktopPlatform
        ? null
        : (MediaQuery.sizeOf(context).width / 3 *
                  MediaQuery.devicePixelRatioOf(context))
              .round();

    return HoverTap(
      onTap: () {
        if (movie.url.isNotEmpty) {
          context.push(
            '/detail',
            extra: DetailArgs(
              contentUrl: movie.url,
              preview: movie,
              heroTag: heroTag,
            ),
          );
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  PosterHero(
                    tag: heroTag,
                    url: movie.thumbnail,
                    memCacheWidth: decodeWidth,
                    child: HomeNetworkImage(
                      url: movie.thumbnail,
                      borderRadius: BorderRadius.zero,
                      placeholderIcon: Icons.movie_outlined,
                      memCacheWidth: decodeWidth,
                    ),
                  ),
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: SizedBox(
                      height: 44,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Color(0xAA000000), Color(0x00000000)],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (quality != null)
                    Positioned(
                      top: 5,
                      right: 5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          quality,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
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
          const SizedBox(height: 5),
          FixedTextLines(
            fontSize: 11,
            lineHeight: 1.25,
            lines: 2,
            child: Text(
              movieTitle(movie),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
          ),
          if (showYear)
            FixedTextLines(
              fontSize: 10,
              lineHeight: 1.3,
              child: movie.year == null
                  ? null
                  : Text(
                      movie.year.toString(),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 10,
                        height: 1.3,
                      ),
                    ),
            ),
        ],
      ),
    );
  }
}


class ViewAllSkeleton extends StatelessWidget {
  const ViewAllSkeleton({super.key, required this.appBarH});

  final double appBarH;

  @override
  Widget build(BuildContext context) {
    return ShimmerWrapper(
      child: CustomScrollView(
        physics: const NeverScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(12, appBarH + 12, 12, 0),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate(
                (_, _) => const _SkeletonGridCard(),
                childCount: 15,
              ),
              gridDelegate: responsiveGridDelegate(
                mobileCrossAxisCount: 3,
                mainAxisSpacing: 10,
                crossAxisSpacing: 8,
                childAspectRatio: 0.52,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SkeletonGridCard extends StatelessWidget {
  const _SkeletonGridCard();

  @override
  Widget build(BuildContext context) {
    // Caption block reserves exactly what ViewAllMovieCard reserves, so the
    // poster does not resize when the real cards replace these.
    //
    // It also has to *look* like what replaces it. The title slot is two lines
    // of 11px text and used to be drawn as one 10px bar floating at the top of
    // a two-line box, with the second line left blank — so the skeleton read
    // as a one-line card and the grid jumped when the real titles wrapped. And
    // the year bar was 50px against a four-digit year that measures about 22.
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
        SizedBox(height: 5),
        FixedTextLines(
          fontSize: 11,
          lineHeight: 1.25,
          lines: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SkeletonLine(width: double.infinity),
              SizedBox(height: 4),
              // Short, because a title that wraps rarely fills its second line.
              _SkeletonLine(width: 46),
            ],
          ),
        ),
        FixedTextLines(
          fontSize: 10,
          lineHeight: 1.3,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: _SkeletonLine(width: 24),
          ),
        ),
      ],
    );
  }
}


/// One line of caption, at the weight a line of small text actually reads as.
/// A 10px bar against an 11px line looked like a heading; 8 sits where the
/// x-height of the real text does.
class _SkeletonLine extends StatelessWidget {
  const _SkeletonLine({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) =>
      HomeSkeletonBox(width: width, height: 8, radius: 2);
}

class ViewAllErrorView extends StatelessWidget {
  const ViewAllErrorView({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final reason = message.trim();
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
              child: const Icon(
                Icons.wifi_off_rounded,
                color: AppColors.textSecondary,
                size: 32,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'errors.network'.tr(),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'general.try_again'.tr(),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.35,
              ),
              textAlign: TextAlign.center,
            ),
            // The reason was passed in and then dropped on the floor, so every
            // failure looked like "you are offline". Matches HomeErrorView.
            if (reason.isNotEmpty) ...[
              const SizedBox(height: 10),
              SelectableText(
                reason,
                maxLines: 4,
                style: const TextStyle(
                  color: AppColors.textHint,
                  fontSize: 11,
                  height: 1.35,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: 156,
              height: 44,
              child: ElevatedButton(
                onPressed: onRetry,
                child: Text('general.retry'.tr()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Loaded, but the list came back with nothing in it.
class ViewAllEmptyView extends StatelessWidget {
  const ViewAllEmptyView({super.key, required this.topPadding});

  final double topPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: topPadding),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                ),
                child: const Icon(
                  Icons.movie_filter_outlined,
                  color: AppColors.textSecondary,
                  size: 32,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'home.list_empty_title'.tr(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'home.list_empty_subtitle'.tr(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
