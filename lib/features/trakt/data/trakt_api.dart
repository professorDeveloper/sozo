import 'package:dio/dio.dart';

import 'package:soplay/features/trakt/data/trakt_hub_models.dart';

/// A film or a show on Trakt, as far as Sozo needs one.
class TraktMedia {
  const TraktMedia({
    required this.kind,
    required this.traktId,
    required this.title,
    this.year,
    this.tmdbId,
    this.imdbId,
    this.slug,
    this.poster,
    this.fanart,
    this.overview,
    this.rating,
    this.runtime,
    this.genres = const [],
    this.status,
    this.network,
    this.airedEpisodes,
  });

  /// `movie` or `show`.
  final String kind;
  final int traktId;
  final String title;
  final int? year;
  final int? tmdbId;
  final String? imdbId;
  final String? slug;

  /// Full https URLs, from `extended=images`.
  final String? poster;
  final String? fanart;

  final String? overview;

  /// Trakt's community rating, 0..10.
  final double? rating;
  final int? runtime;
  final List<String> genres;

  /// `released`, `returning series`, `ended`…
  final String? status;
  final String? network;
  final int? airedEpisodes;

  bool get isMovie => kind == 'movie';

  /// The TMDB page the app's catalogue opens this title from.
  String? get tmdbUrl => tmdbId == null
      ? null
      : 'https://www.themoviedb.org/${isMovie ? 'movie' : 'tv'}/$tmdbId';

  /// The object a scrobble or a sync call takes for this media.
  Map<String, dynamic> get ref => {
    'ids': {'trakt': traktId},
  };

  static TraktMedia? fromSearch(Map<String, dynamic> row) {
    final kind = row['type'];
    if (kind != 'movie' && kind != 'show') return null;
    final m = row[kind];
    if (m is! Map) return null;
    return fromObject(kind as String, m.cast<String, dynamic>());
  }

  static TraktMedia? fromObject(String kind, Map<String, dynamic> m) {
    final ids = (m['ids'] as Map?)?.cast<String, dynamic>() ?? const {};
    final id = (ids['trakt'] as num?)?.toInt();
    if (id == null) return null;
    final images = (m['images'] as Map?)?.cast<String, dynamic>();
    return TraktMedia(
      kind: kind,
      traktId: id,
      title: (m['title'] ?? '').toString(),
      year: (m['year'] as num?)?.toInt(),
      tmdbId: (ids['tmdb'] as num?)?.toInt(),
      imdbId: ids['imdb'] as String?,
      slug: ids['slug'] as String?,
      poster: traktImage(images, 'poster'),
      fanart: traktImage(images, 'fanart'),
      overview: m['overview'] as String?,
      rating: (m['rating'] as num?)?.toDouble(),
      runtime: (m['runtime'] as num?)?.toInt(),
      genres: [for (final g in (m['genres'] as List? ?? const [])) '$g'],
      status: m['status'] as String?,
      network: m['network'] as String?,
      airedEpisodes: (m['aired_episodes'] as num?)?.toInt(),
    );
  }
}

/// The first image of [kind] from an `extended=images` block. Trakt sends
/// them without a scheme ("media.trakt.tv/images/…").
String? traktImage(Map<String, dynamic>? images, String kind) {
  final list = images?[kind];
  if (list is! List || list.isEmpty) return null;
  final path = '${list.first}';
  if (path.isEmpty) return null;
  return path.startsWith('http') ? path : 'https://$path';
}

/// One season of a show: its number and how many episodes it has aired.
class TraktSeason {
  const TraktSeason(this.number, this.episodes);
  final int number;
  final int episodes;
}

/// Where the viewer is on a title.
class TraktState {
  const TraktState({
    this.watchedEpisodes = 0,
    this.airedEpisodes,
    this.movieWatched = false,
    this.inWatchlist = false,
    this.rating,
  });

  final int watchedEpisodes;
  final int? airedEpisodes;
  final bool movieWatched;
  final bool inWatchlist;

  /// 1..10, or null when unrated.
  final int? rating;
}

class TraktException implements Exception {
  const TraktException(this.message, [this.status]);
  final String message;
  final int? status;
  @override
  String toString() => message;
}

/// Trakt's API, called directly with the viewer's token: scrobbles and list
/// edits stay off Sozo's server. Every call takes the public client id the
/// account link carries, so no id is baked into the app.
class TraktApi {
  TraktApi({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://api.trakt.tv',
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
            ),
          );

