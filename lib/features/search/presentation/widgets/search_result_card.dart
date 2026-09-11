import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/features/anilist/presentation/widgets/anilist_linked_badge.dart';
import 'package:soplay/features/home/domain/entities/movie.dart';
import 'package:soplay/core/presentation/widgets/kaizoku_badge.dart';
import 'package:soplay/core/presentation/widgets/kaizoku_media_card.dart';

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

    final card = Stack(
      children: [
        KaizokuMediaCard(
          title: movie.title,
          imageUrl: movie.thumbnail,
          subtitle: subtitle.isNotEmpty ? subtitle : null,
          ratio: KaizokuCardRatio.poster,
          tagText: movie.rating != null ? '★ ${movie.rating}' : null,
          badgeText: sourceCount > 1
              ? 'search.sources_n'.tr(args: ['$sourceCount'])
              : sourceLabel,
          badgeVariant: sourceCount > 1
              ? KaizokuBadgeVariant.primary
              : KaizokuBadgeVariant.glass,
          onTap: onTap,
        ),
        Positioned(
          top: 6,
          left: 6,
          child: AnilistLinkedBadge(
            contentUrl: movie.url,
            provider: provider,
          ),
        ),
      ],
    );

    return width == null ? card : SizedBox(width: width, child: card);
  }
}
