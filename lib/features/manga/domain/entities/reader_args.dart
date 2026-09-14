import 'package:soplay/features/detail/domain/entities/episode_entity.dart';

class ReaderArgs {
  final String title;
  final String provider;
  final String contentUrl;
  final String? thumbnail;

  final List<EpisodeEntity> chapters;
  final int initialChapterIndex;

  /// Null restores this chapter from history; zero explicitly starts over.
  final int? resumePage;

  const ReaderArgs({
    required this.title,
    required this.provider,
    required this.contentUrl,
    required this.chapters,
    this.thumbnail,
    this.initialChapterIndex = 0,
    this.resumePage,
  });
}
