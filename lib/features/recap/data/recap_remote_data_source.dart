import 'package:dio/dio.dart';
import 'package:soplay/features/recap/domain/recap.dart';

/// `GET /contents/recap`, remembered for the session.
///
/// Only answers are remembered. A failed request says nothing about the
/// title, and "no recap" can change once the next episode's synopsis lands.
class RecapRemoteDataSource {
  RecapRemoteDataSource({required this.dio});

  final Dio dio;

  final Map<String, Recap> _cache = {};
  final Map<String, Future<Recap>> _inFlight = {};

  /// Throws [RecapUnavailable] when there is nothing to recap, and the
  /// underlying error for anything worth retrying.
  Future<Recap> load(RecapRequest request, {required String lang}) async {
    try {
      return await _cached(request, lang);
    } on RecapUnavailable {
      final fallback = request.fallbackEpisode;
      if (fallback == null) rethrow;
      return _cached(request.withEpisode(fallback), lang);
    }
  }

  Recap? peek(RecapRequest request, {required String lang}) =>
      _cache[_key(request, lang)];

  Future<Recap> _cached(RecapRequest request, String lang) {
    final key = _key(request, lang);
    final hit = _cache[key];
    if (hit != null) return Future.value(hit);
    final pending = _inFlight[key];
    if (pending != null) return pending;
    final future = () async {
      try {
        final recap = await _fetch(request, lang);
        _cache[key] = recap;
        return recap;
      } finally {
        _inFlight.remove(key);
      }
    }();
    _inFlight[key] = future;
    return future;
  }

  Future<Recap> _fetch(RecapRequest request, String lang) async {
    final Response<dynamic> response;
    try {
      response = await dio.get<dynamic>(
        '/contents/recap',
        queryParameters: {
          if (request.provider.isNotEmpty) 'provider': request.provider,
          'url': request.contentUrl,
          'episode': request.episode,
          if (request.label != null && request.label!.trim().isNotEmpty)
            'label': request.label!.trim(),
          if (request.season != null) 'season': request.season,
          if (request.tmdbId != null) 'tmdbId': request.tmdbId,
          if (request.anilistId != null) 'anilistId': request.anilistId,
          'lang': lang,
        },
      );
    } on DioException catch (e) {
      if (isUnavailable(e.response?.statusCode, e.response?.data)) {
        throw const RecapUnavailable();
      }
      rethrow;
    }
    final recap = Recap.fromJson(
      response.data,
      requestedEpisode: request.episode,
    );
    if (recap == null) throw const RecapUnavailable();
    return recap;
  }

  /// 404 `no_data` and 400 `bad_request` are the server's "there is no
  /// recap", as opposed to "try again".
  static bool isUnavailable(int? status, Object? body) {
    final reason = body is Map ? body['reason'] : null;
    return (status == 404 && reason == 'no_data') ||
        (status == 400 && reason == 'bad_request');
  }

  static String _key(RecapRequest r, String lang) => [
    r.provider,
    r.contentUrl,
    r.episode,
    r.label ?? '',
    r.season ?? '',
    r.tmdbId ?? '',
    r.anilistId ?? '',
    lang,
  ].join('|');
}