  final Dio _dio;

  Options _auth(String clientId, String? token) => Options(
    headers: {
      'Content-Type': 'application/json',
      'trakt-api-version': '2',
      'trakt-api-key': clientId,
      if (token != null) 'Authorization': 'Bearer $token',
    },
  );

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      throw TraktException(
        status == 401
            ? 'Trakt session expired'
            : status == 429
            ? 'Trakt asked to slow down'
            : 'Trakt did not answer',
        status,
      );
    }
  }

  /// The title Trakt files under this TMDB id, of the given [kind].
  Future<TraktMedia?> byTmdb(
    int tmdbId,
    String kind, {
    required String clientId,
  }) => _guard(() async {
    final r = await _dio.get(
      '/search/tmdb/$tmdbId',
      queryParameters: {'type': kind, 'extended': 'images'},
      options: _auth(clientId, null),
    );
    for (final row in (r.data as List? ?? const [])) {
      final m = TraktMedia.fromSearch((row as Map).cast<String, dynamic>());
      if (m != null && m.kind == kind) return m;
    }
    return null;
  });

  /// Text search, films and shows together unless [kind] narrows it.
  Future<List<TraktMedia>> search(
    String query, {
    required String clientId,
    String kind = 'movie,show',
    int? year,
  }) => _guard(() async {
    final r = await _dio.get(
      '/search/$kind',
      queryParameters: {
        'query': query,
        'limit': 12,
        'years': ?year,
        'extended': 'images',
      },
      options: _auth(clientId, null),
    );
    return [
      for (final row in (r.data as List? ?? const []))
        ?TraktMedia.fromSearch((row as Map).cast<String, dynamic>()),
    ];
  });

  /// A show's regular seasons (specials, season 0, left out) with the number
  /// of episodes each has aired — what turns an absolute episode number into
  /// a season and an episode.
  Future<List<TraktSeason>> seasons(int showId, {required String clientId}) =>
      _guard(() async {
        final r = await _dio.get(
          '/shows/$showId/seasons',
          queryParameters: {'extended': 'full'},
          options: _auth(clientId, null),
        );
        return [
          for (final s in (r.data as List? ?? const []))
            if ((s['number'] as num?)?.toInt() case final n? when n > 0)
              TraktSeason(
                n,
                (s['aired_episodes'] as num?)?.toInt() ??
                    (s['episode_count'] as num?)?.toInt() ??
                    0,
              ),
        ];
      });

  /// start / pause / stop. Trakt marks the item watched on a stop at 80% or
  /// more, and shows "watching now" on the profile between start and stop.
  Future<void> scrobble(
    String action,
    Map<String, dynamic> body, {
    required String clientId,
    required String token,
  }) => _guard(() async {
    await _dio.post(
      '/scrobble/$action',
      data: body,
      options: _auth(clientId, token),
    );
  });

  /// Adds plays to the history outright — the fallback for a stop that did
  /// not land, and "mark watched" from the detail page.
  Future<void> addHistory(
    Map<String, dynamic> body, {
    required String clientId,
    required String token,
  }) => _guard(() async {
    await _dio.post(
      '/sync/history',
      data: body,
      options: _auth(clientId, token),
    );
  });

  Future<void> watchlist(
    TraktMedia media, {
    required bool add,
    required String clientId,
    required String token,
  }) => _guard(() async {
    await _dio.post(
      add ? '/sync/watchlist' : '/sync/watchlist/remove',
      data: {
        media.isMovie ? 'movies' : 'shows': [media.ref],
      },
      options: _auth(clientId, token),
    );
  });

  /// 1..10 to rate, 0 to remove the rating.
  Future<void> rate(
    TraktMedia media,
    int rating, {
    required String clientId,
    required String token,
  }) => _guard(() async {
    final key = media.isMovie ? 'movies' : 'shows';
    if (rating <= 0) {
      await _dio.post(
        '/sync/ratings/remove',
        data: {
          key: [media.ref],
        },
        options: _auth(clientId, token),
      );
    } else {
      await _dio.post(
        '/sync/ratings',
        data: {
          key: [
            {...media.ref, 'rating': rating},
          ],
        },
        options: _auth(clientId, token),
      );
    }
  });

  // ─── the viewer's Trakt, for the in-app hub ─────────────────────────────

  static const String _art = 'full,images';

  Future<List<TraktEntry>> _rows(
    String path, {
    required String clientId,
    String? token,
    String? atKey,
    Map<String, dynamic>? query,
  }) => _guard(() async {
    final r = await _dio.get(
      path,
      queryParameters: {'extended': _art, ...?query},
      options: _auth(clientId, token),
    );
    return [
      for (final row in (r.data as List? ?? const []))
        if (row is Map)
          ?TraktEntry.fromRow(row.cast<String, dynamic>(), atKey: atKey),
    ];
  });

  Future<TraktStats> stats(
    String slug, {
    required String clientId,
    required String token,
  }) => _guard(() async {
    final r = await _dio.get(
      '/users/$slug/stats',
      options: _auth(clientId, token),
    );
    return TraktStats.fromJson(
      (r.data as Map? ?? const {}).cast<String, dynamic>(),
    );
  });

  /// Paused playbacks — "continue watching" — newest first.
  Future<List<TraktEntry>> playback({
    required String clientId,
    required String token,
  }) async {
    final rows = await _rows(
      '/sync/playback',
      clientId: clientId,
      token: token,
      atKey: 'paused_at',
    );
    rows.sort((a, b) => (b.at ?? DateTime(0)).compareTo(a.at ?? DateTime(0)));
    return rows;
  }

  Future<void> removePlayback(
    int id, {
    required String clientId,
    required String token,
  }) => _guard(() async {
    await _dio.delete('/sync/playback/$id', options: _auth(clientId, token));
  });

  /// Shows the viewer has watched any of, most recently watched first.
  Future<List<TraktEntry>> watchedShows({
    required String clientId,
    required String token,
  }) async {
    final rows = await _rows(
      '/sync/watched/shows',
      clientId: clientId,
      token: token,
      atKey: 'last_watched_at',
      query: {'extended': 'noseasons,$_art'},
    );
    rows.sort((a, b) => (b.at ?? DateTime(0)).compareTo(a.at ?? DateTime(0)));
    return rows;
  }

  /// Where the viewer is on a show: aired, watched, and the next episode.
  Future<({int aired, int completed, TraktEpisodeRef? next})> showProgress(
    int showId, {
    required String clientId,
    required String token,
  }) => _guard(() async {
    final r = await _dio.get(
      '/shows/$showId/progress/watched',
      queryParameters: {
        'hidden': 'false',
        'specials': 'false',
        'extended': 'images',
      },
      options: _auth(clientId, token),
    );
    final j = (r.data as Map? ?? const {});
    return (
      aired: (j['aired'] as num?)?.toInt() ?? 0,
      completed: (j['completed'] as num?)?.toInt() ?? 0,
      next: TraktEpisodeRef.fromJson(j['next_episode']),
    );
  });

  /// Films and shows on the watchlist, newest first.
  Future<List<TraktEntry>> watchlistItems({
    required String clientId,
    required String token,
  }) async {
    final rows = await _rows(
      '/sync/watchlist',
      clientId: clientId,
      token: token,
      atKey: 'listed_at',
    );
    rows.sort((a, b) => (b.at ?? DateTime(0)).compareTo(a.at ?? DateTime(0)));
    return rows;
  }

  /// One page of the history, and whether there is another.
  Future<({List<TraktEntry> items, bool more})> history({
    required String clientId,
    required String token,
    int page = 1,
    int limit = 40,
  }) => _guard(() async {
    final r = await _dio.get(
      '/sync/history',
      queryParameters: {'extended': _art, 'page': page, 'limit': limit},
      options: _auth(clientId, token),
    );
    final pages =
        int.tryParse(r.headers.value('x-pagination-page-count') ?? '') ?? page;
    return (
      items: [
        for (final row in (r.data as List? ?? const []))
          if (row is Map)
            ?TraktEntry.fromRow(
              row.cast<String, dynamic>(),
              atKey: 'watched_at',
            ),
      ],
      more: page < pages,
    );
  });

  /// Takes plays out of the history by their history ids.
  Future<void> removeHistory(
    List<int> ids, {
    required String clientId,
    required String token,
  }) => _guard(() async {
    await _dio.post(
      '/sync/history/remove',
      data: {'ids': ids},
      options: _auth(clientId, token),
    );
  });

  /// Episodes of the viewer's shows airing from [start] for [days] days, and
  /// films of theirs coming out.
  Future<List<TraktEntry>> calendar(
    DateTime start,
    int days, {
    required String clientId,
    required String token,
  }) async {
    final d =
        '${start.year.toString().padLeft(4, '0')}-'
        '${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';
    final shows = await _rows(
      '/calendars/my/shows/$d/$days',
      clientId: clientId,
      token: token,
      atKey: 'first_aired',
    );
    List<TraktEntry> movies = const [];
    try {
      movies = await _rows(
        '/calendars/my/movies/$d/$days',
        clientId: clientId,
        token: token,
        atKey: 'released',
      );
    } catch (_) {}
    return [...shows, ...movies]
      ..sort((a, b) => (a.at ?? DateTime(0)).compareTo(b.at ?? DateTime(0)));
  }

  /// Films or shows Trakt suggests from what the viewer watched and rated.
  Future<List<TraktEntry>> recommendations(
    String kind, {
    required String clientId,
    required String token,
  }) => _guard(() async {
    final type = kind == 'movie' ? 'movies' : 'shows';
    final r = await _dio.get(
      '/recommendations/$type',
      queryParameters: {
        'extended': _art,
        'limit': 40,
        'ignore_collected': 'true',
        'ignore_watchlisted': 'true',
      },
      options: _auth(clientId, token),
    );
    return [
      for (final m in (r.data as List? ?? const []))
        if (m is Map)
          if (TraktMedia.fromObject(kind, m.cast<String, dynamic>())
              case final media?)
            TraktEntry(media: media),
    ];
  });

  /// "Not interested": the suggestion goes and does not come back.
  Future<void> hideRecommendation(
    TraktMedia media, {
    required String clientId,
    required String token,
  }) => _guard(() async {
    await _dio.delete(
      '/recommendations/${media.isMovie ? 'movies' : 'shows'}/${media.traktId}',
      options: _auth(clientId, token),
    );
  });

  /// Films and shows the viewer rated, highest first.
  Future<List<TraktEntry>> ratedItems({
    required String clientId,
    required String token,
  }) async {
    final movies = await _rows(
      '/sync/ratings/movies',
      clientId: clientId,
      token: token,
      atKey: 'rated_at',
    );
    final shows = await _rows(
      '/sync/ratings/shows',
      clientId: clientId,
      token: token,
      atKey: 'rated_at',
    );
    return [...movies, ...shows]..sort((a, b) {
      final byScore = (b.rating ?? 0).compareTo(a.rating ?? 0);
      return byScore != 0
          ? byScore
          : (b.at ?? DateTime(0)).compareTo(a.at ?? DateTime(0));
    });
  }

  /// What everyone is watching now (`trending`) or waiting for
  /// (`anticipated`). No account needed.
  Future<List<TraktEntry>> chart(
    String kind,
    String chart, {
    required String clientId,
  }) => _rows(
    '/${kind == 'movie' ? 'movies' : 'shows'}/$chart',
    clientId: clientId,
    query: {'limit': 30},
  );

  /// The viewer's state on one title: progress or watched, watchlist, rating.
  Future<TraktState> state(
    TraktMedia media, {
    required String clientId,
    required String token,
  }) => _guard(() async {
    final o = _auth(clientId, token);
    final key = media.isMovie ? 'movies' : 'shows';
    final id = media.traktId;
    final results = await Future.wait([
      media.isMovie
          ? _dio.get(
              '/sync/history/movies/$id',
              queryParameters: {'limit': 1},
              options: o,
            )
          : _dio.get('/shows/$id/progress/watched', options: o),
      _dio.get('/sync/watchlist/$key', options: o),
      _dio.get('/sync/ratings/$key', options: o),
    ]);
    bool has(dynamic list) => (list as List? ?? const []).any(
      (row) => ((row as Map)[media.kind] as Map?)?['ids']?['trakt'] == id,
    );
    int? ratingOf(dynamic list) {
      for (final row in (list as List? ?? const [])) {
        if (((row as Map)[media.kind] as Map?)?['ids']?['trakt'] == id) {
          return (row['rating'] as num?)?.toInt();
        }
      }
      return null;
    }

    final first = results[0].data;
    return TraktState(
      movieWatched: media.isMovie && (first as List? ?? const []).isNotEmpty,
      watchedEpisodes: media.isMovie
          ? 0
          : ((first as Map?)?['completed'] as num?)?.toInt() ?? 0,
      airedEpisodes: media.isMovie
          ? null
          : ((first as Map?)?['aired'] as num?)?.toInt(),
      inWatchlist: has(results[1].data),
      rating: ratingOf(results[2].data),
    );
  });
}
