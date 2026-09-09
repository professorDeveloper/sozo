import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/network/user_agent.dart';
import 'package:soplay/features/anilist/data/anilist_service.dart';
import 'package:soplay/features/anilist/data/anilist_tracker.dart';

/// One opening or ending, as AniSkip describes it.
class SkipInterval {
  const SkipInterval({
    required this.type,
    required this.start,
    required this.end,
  });

  /// `op` or `ed`.
  final String type;
  final Duration start;
  final Duration end;

  bool contains(Duration position) => position >= start && position < end;

  /// True for intervals so short they are almost certainly a bad submission.
  ///
  /// AniSkip is crowd-sourced and the occasional entry is a two-second stub.
  /// Offering a Skip button that jumps two seconds forward looks broken.
  bool get isUsable => end - start >= const Duration(seconds: 5);
}

/// Skip-times lookup for anime openings and endings.
///
/// AniSkip is keyed on MyAnimeList ids, which this app does not store — but it
/// already knows how to turn a local title into an AniList id, and AniList
/// carries `idMal` for the same entry. That chain is reused here rather than
/// rebuilt: the manual link the user made by hand comes first, because it
/// exists precisely for the titles no search could match — an Uzbek dub, a
/// transliteration, a source's own naming — and re-running the search that
/// already failed would quietly skip nothing for exactly those.
///
/// Nothing here requires a connected account. The AniList queries involved are
/// unauthenticated, so skip times work for a viewer who has never linked
/// anything, which is the majority.
///
/// Results are memoised per title and per episode for the process lifetime.
/// A season is dozens of episodes off one id lookup, and the intervals for an
/// episode never change while it is being watched.
class AniSkipService {
  AniSkipService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 8),
                headers: {'User-Agent': kSozoUserAgent},
                validateStatus: (_) => true,
              ),
            );

  static const String _tag = '[aniskip]';
  static const String _base = 'https://api.aniskip.com/v2/skip-times';

  final Dio _dio;

  /// provider|contentUrl -> MAL id, or null when the title has no match.
  final Map<String, int?> _malIds = {};

  /// malId|episode -> intervals.
  final Map<String, List<SkipInterval>> _episodes = {};

  /// Skip times for one episode, or an empty list when there are none.
  ///
  /// [episodeLength] is passed straight through to AniSkip, which uses it to
  /// reject submissions recorded against a different cut of the episode. Zero
  /// means "do not check", which is the right value while the player is still
  /// working out the duration.
  Future<List<SkipInterval>> intervalsFor({
    required String provider,
    required String contentUrl,
    required String title,
    required int episodeNumber,
    Duration episodeLength = Duration.zero,
  }) async {
    if (episodeNumber <= 0 || contentUrl.trim().isEmpty) return const [];

    final malId = await _malIdFor(
      provider: provider,
      contentUrl: contentUrl,
      title: title,
    );
    if (malId == null) return const [];

    final cacheKey = '$malId|$episodeNumber';
    final cached = _episodes[cacheKey];
    if (cached != null) return cached;

    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '$_base/$malId/$episodeNumber',
        queryParameters: {
          'types[]': ['op', 'ed'],
          'episodeLength': episodeLength.inSeconds,
        },
        options: Options(extra: const {'skipAuthInterceptor': true}),
      );
      if (res.statusCode != 200 || res.data == null) {
        // A 404 is the ordinary answer for "nobody has timed this episode".
        // Cached as empty so the miss is paid once per episode, not per tick.
        _episodes[cacheKey] = const [];
        return const [];
      }
      final results = res.data!['results'];
      final out = <SkipInterval>[];
      if (results is List) {
        for (final r in results) {
          if (r is! Map) continue;
          final interval = r['interval'];
          if (interval is! Map) continue;
          final start = (interval['startTime'] as num?)?.toDouble();
          final end = (interval['endTime'] as num?)?.toDouble();
          final type = '${r['skipType'] ?? ''}';
          if (start == null || end == null || end <= start) continue;
          final s = SkipInterval(
            type: type,
            start: Duration(milliseconds: (start * 1000).round()),
            end: Duration(milliseconds: (end * 1000).round()),
          );
          if (s.isUsable) out.add(s);
        }
      }
      out.sort((a, b) => a.start.compareTo(b.start));
      _episodes[cacheKey] = out;
      if (out.isNotEmpty) {
        debugPrint('$_tag mal=$malId ep=$episodeNumber -> '
            '${out.map((e) => '${e.type} ${e.start.inSeconds}-${e.end.inSeconds}s').join(', ')}');
      }
      return out;
    } catch (e) {
      debugPrint('$_tag lookup failed for mal=$malId ep=$episodeNumber: $e');
      // NOT cached: a network blip should not turn into "this episode has no
      // opening" for the rest of the session.
      return const [];
    }
  }

  Future<int?> _malIdFor({
    required String provider,
    required String contentUrl,
    required String title,
  }) async {
    final key = '$provider|$contentUrl';
    if (_malIds.containsKey(key)) return _malIds[key];

    int? malId;
    try {
      final api = getIt<AnilistService>().api;

      // The link the user made by hand, when there is one. See the class doc.
      final linked = getIt<AnilistTracker>().links.get(provider, contentUrl);
      if (linked != null && linked.mediaId > 0) {
        malId = await api.malIdFor(linked.mediaId);
      }

      if (malId == null && title.trim().isNotEmpty) {
        final results = await api.searchMedia(title, perPage: 5);
        for (final m in results) {
          if (m.idMal != null && m.idMal! > 0) {
            malId = m.idMal;
            break;
          }
        }
      }
    } catch (e) {
      debugPrint('$_tag MAL id lookup failed for "$title": $e');
      // Left uncached for the same reason as above.
      return null;
    }

    _malIds[key] = malId;
    return malId;
  }
}
