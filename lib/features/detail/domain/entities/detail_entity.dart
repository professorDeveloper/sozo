import 'package:soplay/core/trailer/trailer_query.dart';

import 'cast_entity.dart';
import 'screenshot_entity.dart';
import 'related_entity.dart';

class DetailEntity {
  final String provider;
  final String contentId;
  final String contentUrl;
  final String title;
  final String description;
  final String? thumbnail;
  final int? year;
  final String? duration;
  final String? country;
  final String? director;
  final List<String> genres;
  final List<CastEntity> cast;
  final int likes;
  final int dislikes;
  final bool isSerial;
  final bool? isFavorited;
  final List<ScreenshotEntity> screenshots;
  final List<RelatedEntity> related;

  /// The YouTube id of this title's trailer, when the provider knows one.
  ///
  /// Null for most providers: only the TMDB-backed ones carry it, because
  /// only they have a catalogue that maps a title to an official video. It is
  /// the ID rather than a URL because the app resolves it to a direct stream
  /// and plays it in its own player — a link would mean handing somebody to
  /// YouTube's app, with its ads and its own fullscreen, from inside ours.
  final String? trailerYoutubeId;

  const DetailEntity({
    required this.provider,
    required this.contentId,
    required this.contentUrl,
    required this.title,
    required this.description,
    required this.thumbnail,
    required this.year,
    required this.duration,
    required this.country,
    required this.director,
    required this.genres,
    required this.cast,
    required this.likes,
    required this.dislikes,
    required this.isSerial,
    required this.isFavorited,
    required this.screenshots,
    required this.related,
    this.trailerYoutubeId,
  });

  /// What the trailer lookup has to go on for this title.
  ///
  /// Built here so the button and the header preview cannot assemble it
  /// differently: they ask with one value, and the service answers both from
  /// one lookup. [trailerYoutubeId] rides along, so a provider that already
  /// knows the video never triggers a search for its name.
  TrailerQuery get trailerQuery => TrailerQuery(
        youtubeId: trailerYoutubeId,
        title: title,
        year: year,
        isSerial: isSerial,
      );
}
