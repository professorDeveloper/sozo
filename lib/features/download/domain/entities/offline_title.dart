import 'package:soplay/features/detail/domain/entities/detail_entity.dart';
import 'package:soplay/features/detail/domain/entities/episode_entity.dart';
import 'package:soplay/features/detail/domain/entities/playback_entity.dart';
import 'package:soplay/features/download/domain/entities/download_item.dart';

/// What the app remembers about a title it has downloads for, so its page and
/// its episode list still open when the source cannot be reached.
class OfflineTitle {
  const OfflineTitle({
    required this.contentUrl,
    required this.provider,
    required this.title,
    required this.savedAt,
    this.providerName,
    this.description = '',
    this.thumbnail,
    this.year,
    this.duration,
    this.country,
    this.director,
    this.genres = const [],
    this.isSerial = false,
    this.episodes = const [],
    this.headers = const {},
  });

  /// A long run's list is kept whole up to here. Past it, the snapshot is only
  /// ever read offline, where the downloaded episodes are what matter.
  static const int maxEpisodes = 3000;

  final String contentUrl;
  final String provider;
  final String? providerName;
  final String title;
  final String description;
  final String? thumbnail;
  final int? year;
  final String? duration;
  final String? country;
  final String? director;
  final List<String> genres;
  final bool isSerial;
  final List<EpisodeEntity> episodes;
  final Map<String, String> headers;
  final int savedAt;

  String get groupKey => contentUrl;

  /// A snapshot good enough to open the page, built from the rows alone — for
  /// a title downloaded before snapshots existed, or queued by automation.
  factory OfflineTitle.fromItems(List<DownloadItem> items, {int? now}) {
    final lead = items.first;
    final ordered = [...items]
      ..sort((a, b) {
        final byNumber = (a.episodeNumber ?? 0).compareTo(b.episodeNumber ?? 0);
        if (byNumber != 0) return byNumber;
        return (a.chapterIndex ?? 0).compareTo(b.chapterIndex ?? 0);
      });
    final serial = items.any((i) => i.isSerial || i.isManga);
    return OfflineTitle(
      contentUrl: lead.contentUrl,
      provider: lead.provider,
      title: lead.title,
      thumbnail: lead.thumbnailUrl,
      isSerial: serial,
      episodes: [
        for (final item in ordered)
          if (serial)
            EpisodeEntity(
              episode: item.episodeNumber ?? 0,
              label: item.episodeLabel ?? '',
              mediaRef: item.chapterRef ?? '',
            ),
      ],
      savedAt: now ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  OfflineTitle withDetail(DetailEntity detail, {int? now}) => OfflineTitle(
    contentUrl: contentUrl,
    provider: provider,
    providerName: providerName,
    title: detail.title.isEmpty ? title : detail.title,
    description: detail.description,
    thumbnail: detail.thumbnail ?? thumbnail,
    year: detail.year,
    duration: detail.duration,
    country: detail.country,
    director: detail.director,
    genres: detail.genres,
    isSerial: detail.isSerial || isSerial,
    episodes: episodes,
    headers: headers,
    savedAt: now ?? DateTime.now().millisecondsSinceEpoch,
  );

  OfflineTitle withPlayback(PlaybackEntity playback, {int? now}) {
    final incoming = playback.episodes;
    // A later page of a long run is not the whole list; merged by number so
    // what was saved from page one is not thrown away by page two.
    final merged = playback.page <= 1 && playback.totalPages <= 1
        ? incoming
        : _mergeEpisodes(episodes, incoming);
    return OfflineTitle(
      contentUrl: contentUrl,
      provider: provider,
      providerName: providerName,
      title: title,
      description: description,
      thumbnail: thumbnail,
      year: year,
      duration: duration,
      country: country,
      director: director,
      genres: genres,
      isSerial: playback.isSerial || isSerial,
      episodes: merged.length > maxEpisodes
          ? merged.sublist(0, maxEpisodes)
          : merged,
      headers: playback.headers.isEmpty ? headers : playback.headers,
      savedAt: now ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  OfflineTitle relinked({
    required String contentUrl,
    required String provider,
    String? providerName,
    List<EpisodeEntity>? episodes,
  }) => OfflineTitle(
    contentUrl: contentUrl,
    provider: provider,
    providerName: providerName,
    title: title,
    description: description,
    thumbnail: thumbnail,
    year: year,
    duration: duration,
    country: country,
    director: director,
    genres: genres,
    isSerial: isSerial,
    episodes: episodes ?? this.episodes,
    headers: const {},
    savedAt: DateTime.now().millisecondsSinceEpoch,
  );

  DetailEntity toDetail() => DetailEntity(
    provider: provider,
    contentId: contentUrl,
    contentUrl: contentUrl,
    title: title,
    description: description,
    thumbnail: thumbnail,
    year: year,
    duration: duration,
    country: country,
    director: director,
    genres: genres,
    cast: const [],
    likes: 0,
    dislikes: 0,
    isSerial: isSerial,
    isFavorited: null,
    screenshots: const [],
    related: const [],
  );

  PlaybackEntity toPlayback() => PlaybackEntity(
    provider: provider,
    contentUrl: contentUrl,
    isSerial: isSerial,
    episodes: episodes,
    videoSources: const [],
    playerSrc: null,
    headers: headers,
    // One page holding everything, so nothing on the list tries to fetch
    // another.
    size: episodes.isEmpty ? 100 : episodes.length,
    total: episodes.length,
  );

  static List<EpisodeEntity> _mergeEpisodes(
    List<EpisodeEntity> saved,
    List<EpisodeEntity> incoming,
  ) {
    final byKey = <String, EpisodeEntity>{
      for (final e in saved) _episodeKey(e): e,
    };
    for (final e in incoming) {
      byKey[_episodeKey(e)] = e;
    }
    return byKey.values.toList()
      ..sort((a, b) => a.episode.compareTo(b.episode));
  }

  static String _episodeKey(EpisodeEntity e) =>
      e.episode > 0 ? '#${e.episode}' : 'ref:${e.mediaRef}';
}
