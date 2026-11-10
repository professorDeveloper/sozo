import 'episode_entity.dart';
import 'source_notice.dart';
import 'thumbnails_entity.dart';
import 'video_source_entity.dart';

class PlaybackEntity {
  final String provider;
  final String contentUrl;
  final bool isSerial;
  final List<EpisodeEntity> episodes;
  final List<VideoSourceEntity> videoSources;
  final String? playerSrc;
  final String? type;
  final Map<String, String> headers;
  final ThumbnailsEntity? thumbnails;
  final int page;
  final int size;
  final int total;
  final int totalPages;
  final String sort;

  /// Whether the source says this title can be played at all.
  ///
  /// Defaults to true: a source that says nothing is a source with nothing
  /// wrong, and every host but the backend's own providers says nothing.
  final bool playable;

  /// Why, when it cannot — or why the page is the wrong one to play from.
  /// Null when the source raised nothing.
  final SourceNotice? notice;

  const PlaybackEntity({
    required this.provider,
    required this.contentUrl,
    required this.isSerial,
    required this.episodes,
    required this.videoSources,
    required this.playerSrc,
    required this.headers,
    this.type,
    this.thumbnails,
    this.page = 1,
    this.size = 100,
    this.total = 0,
    this.totalPages = 1,
    this.sort = 'asc',
    this.playable = true,
    this.notice,
  });
}
