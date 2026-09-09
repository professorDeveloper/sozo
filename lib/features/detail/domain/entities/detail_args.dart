import 'package:soplay/features/home/domain/entities/movie.dart';

class DetailArgs {
  final String contentUrl;
  final MovieEntity? preview;
  final bool autoPlay;
  final int? resumeEpisodeIndex;
  final String? provider;

  /// Ties the poster on the page you came FROM to the poster on this one, so
  /// the image flies between them instead of the detail page appearing from
  /// nothing.
  ///
  /// Passed in rather than derived from the content url, because the same
  /// title legitimately appears in several rows of the home page at once —
  /// "Trending" and "Popular" often share half their contents — and two Heroes
  /// with one tag on screen together is a hard assertion, not a cosmetic bug.
  /// The caller knows which of its posters was tapped; nothing else does.
  ///
  /// Null means no flight, which is the correct behaviour for a detail page
  /// opened from search, a deeplink or the player.
  final String? heroTag;

  const DetailArgs({
    required this.contentUrl,
    this.preview,
    this.autoPlay = false,
    this.resumeEpisodeIndex,
    this.provider,
    this.heroTag,
  });
}
