import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:soplay/features/mal/data/mal_constants.dart';
import 'package:soplay/features/mal/domain/entities/mal_entities.dart';

/// Talks to MyAnimeList directly from the device.
///
/// Its own Dio instance, not the app's: the shared client carries a Sozo bearer
/// token and a refresh interceptor, and pointing it at another host would send
/// the user's Sozo credentials to MAL on every call.
///
/// MAL is a REST API where AniList is GraphQL, and two details of it are easy
/// to get wrong: writes are `PATCH` with FORM encoding (JSON is rejected), and
/// the current list state is read from the ANIME endpoint with a
/// `my_list_status` field rather than from a list endpoint of its own.
class MalApi {
  MalApi({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: MalConstants.apiBase,
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 12),
              // 4xx must reach the caller as data, so a 404 ("not on the list")
              // can be told apart from a 401 ("token is dead").
              validateStatus: (code) => code != null && code < 500,
            ));

  final Dio _dio;

  static const String _tag = '[MAL]';

  Options _auth(String token, {Map<String, String>? headers}) => Options(
        headers: {'Authorization': 'Bearer $token', ...?headers},
      );

  /// The account behind [token].
  Future<MalViewer> viewer(String token) async {
    final res = await _dio.get(
      '/users/@me',
      queryParameters: {'fields': 'id,name,picture'},
      options: _auth(token),
    );
    final data = _ok(res, 'could not read the MyAnimeList account');
    return MalViewer(
      id: (data['id'] as num?)?.toInt() ?? 0,
      name: (data['name'] ?? '').toString(),
      avatarUrl: (data['picture'] ?? '') is String && '${data['picture']}'.isNotEmpty
          ? data['picture'] as String
          : null,
    );
  }

  /// Searches the catalogue.
  ///
  /// MAL rejects a query shorter than three characters outright, so those are
  /// answered with an empty list rather than a 400 the caller has to interpret.
  Future<List<MalAnime>> search(
    String query, {
    required String token,
    int limit = 10,
  }) async {
    final q = query.trim();
    if (q.length < 3) return const [];

    final res = await _dio.get(
      '/anime',
      queryParameters: {
        'q': q,
        'limit': limit,
        'fields': 'id,title,alternative_titles,num_episodes,main_picture',
      },
      options: _auth(token),
    );
    final data = _ok(res, 'MyAnimeList search failed');
    final nodes = data['data'];
    if (nodes is! List) return const [];
    return [
      for (final row in nodes)
        if (row is Map && row['node'] is Map)
          MalAnime.fromJson((row['node'] as Map).cast<String, dynamic>()),
    ];
  }

  /// The account's current position on [animeId].
  ///
  /// Returns a state with `status == null` when the anime is simply not on the
  /// list yet — which is the normal case for a first write, not an error.
  Future<MalEntryState?> entryState({
    required String token,
    required int animeId,
  }) async {
    final res = await _dio.get(
      '/anime/$animeId',
      queryParameters: {'fields': 'id,num_episodes,my_list_status'},
      options: _auth(token),
    );
    if (res.statusCode == 404) return null;
    final data = _ok(res, 'could not read the MyAnimeList entry');
    return MalEntryState.fromAnime(data);
  }

  /// The viewer's whole anime list.
  ///
  /// Fetched unfiltered and grouped by the caller rather than asked for once
  /// per status: five requests for what one returns, and the counts on a tab
  /// bar need every status anyway.
  ///
  /// Paged because MAL caps a page at 1000 and answers with a `paging.next`
  /// URL. The page cap is a safety net against a list nobody expected, not a
  /// real limit — 10,000 entries is far beyond any real account.
  Future<List<MalListEntry>> animeList(String token) async {
    final out = <MalListEntry>[];
    String? next;

    for (var page = 0; page < 10; page++) {
      final Response<dynamic> res;
      if (next == null) {
        res = await _dio.get(
          '/users/@me/animelist',
          queryParameters: {
            'fields': 'list_status,num_episodes,alternative_titles,main_picture',
            'limit': 1000,
            'sort': 'list_updated_at',
            'nsfw': 'true',
          },
          options: _auth(token),
        );
      } else {
        // The paging URL is absolute and already carries every parameter.
        res = await _dio.get(next, options: _auth(token));
      }

      final data = _ok(res, 'could not read your MyAnimeList');
      final rows = data['data'];
      if (rows is! List) break;
      for (final row in rows) {
        if (row is! Map) continue;
        final entry = MalListEntry.fromJson(row.cast<String, dynamic>());
        if (entry != null) out.add(entry);
      }

      final paging = (data['paging'] as Map?)?['next'];
      if (paging is! String || paging.isEmpty) break;
      next = paging;
    }

    return out;
  }

  /// Edits an entry: any of status, progress and score, and only those given.
  ///
  /// Null means "leave it alone" throughout. Sending a field MAL already holds
  /// the right value for is harmless; sending one the caller did not ask to
  /// change is how a status gets silently rewritten.
  Future<MalListEntry?> updateEntry({
    required String token,
    required MalAnime anime,
    String? status,
    int? episodes,
    int? score,
  }) async {
    if (status == null && episodes == null && score == null) return null;

    final res = await _dio.patch(
      '/anime/${anime.id}/my_list_status',
      data: {
        'status': ?status,
        'num_watched_episodes': ?episodes,
        'score': ?score,
      },
      options: _auth(
        token,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      ),
    );
    final data = _ok(res, 'could not update MyAnimeList');
    return MalListEntry(
      anime: anime,
      status: (data['status'] ?? status ?? MalStatus.watching).toString(),
      progress: (data['num_episodes_watched'] as num?)?.toInt() ?? episodes ?? 0,
      score: (data['score'] as num?)?.toInt() ?? score ?? 0,
      isRewatching: data['is_rewatching'] == true,
      updatedAt: DateTime.tryParse('${data['updated_at']}'),
    );
  }

  /// Removes the anime from the list entirely.
  ///
  /// MAL answers 404 when it was not on the list — treated as success, because
  /// the caller asked for it to be gone and it is.
  Future<void> deleteEntry({required String token, required int animeId}) async {
    final res = await _dio.delete(
      '/anime/$animeId/my_list_status',
      options: _auth(token),
    );
    final code = res.statusCode ?? 0;
    if (code == 200 || code == 404) return;
    _ok(res, 'could not remove it from MyAnimeList');
  }

  /// Edits the entry by id: any of status, episodes and score, only those
  /// given. What [updateEntry] does for a search hit, for a page that has
  /// the id and nothing else.
  Future<MalEntryState> updateListStatus({
    required String token,
    required int animeId,
    String? status,
    int? episodes,
    int? score,
    int? totalEpisodes,
  }) async {
    final res = await _dio.patch(
      '/anime/$animeId/my_list_status',
      data: {
        'status': ?status,
        'num_watched_episodes': ?episodes,
        'score': ?score,
      },
      options: _auth(
        token,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      ),
    );
    final data = _ok(res, 'could not update MyAnimeList');
    return MalEntryState(
      watchedEpisodes:
          (data['num_episodes_watched'] as num?)?.toInt() ?? episodes ?? 0,
      status: data['status'] as String? ?? status,
      totalEpisodes: totalEpisodes,
      isRewatching: data['is_rewatching'] == true,
      score: (data['score'] as num?)?.toInt() ?? score,
    );
  }

  /// Writes [episodes] watched, and optionally moves the entry's status.
  ///
  /// [status] is null when the entry should keep whatever status it has —
  /// sending one unconditionally is what would demote a rewatch or reopen a
  /// dropped show.
  Future<MalEntryState> updateProgress({
    required String token,
    required int animeId,
    required int episodes,
    String? status,
  }) async {
    final res = await _dio.patch(
      '/anime/$animeId/my_list_status',
      // Form encoding, not JSON: MAL answers a JSON body with 400.
      data: {
        'num_watched_episodes': episodes,
        'status': ?status,
      },
      options: _auth(
        token,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      ),
    );
    final data = _ok(res, 'could not update MyAnimeList');
    return MalEntryState(
      watchedEpisodes: (data['num_episodes_watched'] as num?)?.toInt() ?? episodes,
      status: data['status'] as String?,
      isRewatching: data['is_rewatching'] == true,
    );
  }

  /// Unwraps a response, turning MAL's error shapes into one exception type.
  Map<String, dynamic> _ok(Response<dynamic> res, String whenFailed) {
    final code = res.statusCode ?? 0;
    if (code == 401 || code == 403) {
      throw const MalException('MyAnimeList connection has expired');
    }
    if (code >= 400) {
      final detail = res.data is Map ? (res.data as Map)['message'] : null;
      if (kDebugMode) debugPrint('$_tag $code ${res.realUri} — ${res.data}');
      throw MalException(
        detail is String && detail.isNotEmpty ? detail : whenFailed,
      );
    }
    final data = res.data;
    if (data is! Map) throw MalException(whenFailed);
    return data.cast<String, dynamic>();
  }
}
