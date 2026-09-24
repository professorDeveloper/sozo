import 'package:dio/dio.dart';

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
  });

  /// `movie` or `show`.
  final String kind;
  final int traktId;
  final String title;
  final int? year;
  final int? tmdbId;
  final String? imdbId;
  final String? slug;

  bool get isMovie => kind == 'movie';

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
    return TraktMedia(
      kind: kind,
      traktId: id,
      title: (m['title'] ?? '').toString(),
      year: (m['year'] as num?)?.toInt(),
      tmdbId: (ids['tmdb'] as num?)?.toInt(),
      imdbId: ids['imdb'] as String?,
      slug: ids['slug'] as String?,
    );
  }
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
      queryParameters: {'type': kind},
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
      queryParameters: {'query': query, 'limit': 12, 'years': ?year},
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
