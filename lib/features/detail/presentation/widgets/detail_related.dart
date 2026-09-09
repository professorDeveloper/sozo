import 'package:easy_localization/easy_localization.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/detail/domain/entities/detail_args.dart';
import 'package:soplay/features/detail/domain/entities/related_entity.dart';
import 'package:soplay/features/detail/presentation/widgets/detail_empty_state.dart';
import 'package:soplay/core/widgets/poster_hero.dart';
import 'package:soplay/features/home/domain/entities/movie.dart';

class DetailRelatedSection extends StatelessWidget {
  const DetailRelatedSection({super.key, required this.related});
  final List<RelatedEntity> related;

  @override
  Widget build(BuildContext context) {
    if (related.isEmpty) {
      return DetailEmptyState(
        icon: Icons.movie_filter_outlined,
        message: 'detail.no_recommendations'.tr(),
      );
    }

    final items = related.length > 30 ? related.sublist(0, 30) : related;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: responsiveGridDelegate(
          mobileCrossAxisCount: 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 14,
          childAspectRatio: 0.66,
        ),
        itemCount: items.length,
        itemBuilder: (_, i) => _RelatedCard(item: items[i]),
      ),
    );
  }
}

class _RelatedCard extends StatelessWidget {
  const _RelatedCard({required this.item});
  final RelatedEntity item;

  /// A [MovieEntity] standing in for what the next page already knows.
  ///
  /// Not decoration: a hero tag alone is INERT without it. The no-preview
  /// branch of the detail page renders `DetailSkeleton`, which contains no
  /// `PosterHero`, so the flight would have no destination and Hero would
  /// silently do nothing. Every field below is one this card already holds and
  /// already drew, so the next page opens with its poster, title and year
  /// correct instead of shimmering over facts it was handed.
  MovieEntity get _preview => MovieEntity(
    externalId: item.externalId,
    title: item.title,
    description: item.description,
    slug: item.slug,
    url: item.contentUrl,
    provider: item.provider,
    thumbnail: item.thumbnail,
    year: item.year,
    rating: item.rating,
    qualities: item.qualities,
    category: item.category,
  );

  /// Keyed on the content url rather than a grid position.
  ///
  /// This grid is inside a detail page that itself carries a hero — but a
  /// different one, since a title never lists itself as related. Two heroes
  /// with one tag on screen is a hard assertion, and the url is what
  /// guarantees they differ.
  String get _heroTag => 'related:${item.contentUrl}';

  @override
  Widget build(BuildContext context) {
    return HoverTap(
      onTap: () {
        if (item.contentUrl.isNotEmpty) {
          context.push(
            '/detail',
            // Related items belong to the SAME source as the open detail — pass
            // it so the right provider resolves them (not the app's "current").
            extra: DetailArgs(
              contentUrl: item.contentUrl,
              provider: item.provider,
              preview: _preview,
              heroTag: _heroTag,
            ),
          );
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: PosterHero(
                tag: _heroTag,
                url: item.thumbnail,
                fromRadius: 8,
                child: _RelatedThumbnail(url: item.thumbnail),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.title.trim().isNotEmpty ? item.title : 'detail.untitled'.tr(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
          // Always laid out, even with no year: the poster is the Expanded
          // child, so dropping this line made those cards' artwork taller than
          // their neighbours' and the titles no longer lined up across a row.
          Text(
            item.year?.toString() ?? '',
            maxLines: 1,
            style: const TextStyle(
              color: AppColors.textHint,
              fontSize: 11,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _RelatedThumbnail extends StatelessWidget {
  const _RelatedThumbnail({required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return Container(
        color: AppColors.surfaceVariant,
        child: const Center(
          child: Icon(
            Icons.movie_outlined,
            color: AppColors.textHint,
            size: 28,
          ),
        ),
      );
    }
    // Cached: these posters are the same ones the home rows already fetched,
    // and re-downloading them made every "Similar" strip repaint grey on the
    // way back to a title.
    return CachedNetworkImage(
      imageUrl: url!,
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 180),
      placeholder: (_, _) => ColoredBox(color: AppColors.surfaceVariant),
      errorWidget: (_, _, _) => Container(
        color: AppColors.surfaceVariant,
        child: const Center(
          child: Icon(
            Icons.movie_outlined,
            color: AppColors.textHint,
            size: 28,
          ),
        ),
      ),
    );
  }
}
