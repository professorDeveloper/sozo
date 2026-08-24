import 'package:dio/dio.dart';
import 'package:soplay/features/anilist/data/anilist_constants.dart';
import 'package:soplay/features/anilist/domain/entities/anilist_entities.dart';

/// Thin GraphQL transport for AniList.
///
/// Deliberately on its OWN Dio, not the app's: the app's client carries a Sozo
/// bearer token and a stack of interceptors (auth refresh, Cloudflare bypass)
/// that have no business firing at anilist.co — and sending our token to a third
/// party would be worse than pointless.
class AnilistApi {
  AnilistApi({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
              headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
              },
            ),
          );

  final Dio _dio;

  /// When the next request may be sent, after AniList answered 429.
  ///
  /// AniList's budget is small and enforced hard, and the calendar spends
  /// several requests per day tapped — flicking across the strip trips it.
  /// Failing fast until the window reopens beats firing a request that is
  /// certain to be rejected.
  DateTime? _throttledUntil;

  static const String _rateLimitMessage = 'AniList is rate limiting requests';

  /// AniList refusing everything, and the reason it gave.
  ///
  /// Separate from [_throttledUntil]: a rate limit is our fault and clears in
  /// seconds, an outage is theirs and lasts as long as it lasts. Keeping them
  /// apart means we replay AniList's own words instead of telling the user to
  /// slow down when slowing down cannot help.
  DateTime? _outageUntil;
  String? _outageMessage;
  static const Duration _outageBackoff = Duration(minutes: 5);

  static Duration _retryAfter(Response<dynamic>? response) {
    final headers = response?.headers;
    final retryAfter = int.tryParse(headers?.value('retry-after') ?? '');
    if (retryAfter != null && retryAfter > 0) {
      return Duration(seconds: retryAfter.clamp(1, 300));
    }
    final reset = int.tryParse(headers?.value('x-ratelimit-reset') ?? '');
    if (reset != null) {
      final left = reset - DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (left > 0) return Duration(seconds: left.clamp(1, 300));
    }
    return const Duration(seconds: 60);
  }

  /// The media selection every query shares.
  ///
  /// One constant rather than a copy per query: the entity parses these fields
  /// unconditionally, so a field added to search but forgotten in the library
  /// query shows up as a silently missing value rather than an error.
  static const String _mediaFields = '''
    id
    idMal
    episodes
    averageScore
    seasonYear
    format
    status
    siteUrl
    title { romaji english native }
    coverImage { large }
    bannerImage
    description(asHtml: false)
    isAdult
    nextAiringEpisode { episode airingAt }
  ''';

  /// The lean selection the airing calendar uses.
  ///
  /// A global day runs to a hundred-odd airings over several pages, and the
  /// heavy fields above — description most of all — cost a few hundred KB per
  /// day tapped for values the calendar never renders. Named next to
  /// [_mediaFields] rather than inlined so both selections stay visible
  /// together when a field is added.
  static const String _airingMediaFields = '''
    id
    episodes
    format
    status
    siteUrl
    title { romaji english native }
    coverImage { large }
    isAdult
  ''';

  /// Runs [query]. [token] is optional: search and media lookups are public,
  /// only the viewer's own list and any write need it.
  Future<Map<String, dynamic>> _run(
    String query, {
    Map<String, dynamic> variables = const {},
    String? token,
  }) async {
    final until = _throttledUntil;
    if (until != null && DateTime.now().isBefore(until)) {
      throw const AnilistException(_rateLimitMessage, rateLimited: true);
    }
    // While AniList is refusing everything there is nothing to gain by asking
    // again — and the calendar alone fires two requests per visit (the selected
    // day plus tomorrow's prefetch), every one of them a guaranteed failure.
    final outage = _outageUntil;
    if (outage != null && DateTime.now().isBefore(outage)) {
      throw AnilistException(_outageMessage ?? 'AniList is unavailable');
    }

    final Response<dynamic> response;
    try {
      response = await _dio.post(
        AnilistConstants.graphqlEndpoint,
        data: {'query': query, 'variables': variables},
        options: Options(
          headers: {if (token != null) 'Authorization': 'Bearer $token'},
        ),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 429) {
        _throttledUntil = DateTime.now().add(_retryAfter(e.response));
        throw const AnilistException(_rateLimitMessage, rateLimited: true);
      }
      // GraphQL errors normally arrive in a 200 body and are read below, but a
      // refusal comes back as a non-2xx — which Dio throws on, so the body was
      // discarded and the reason with it. When AniList disabled its API it
      // answered every query with 403 and "The AniList API has been temporarily
      // disabled due to severe stability issues", and every screen showed its
      // own generic "could not load" beside a Try again that could not work.
      final message = _graphqlError(e.response?.data);
      if (message != null) {
        // Back off only when the service is refusing everyone — 403, or a 5xx.
        // A 400 means we sent something wrong, and muting our own bug for five
        // minutes would hide it rather than fix it, so that one is reported and
        // the next call still goes out.
        final code = e.response?.statusCode ?? 0;
        if (code == 403 || code >= 500) {
          _outageUntil = DateTime.now().add(_outageBackoff);
          _outageMessage = message;
        }
        throw AnilistException(message);
      }
      rethrow;
    }
    _throttledUntil = null;
    _outageUntil = null;
    _outageMessage = null;

    final body = response.data;
    if (body is! Map) throw const AnilistException('Unexpected AniList reply');

    // GraphQL reports failures in a 200 body, so a non-throwing Dio call is not
    // the same as a successful query.
    final message = _graphqlError(body);
    if (message != null) throw AnilistException(message);

    final data = body['data'];
    if (data is! Map) throw const AnilistException('AniList returned no data');
    return data.cast<String, dynamic>();
  }

  /// The first message out of a GraphQL `errors` array, wherever it arrives —
  /// a 200 body or the body of a refusal. Null when the payload carries none.
  static String? _graphqlError(dynamic body) {
    if (body is! Map) return null;
    final errors = body['errors'];
    if (errors is! List || errors.isEmpty) return null;
    final first = errors.first;
    final message = first is Map ? first['message']?.toString() : null;
    return (message != null && message.isNotEmpty)
        ? message
        : 'AniList rejected the request';
  }

  /// Who the stored token belongs to. Also the cheapest way to tell whether a
  /// token is still valid — AniList tokens last about a year but can be revoked.
  Future<AnilistViewer> viewer(String token) async {
    const query = '''
      query {
        Viewer {
          id
          name
          avatar { large }
          siteUrl
        }
      }
    ''';
    final data = await _run(query, token: token);
    final v = data['Viewer'];
    if (v is! Map) throw const AnilistException('Not signed in to AniList');
    return AnilistViewer.fromJson(v.cast<String, dynamic>());
  }

  /// The viewer's anime list, every status in one call.
  ///
  /// AniList returns it grouped by status; flattening here keeps the grouping
  /// decision in the UI rather than baking one layout into the transport.
  Future<List<AnilistListEntry>> mediaList({
    required String token,
    required int userId,
  }) async {
    final query = '''
      query (\$userId: Int) {
        MediaListCollection(userId: \$userId, type: ANIME) {
          lists {
            entries {
              id
              status
              progress
              score(format: POINT_10)
              updatedAt
              media { $_mediaFields }
            }
          }
        }
      }
    ''';
    final data = await _run(query, variables: {'userId': userId}, token: token);

    final collection = data['MediaListCollection'];
    final lists = collection is Map ? collection['lists'] : null;
    if (lists is! List) return const [];

    // Custom lists make AniList repeat one entry under several list objects.
    // De-duped by entry id so a title on a custom list is not counted twice.
    final seen = <int>{};
    final out = <AnilistListEntry>[];
    for (final list in lists.whereType<Map>()) {
      final entries = list['entries'];
      if (entries is! List) continue;
      for (final raw in entries.whereType<Map>()) {
        final entry = AnilistListEntry.fromJson(raw.cast<String, dynamic>());
        if (seen.add(entry.id)) out.add(entry);
      }
    }
    return out;
  }

  /// A browse shelf: trending, popular, or a given season.
  ///
  /// Public, like search — discovery is the half of AniList that works without
  /// an account, and gating it behind one would hide the reason to make one.
  ///
  /// [season] and [seasonYear] travel together or not at all; AniList treats a
  /// season without its year as "this season of every year", which is not a
  /// shelf anybody wants.
  Future<List<AnilistMedia>> browse({
    String sort = 'TRENDING_DESC',
    String? season,
    int? seasonYear,
    String? status,
    int page = 1,
    int perPage = 30,
  }) async {
    final gql = '''
      query (\$sort: [MediaSort], \$season: MediaSeason, \$seasonYear: Int,
             \$status: MediaStatus, \$page: Int, \$perPage: Int) {
        Page(page: \$page, perPage: \$perPage) {
          media(
            type: ANIME
            sort: \$sort
            season: \$season
            seasonYear: \$seasonYear
            status: \$status
            isAdult: false
          ) {
            $_mediaFields
          }
        }
      }
    ''';

    final withSeason = season != null && seasonYear != null;
    final data = await _run(
      gql,
      variables: {
        'sort': [sort],
        'season': ?(withSeason ? season : null),
        'seasonYear': ?(withSeason ? seasonYear : null),
        'status': ?status,
        'page': page,
        'perPage': perPage,
      },
    );

    final pageData = data['Page'];
    final media = pageData is Map ? pageData['media'] : null;
    if (media is! List) return const [];
    return media
        .whereType<Map>()
        .map((e) => AnilistMedia.fromJson(e.cast<String, dynamic>()))
        .where((m) => !m.isAdult)
        .toList(growable: false);
  }

  /// Public title search — used to attach an AniList id to something the user
  /// is watching from a source that knows nothing about AniList.
  Future<List<AnilistMedia>> searchMedia(String query, {int perPage = 20}) async {
    if (query.trim().isEmpty) return const [];
    final gql = '''
      query (\$search: String, \$perPage: Int) {
        Page(page: 1, perPage: \$perPage) {
          media(search: \$search, type: ANIME, sort: SEARCH_MATCH) {
            $_mediaFields
          }
        }
      }
    ''';
    final data = await _run(
      gql,
      variables: {'search': query.trim(), 'perPage': perPage},
    );
    final page = data['Page'];
    final media = page is Map ? page['media'] : null;
    if (media is! List) return const [];
    return media
        .whereType<Map>()
        .map((e) => AnilistMedia.fromJson(e.cast<String, dynamic>()))
        .toList(growable: false);
  }

  /// The MyAnimeList id for an AniList media, or null when there is none.
  ///
  /// Exists so a title the user linked BY HAND reaches MyAnimeList too. That
  /// link is the only thing that works for a translated or transliterated
  /// source title — no search will ever match one — so without this lookup MAL
  /// would silently track nothing for exactly the titles that needed the manual
  /// link in the first place.
  ///
  /// Deliberately its own tiny query rather than a field on [entryState]: it is
  /// asked once per title, cached by the caller, and needs no token.
  Future<int?> malIdFor(int mediaId) async {
    if (mediaId <= 0) return null;
    final gql = '''
      query (\$id: Int) {
        Media(id: \$id, type: ANIME) { idMal }
      }
    ''';
    final data = await _run(gql, variables: {'id': mediaId});
    final media = data['Media'];
    if (media is! Map) return null;
    final idMal = (media['idMal'] as num?)?.toInt();
    return (idMal != null && idMal > 0) ? idMal : null;
  }

  /// Everything airing between [from] and [to].
  ///
  /// Paged rather than a single large request: a day of global airings runs to
  /// a few dozen entries and AniList caps perPage at 50, so asking for one page
  /// silently truncates the evening. The cap on pages is a safety net against a
  /// window someone widens later, not a real limit — a day never reaches it.
  Future<List<AnilistScheduledAiring>> airingSchedule({
    required DateTime from,
    required DateTime to,
    bool includeAdult = false,
  }) async {
    final gql = '''
      query (\$start: Int, \$end: Int, \$page: Int) {
        Page(page: \$page, perPage: 50) {
          pageInfo { hasNextPage }
          airingSchedules(
            airingAt_greater: \$start
            airingAt_lesser: \$end
            sort: TIME
          ) {
            episode
            airingAt
            media { $_airingMediaFields }
          }
        }
      }
    ''';

    // `airingAt_greater` is strictly greater, so the one-second nudge is what
    // keeps an episode airing exactly at midnight from falling between two
    // days — excluded from this one for equalling its start, and from the
    // previous one for that day's inclusive `airingAt_lesser`.
    final start = from.toUtc().millisecondsSinceEpoch ~/ 1000 - 1;
    final end = to.toUtc().millisecondsSinceEpoch ~/ 1000;
    final out = <AnilistScheduledAiring>[];

    for (var page = 1; page <= 10; page++) {
      final data = await _run(
        gql,
        variables: {'start': start, 'end': end, 'page': page},
      );
      final pageData = data['Page'];
      if (pageData is! Map) break;

      final schedules = pageData['airingSchedules'];
      if (schedules is List) {
        for (final raw in schedules.whereType<Map>()) {
          final airing =
              AnilistScheduledAiring.fromJson(raw.cast<String, dynamic>());
          if (airing == null) continue;
          if (!includeAdult && airing.media.isAdult) continue;
          out.add(airing);
        }
      }

      final info = pageData['pageInfo'];
      final hasNext = info is Map && info['hasNextPage'] == true;
      if (!hasNext) break;
    }
    return out;
  }

  /// The viewer's own entry for one title, or null if it is not on their list.
  ///
  /// Read before every automatic write so progress is never moved BACKWARDS:
  /// a rewatch, a second device, or a partly-watched episode would otherwise
  /// overwrite a higher number the account already holds.
  Future<AnilistEntryState?> entryState({
    required String token,
    required int mediaId,
  }) async {
    const query = '''
      query (\$mediaId: Int) {
        Media(id: \$mediaId, type: ANIME) {
          episodes
          mediaListEntry { progress status }
        }
      }
    ''';
    final data = await _run(query, variables: {'mediaId': mediaId}, token: token);
    final media = data['Media'];
    if (media is! Map) return null;
    final entry = media['mediaListEntry'];
    return AnilistEntryState(
      onList: entry is Map,
      progress: entry is Map ? (entry['progress'] as num?)?.toInt() ?? 0 : 0,
      status: entry is Map ? entry['status'] as String? : null,
      totalEpisodes: (media['episodes'] as num?)?.toInt(),
    );
  }

  /// Puts a title on the viewer's list, leaving an existing entry alone.
  ///
  /// SaveMediaListEntry is an UPSERT. Sending progress 0 and PLANNING for a
  /// media the viewer is already twelve episodes into would reset both — on
  /// their real account, with no undo. So this reads first and refuses to
  /// write over an entry that exists, and never sends progress at all: the
  /// caller's own "is it on the list" check can be stale or, worse, false
  /// simply because the library failed to load.
  ///
  /// Returns null when the title was already there.
  Future<AnilistSaveResult?> addToList({
    required String token,
    required int mediaId,
    AnilistStatus status = AnilistStatus.planning,
  }) async {
    final existing = await entryState(token: token, mediaId: mediaId);
    if (existing != null) return null;
    return saveProgress(token: token, mediaId: mediaId, status: status.value);
  }

  /// Takes a title off the viewer's list entirely.
  ///
  /// [entryId] is the LIST ENTRY id, not the media id — AniList deletes by the
  /// row, and passing a media id here silently deletes nothing (or somebody
  /// else's row, if it happens to collide).
  ///
  /// A missing entry counts as success: the caller wanted it gone, and it is.
  Future<void> deleteEntry({
    required String token,
    required int entryId,
  }) async {
    const mutation = '''
      mutation (\$id: Int) {
        DeleteMediaListEntry(id: \$id) {
          deleted
        }
      }
    ''';
    final data = await _run(
      mutation,
      variables: {'id': entryId},
      token: token,
    );
    final result = data['DeleteMediaListEntry'];
    if (result is Map && result['deleted'] == false) {
      throw const AnilistException('AniList did not remove the entry');
    }
  }

  /// Writes progress back to AniList.
  ///
  /// [progress] is an episode COUNT, not an index — AniList means "episodes
  /// finished", so passing a zero-based index silently reports one episode less
  /// than the viewer actually watched.
  ///
  /// Returns what AniList stored, which is not always what was sent: it clamps
  /// progress to the episode total and flips status to COMPLETED on the last
  /// episode. Echoing the server's answer keeps the UI from showing a number
  /// the account does not actually hold.
  Future<AnilistSaveResult> saveProgress({
    required String token,
    required int mediaId,
    // Optional so a status-only write leaves the viewer's position untouched.
    // The mutation omits the argument entirely rather than sending null, which
    // AniList would take as "set it to nothing".
    int? progress,
    String? status,
  }) async {
    const mutation = '''
      mutation (\$mediaId: Int, \$progress: Int, \$status: MediaListStatus) {
        SaveMediaListEntry(mediaId: \$mediaId, progress: \$progress, status: \$status) {
          id
          progress
          status
        }
      }
    ''';
    final data = await _run(
      mutation,
      variables: {
        'mediaId': mediaId,
        'progress': ?progress,
        'status': ?status,
      },
      token: token,
    );
    final saved = data['SaveMediaListEntry'];
    if (saved is! Map) {
      throw const AnilistException('AniList did not save the change');
    }
    return AnilistSaveResult(
      progress: (saved['progress'] as num?)?.toInt() ?? progress ?? 0,
      status: saved['status'] as String? ?? status ?? AnilistStatus.current.value,
    );
  }
}

/// What AniList actually stored after a write.
class AnilistSaveResult {
  const AnilistSaveResult({required this.progress, required this.status});
  final int progress;
  final String status;
}

/// The viewer's current position on one title, as AniList holds it.
class AnilistEntryState {
  const AnilistEntryState({
    required this.onList,
    required this.progress,
    this.status,
    this.totalEpisodes,
  });

  final bool onList;
  final int progress;
  final String? status;
  final int? totalEpisodes;
}

class AnilistException implements Exception {
  const AnilistException(this.message, {this.rateLimited = false});
  final String message;

  /// AniList refused on its request budget, not because anything is wrong.
  /// Callers can say "try again in a moment" rather than "it failed".
  final bool rateLimited;

  @override
  String toString() => message;
}
