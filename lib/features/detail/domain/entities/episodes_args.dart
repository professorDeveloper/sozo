import 'episode_entity.dart';

class EpisodesArgs {
  final String title;
  final String contentUrl;
  final String provider;
  final String? thumbnail;
  final List<EpisodeEntity> episodes;
  final Map<String, String> headers;
  final int page;
  final int size;
  final int total;
  final int totalPages;

  /// Opened from Continue Watching: play the episode history points at
  /// instead of stopping on the list.
  ///
  /// The detail page was handed the episode to resume and dropped it, so the
  /// one-tap "continue" from the home rail landed on a list of every episode
  /// and made the viewer find their place a second time.
  final bool resumeFromHistory;

  /// The list is the copy saved with the downloads: only what is on disk can
  /// be played or read.
  final bool offline;

  /// The episode a new-release tap is about: the list scrolls to it and
  /// marks it.
  final int? focusEpisode;

  const EpisodesArgs({
    required this.title,
    required this.episodes,
    this.contentUrl = '',
    this.provider = '',
    this.thumbnail,
    this.headers = const {},
    this.page = 1,
    this.size = 100,
    this.total = 0,
    this.totalPages = 1,
    this.resumeFromHistory = false,
    this.offline = false,
    this.focusEpisode,
  });
}
