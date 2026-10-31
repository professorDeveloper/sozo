import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:soplay/core/matching/title_match.dart';
import 'package:soplay/features/anilist/domain/entities/anilist_entities.dart';

/// A TMDB title the relations tab can stand on.
@immutable
class TmdbTitle {
  const TmdbTitle({
    required this.id,
    required this.isTv,
    required this.title,
    this.year,
    this.isAnime = false,
  });

  final int id;
  final bool isTv;
  final String title;
  final int? year;

  /// Japanese animation: AniList knows its sequels and side stories far
  /// better than TMDB's "recommended", so the tab asks AniList for it.
  final bool isAnime;
}

/// What comes with a film or a series that is not anime: the rest of its
/// franchise and what TMDB recommends after it.
///
/// AniList is where relations came from, and it knows only anime and manga.
/// A title search there for "Grey's Anatomy" either found nothing or found
/// whichever anime shared a word with it, and the tab showed that. TMDB is
/// asked through the backend's read-only proxy, which carries the token.
class TmdbRelations {
  TmdbRelations(this._dio);

  final Dio _dio;

  static const _poster = 'https://image.tmdb.org/t/p/w342';

  /// Relation types this source produces, ordered as they are shown.
  static const collection = 'TMDB_COLLECTION';
  static const recommended = 'TMDB_RECOMMENDED';

  /// The TMDB title [title] is, or null when nothing matches well enough to
  /// trust: a wrong show's recommendations are worse than none.
  Future<TmdbTitle?> find(String title, {int? year, bool? isSerial}) async {
    final query = title.trim();
    if (query.isEmpty) return null;
    final data = await _get('/tmdb/search/multi', {'query': query});
    final rows = [
      for (final r in _results(data))
        if (r['media_type'] == 'tv' || r['media_type'] == 'movie')
          if (isSerial == null || (r['media_type'] == 'tv') == isSerial) r,
    ];
    final best = TitleMatch.best(
      rows,
      query: query,
      titleOf: _titleOf,
      queryYear: year,
      yearOf: _yearOf,
    );
    if (best == null || !best.$2.isTrustworthy) return null;
    return _tmdbTitle(best.$1);
  }

  /// The relations of [title]: its franchise first, then recommendations.
  Future<List<AnilistRelation>> relationsOf(TmdbTitle title) async {
    final kind = title.isTv ? 'tv' : 'movie';
    final out = <AnilistRelation>[];
    if (!title.isTv) {
      final movie = await _get('/tmdb/movie/${title.id}', const {});
      final set = movie['belongs_to_collection'];
      final setId = set is Map ? (set['id'] as num?)?.toInt() : null;
      if (setId != null) {
        final parts =
            _results(
                await _get('/tmdb/collection/$setId', const {}),
                key: 'parts',
              ).where((p) => (p['id'] as num?)?.toInt() != title.id).toList()
              ..sort(
                (a, b) => '${a['release_date'] ?? ''}'.compareTo(
                  '${b['release_date'] ?? ''}',
                ),
              );
        out.addAll(parts.map((p) => _relation(p, collection, isTv: false)));
      }
    }
    final recs = _results(
      await _get('/tmdb/$kind/${title.id}/recommendations', const {}),
    );
    final seen = {for (final r in out) r.id};
    for (final r in recs.take(20)) {
      final rel = _relation(r, recommended, isTv: title.isTv);
      if (seen.add(rel.id)) out.add(rel);
    }
    return out;
  }

  Future<Map<String, dynamic>> _get(
    String path,
    Map<String, dynamic> query,
  ) async {
    final res = await _dio.get<dynamic>(path, queryParameters: query);
    final data = res.data;
    return data is Map<String, dynamic> ? data : const {};
  }

  static List<Map<String, dynamic>> _results(
    Map<String, dynamic> data, {
    String key = 'results',
  }) {
    final raw = data[key];
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().toList();
  }

  static String _titleOf(Map<String, dynamic> r) =>
      '${r['title'] ?? r['name'] ?? ''}';

  static int? _yearOf(Map<String, dynamic> r) {
    final date = '${r['release_date'] ?? r['first_air_date'] ?? ''}';
    return date.length >= 4 ? int.tryParse(date.substring(0, 4)) : null;
  }

  static TmdbTitle _tmdbTitle(Map<String, dynamic> r) {
    final genres = r['genre_ids'];
    final animation = genres is List && genres.contains(16);
    return TmdbTitle(
      id: (r['id'] as num).toInt(),
      isTv: r['media_type'] == 'tv',
      title: _titleOf(r),
      year: _yearOf(r),
      isAnime: animation && r['original_language'] == 'ja',
    );
  }

  static AnilistRelation _relation(
    Map<String, dynamic> r,
    String type, {
    required bool isTv,
  }) {
    final poster = r['poster_path'];
    final tv = r['media_type'] == null ? isTv : r['media_type'] == 'tv';
    return AnilistRelation(
      id: (r['id'] as num?)?.toInt() ?? 0,
      relationType: type,
      title: _titleOf(r),
      format: tv ? 'TV' : 'MOVIE',
      year: _yearOf(r),
      coverImage: poster is String && poster.isNotEmpty
          ? '$_poster$poster'
          : null,
    );
  }
}
