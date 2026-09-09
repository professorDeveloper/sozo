import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:soplay/core/network/dio_client.dart';
import 'package:soplay/core/trailer/trailer_query.dart';

/// Finds the YouTube id of a trailer for a title the catalogue never named.
///
/// `GET /contents/trailer?title=&year=&type=` searches TMDB by name on the
/// server and answers `{ "trailer": { "youtubeId": … } }` when the match is
/// convincing, `{ "trailer": null }` when it is not. The matching runs there
/// because that is where the catalogue and its API key are, and because a
/// wrong match is worse than no trailer — the server refuses a weak one rather
/// than handing back its best guess.
///
/// The id it returns goes to `TrailerService.resolve` exactly like a TMDB id
/// does, so a provider found by name and a provider that carried its own id
/// end up on the same path.
class TrailerTitleLookup {
  TrailerTitleLookup({Dio? dio}) : _dio = dio ?? DioClient.instance;

  final Dio _dio;

  /// The endpoint rejects anything shorter, and one letter would match half
  /// the catalogue anyway.
  static const int minTitleLength = 2;

  /// Answers, keyed by title. Holds nulls as answers in their own right: most
  /// titles on a scraper have no trailer, and without remembering that, every
  /// page that opens the button and the header preview asks again for a name
  /// TMDB has already said it does not know.
  ///
  /// Bounded like the id cache in `TrailerService`, and for the same reason —
  /// a long browsing session touches many titles. Unlike that cache it has no
  /// freshness window: what expires there is a signed stream URL, while which
  /// video is a film's trailer does not change during a session.
  static const int maxCacheEntries = 60;
  final Map<String, String?> _cache = {};

  /// Lookups that have been asked for but not yet answered.
  ///
  /// The button asks as soon as the page opens and the header preview asks a
  /// couple of seconds later, so on a slow connection the second question
  /// arrives while the first is still out. Both wait on the one request.
  final Map<String, Future<String?>> _inFlight = {};

  /// The trailer's YouTube id for [query], or null when there is none.
  Future<String?> youtubeIdFor(TrailerQuery query) {
    final title = query.title.trim();
    if (title.length < minTitleLength) return Future.value(null);

    final key = _keyFor(query, title);
    if (_cache.containsKey(key)) return Future.value(_cache[key]);

    final pending = _inFlight[key];
    if (pending != null) return pending;

    final request = _ask(query, title, key);
    _inFlight[key] = request;
    unawaited(request.whenComplete(() => _inFlight.remove(key)));
    return request;
  }

  Future<String?> _ask(TrailerQuery query, String title, String key) async {
    try {
      final response = await _dio.get<dynamic>(
        '/contents/trailer',
        queryParameters: {
          'title': title,
          if (query.year != null) 'year': query.year,
          'type': query.isSerial ? 'tv' : 'movie',
        },
      );
      final id = youtubeIdFrom(response.data);
      _remember(key, id);
      return id;
    } catch (e) {
      // Deliberately not remembered. A dropped connection is not evidence that
      // this title has no trailer, and since the cache has no expiry, caching
      // it would mean one bad moment costs the title its trailer until the app
      // is restarted. A genuine `{"trailer": null}` above is remembered.
      debugPrint('TrailerTitleLookup: no answer for "$title" ($e)');
      return null;
    }
  }

  /// `trailer.youtubeId` out of the response body, defended at every step.
  ///
  /// The body is null-carrying by design and a gateway in front of it can
  /// answer with an error page instead of JSON. Anything that is not the shape
  /// above has to read as "no trailer", because the alternative is a cast
  /// error thrown out of a detail page that was only decorating a header.
  @visibleForTesting
  static String? youtubeIdFrom(Object? body) {
    if (body is! Map) return null;
    final trailer = body['trailer'];
    if (trailer is! Map) return null;
    final id = trailer['youtubeId'];
    if (id is! String) return null;
    final trimmed = id.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  void _remember(String key, String? id) {
    if (_cache.length >= maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = id;
  }

  /// Case and stray whitespace are not different titles — providers write the
  /// same name with a double space or in title case, and the server normalises
  /// them into the same search either way.
  static String _keyFor(TrailerQuery query, String title) {
    final name = title.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    return '${query.isSerial ? 'tv' : 'movie'}|${query.year ?? ''}|$name';
  }

  void clear() => _cache.clear();
}
