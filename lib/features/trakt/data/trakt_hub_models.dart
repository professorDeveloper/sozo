import 'package:soplay/features/trakt/data/trakt_api.dart';

/// One episode as Trakt names it.
class TraktEpisodeRef {
  const TraktEpisodeRef({
    required this.season,
    required this.number,
    this.title,
    this.traktId,
    this.screenshot,
    this.overview,
  });

  final int season;
  final int number;
  final String? title;
  final int? traktId;
  final String? screenshot;
  final String? overview;

  /// "S2 · E5".
  String get code => 'S$season · E$number';

  static TraktEpisodeRef? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final season = (raw['season'] as num?)?.toInt();
    final number = (raw['number'] as num?)?.toInt();
    if (season == null || number == null) return null;
    final title = raw['title'] as String?;
    return TraktEpisodeRef(
      season: season,
      number: number,
      title: (title == null || title.isEmpty) ? null : title,
      traktId: ((raw['ids'] as Map?)?['trakt'] as num?)?.toInt(),
      screenshot: traktImage(
        (raw['images'] as Map?)?.cast<String, dynamic>(),
        'screenshot',
      ),
      overview: raw['overview'] as String?,
    );
  }
}

/// A row of any of the viewer's lists: a film, or a show — with an episode
/// where the row is about one.
///
/// One shape for all of them (watchlist, history, playback, calendar,
/// ratings, recommendations), because the screen draws them the same way and
/// only the line under the title differs.
class TraktEntry {
  const TraktEntry({
    required this.media,
    this.episode,
    this.at,
    this.progress,
    this.rating,
    this.id,
    this.aired,
    this.completed,
  });

  /// The film, or the show the episode belongs to.
  final TraktMedia media;
  final TraktEpisodeRef? episode;

  /// When it was watched, listed, rated, paused, or airs.
  final DateTime? at;

  /// How far into a paused playback, 0..100.
  final double? progress;

  /// The viewer's own rating, 1..10.
  final int? rating;

  /// The row's own id on Trakt — a playback or history entry — for removing
  /// exactly that row.
  final int? id;

  /// For a show in progress: episodes aired and watched.
  final int? aired;
  final int? completed;

  bool get isMovie => media.isMovie;

  double? get fraction => (aired == null || aired == 0 || completed == null)
      ? null
      : (completed! / aired!).clamp(0, 1).toDouble();

  TraktEntry copyWith({
    TraktEpisodeRef? episode,
    int? aired,
    int? completed,
    DateTime? at,
  }) => TraktEntry(
    media: media,
    episode: episode ?? this.episode,
    at: at ?? this.at,
    progress: progress,
    rating: rating,
    id: id,
    aired: aired ?? this.aired,
    completed: completed ?? this.completed,
  );

  /// A list row: `{type, movie | show [+ episode], <atKey>, …}`. Rows about a
  /// season or a person are skipped.
  static TraktEntry? fromRow(Map<String, dynamic> row, {String? atKey}) {
    final movie = row['movie'];
    final show = row['show'];
    TraktMedia? media;
    if (movie is Map) {
      media = TraktMedia.fromObject('movie', movie.cast<String, dynamic>());
    } else if (show is Map) {
      media = TraktMedia.fromObject('show', show.cast<String, dynamic>());
    }
    if (media == null) return null;
    final type = row['type'];
    if (type == 'season') return null;
    return TraktEntry(
      media: media,
      episode: TraktEpisodeRef.fromJson(row['episode']),
      at: atKey == null ? null : DateTime.tryParse('${row[atKey]}')?.toLocal(),
      progress: (row['progress'] as num?)?.toDouble(),
      rating: (row['rating'] as num?)?.toInt(),
      id: (row['id'] as num?)?.toInt(),
    );
  }
}

/// The numbers on the viewer's profile.
class TraktStats {
  const TraktStats({
    this.moviesWatched = 0,
    this.movieMinutes = 0,
    this.showsWatched = 0,
    this.episodesWatched = 0,
    this.episodeMinutes = 0,
    this.ratings = 0,
    this.distribution = const {},
  });

  final int moviesWatched;
  final int movieMinutes;
  final int showsWatched;
  final int episodesWatched;
  final int episodeMinutes;
  final int ratings;

  /// How many of each score, 1..10.
  final Map<int, int> distribution;

  int get hours => ((movieMinutes + episodeMinutes) / 60).round();

  static TraktStats fromJson(Map<String, dynamic> j) {
    int n(Object? section, String key) =>
        ((section as Map?)?[key] as num?)?.toInt() ?? 0;
    final dist = <int, int>{};
    final raw = (j['ratings'] as Map?)?['distribution'];
    if (raw is Map) {
      raw.forEach((k, v) {
        final score = int.tryParse('$k');
        if (score != null) dist[score] = (v as num?)?.toInt() ?? 0;
      });
    }
    return TraktStats(
      moviesWatched: n(j['movies'], 'watched'),
      movieMinutes: n(j['movies'], 'minutes'),
      showsWatched: n(j['shows'], 'watched'),
      episodesWatched: n(j['episodes'], 'watched'),
      episodeMinutes: n(j['episodes'], 'minutes'),
      ratings: n(j['ratings'], 'total'),
      distribution: dist,
    );
  }
}
