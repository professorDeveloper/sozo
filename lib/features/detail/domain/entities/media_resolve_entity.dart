import 'extractor_config_entity.dart';
import 'subtitle_entity.dart';
import 'thumbnails_entity.dart';
import 'video_source_entity.dart';

class MediaResolveEntity {
  final String videoUrl;
  final String? type;
  final Map<String, String> headers;
  final List<VideoSourceEntity> videoSources;
  final List<String> languagesAvailable;
  final String? activeLang;
  final List<SubtitleEntity> subtitles;
  final ThumbnailsEntity? thumbnails;
  final ExtractorConfigEntity? extractor;

  /// A live broadcast (a TV channel) rather than a file: no seek bar, no
  /// ±10 s, and a dropped stream reconnects instead of ending.
  final bool live;

  const MediaResolveEntity({
    required this.videoUrl,
    required this.headers,
    this.type,
    this.videoSources = const [],
    this.languagesAvailable = const [],
    this.activeLang,
    this.subtitles = const [],
    this.thumbnails,
    this.extractor,
    this.live = false,
  });
}
