import 'dart:async';

import 'package:soplay/features/tracker/data/tracker_outbox.dart';
import 'package:soplay/features/trakt/data/trakt_api.dart';
import 'package:soplay/features/trakt/data/trakt_link_store.dart';
import 'package:soplay/features/trakt/data/trakt_service.dart';

/// A season and an episode on Trakt.
typedef TraktEpisode = ({int season, int episode});

/// What the player tells Trakt, and how a title on a source becomes a film or
/// a show on Trakt.
///
/// Playback scrobbles: start when it plays, pause when it pauses or the
/// player closes, stop once it is far enough through — Trakt records a stop
/// at 80% or more as watched, and shows "watching now" on the profile in
/// between. A stop that does not land goes to the outbox and is sent later as
/// a plain history entry.
class TraktTracker {
  TraktTracker({required this.service, required this.outbox}) {
    outbox.register(
      outboxName,
      send: _sendQueued,
      account: () => service.viewer?.slug,
    );
  }

  final TraktService service;
  final TrackerOutbox outbox;

  static const String outboxName = 'trakt';

  bool get isConnected => service.isConnected;

  TraktLinkStore get _links => service.links;
  TraktApi get _api => service.api;

  final Map<int, List<TraktSeason>> _seasons = {};

  /// Titles already searched without a confident answer this session, so a
  /// start, a pause and a stop do not each search Trakt again.
  final Set<String> _unmatched = {};

  // ─── identifying a title ───────────────────────────────────────────────

  // `\b` only knows ASCII letters, so "5 сезон" never ended on a boundary;
  // the edges are spelled out as "no letter or digit next to it" instead.
  static final RegExp _seasonPattern = RegExp(
    r'(?<![\p{L}\d])(?:season\s*(\d{1,2})|s(\d{1,2})|(\d{1,2})\s*-?\s*(?:fasl|сезон|season)|сезон\s*(\d{1,2})|fasl\s*(\d{1,2}))(?![\p{L}\d])',
    caseSensitive: false,
    unicode: true,
  );

  /// The season a source's title names — "Season 2", "S2", "2-fasl",
  /// "2 сезон" — or null.
  static int? seasonIn(String title) {
    final m = _seasonPattern.firstMatch(title);
    if (m == null) return null;
    for (var i = 1; i <= m.groupCount; i++) {
      final g = m.group(i);
      if (g != null) return int.tryParse(g);
    }
    return null;
  }

  /// The title without its season part and the noise sources add, for
  /// searching Trakt and for comparing with what it finds.
  static String baseTitle(String title) => title
      .replaceAll(_seasonPattern, ' ')
      .replaceAll(RegExp(r'\((?:19|20)\d\d\)|\[.*?\]'), ' ')
      .replaceAll(
        RegExp(
          r"\b(?:uzbek|o'zbek|tarjima|dubbed|sub|dub)\b",
          caseSensitive: false,
        ),
        ' ',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9а-яё]+'), '');

  /// The Trakt title for a source title: what the viewer linked, or a match
  /// made here — only an exact one, since a wrong match writes plays to
  /// somebody else's show. Null when there is no confident answer.
  Future<TraktLink?> resolve({
    required String provider,
    required String contentUrl,
    required String title,
    required bool isSerial,
    int? year,
    int? tmdbId,
  }) async {
    final known = _links.get(provider, contentUrl);
    if (known != null) return known;
    final clientId = service.clientId;
    if (clientId == null) return null;
    final missKey = '$provider|$contentUrl';
    if (tmdbId == null && _unmatched.contains(missKey)) return null;
    final kind = isSerial ? 'show' : 'movie';
    TraktMedia? match;
    try {
      if (tmdbId != null) {
        match = await _api.byTmdb(tmdbId, kind, clientId: clientId);
      }
      if (match == null) {
        final base = baseTitle(title);
        if (base.isEmpty) return null;
        final found = await _api.search(
          base,
          clientId: clientId,
          kind: kind,
          year: year,
        );
        final exact = [
          for (final m in found)
            if (_norm(m.title) == _norm(base) &&
                (year == null || m.year == year))
              m,
        ];
        // One exact hit is an answer; several (remakes) are not.
        if (exact.length == 1) match = exact.single;
      }
    } catch (_) {
      return null;
    }
    if (match == null) {
      _unmatched.add(missKey);
      return null;
    }
    final link = TraktLink(
      provider: provider,
      contentUrl: contentUrl,
      traktId: match.traktId,
      kind: match.kind,
      title: match.title,
      year: match.year,
      season: isSerial ? seasonIn(title) : null,
      auto: true,
    );
    await _links.save(link);
    return link;
  }

  /// A source's episode number as Trakt's season and episode.
  ///
  /// A link with a season counts within it. Without one, the number is
  /// absolute — anime sources number the whole run 1..N — and is walked
  /// through the show's aired seasons: episode 30 of a show with seasons of
  /// 24 and 12 is season 2, episode 6.
  Future<TraktEpisode?> episodeFor(TraktLink link, int number) async {
    if (number <= 0) return null;
    if (link.season != null) return (season: link.season!, episode: number);
    final clientId = service.clientId;
    if (clientId == null) return (season: 1, episode: number);
    var seasons = _seasons[link.traktId];
    if (seasons == null) {
      try {
        seasons = await _api.seasons(link.traktId, clientId: clientId);
        _seasons[link.traktId] = seasons;
      } catch (_) {
        return (season: 1, episode: number);
      }
    }
    var left = number;
    for (final s in seasons) {
      if (s.episodes <= 0) continue;
      if (left <= s.episodes) return (season: s.number, episode: left);
      left -= s.episodes;
    }
    // Past everything aired: most likely season 1 numbering after all.
    return (season: 1, episode: number);
  }

  Map<String, dynamic> _body(
    TraktLink link,
    TraktEpisode? ep,
    double progress,
  ) => {
    if (link.isMovie)
      'movie': {
        'ids': {'trakt': link.traktId},
      }
    else ...{
      'show': {
        'ids': {'trakt': link.traktId},
      },
      'episode': {'season': ep!.season, 'number': ep.episode},
    },
    'progress': double.parse(progress.clamp(0, 100).toStringAsFixed(2)),
  };

  // ─── playback ──────────────────────────────────────────────────────────

  /// start / pause, best effort: a missed "watching now" costs nothing.
  Future<void> scrobble(
    String action, {
    required String provider,
    required String contentUrl,
    required String title,
    required bool isSerial,
    required int episode,
    required double progress,
  }) async {
    final token = service.token;
    final clientId = service.clientId;
    if (token == null || clientId == null) return;
    final link = await resolve(
      provider: provider,
      contentUrl: contentUrl,
      title: title,
      isSerial: isSerial,
    );
    if (link == null) return;
    final ep = link.isMovie ? null : await episodeFor(link, episode);
    if (!link.isMovie && ep == null) return;
    try {
      await _api.scrobble(
        action,
        _body(link, ep, progress),
        clientId: clientId,
        token: token,
      );
    } catch (_) {}
  }

  /// The episode is watched: a stop at [progress] (80 or more). Queued for a
  /// history write if it does not land. Returns whether it was written now.
  Future<bool> reportWatched({
    required String provider,
    required String contentUrl,
    required String title,
    required bool isSerial,
    required int episode,
    double progress = 90,
  }) async {
    final token = service.token;
    final clientId = service.clientId;
    final account = service.viewer?.slug;
    if (token == null || clientId == null || account == null) return false;
    final link = await resolve(
      provider: provider,
      contentUrl: contentUrl,
      title: title,
      isSerial: isSerial,
    );
    if (link == null) return false;
    final ep = link.isMovie ? null : await episodeFor(link, episode);
    try {
      await _api.scrobble(
        'stop',
        _body(link, ep, progress < 80 ? 80.5 : progress),
        clientId: clientId,
        token: token,
      );
      return true;
    } catch (_) {
      await outbox.queue(
        PendingTrackerWrite(
          tracker: outboxName,
          provider: provider,
          contentUrl: contentUrl,
          title: title,
          number: isSerial ? episode : 1,
          account: account,
          queuedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      return false;
    }
  }

  Future<TrackerWriteResult> _sendQueued(PendingTrackerWrite w) async {
    final token = service.token;
    final clientId = service.clientId;
    if (token == null || clientId == null) return TrackerWriteResult.failed;
    final link = _links.get(w.provider, w.contentUrl);
    if (link == null) return TrackerWriteResult.skipped;
    final watchedAt = DateTime.fromMillisecondsSinceEpoch(
      w.queuedAt,
    ).toUtc().toIso8601String();
    try {
      if (link.isMovie) {
        await _api.addHistory(
          {
            'movies': [
              {
                'ids': {'trakt': link.traktId},
                'watched_at': watchedAt,
              },
            ],
          },
          clientId: clientId,
          token: token,
        );
      } else {
        final ep = await episodeFor(link, w.number);
        if (ep == null) return TrackerWriteResult.skipped;
        await _api.addHistory(
          {
            'shows': [
              {
                'ids': {'trakt': link.traktId},
                'seasons': [
                  {
                    'number': ep.season,
                    'episodes': [
                      {'number': ep.episode, 'watched_at': watchedAt},
                    ],
                  },
                ],
              },
            ],
          },
          clientId: clientId,
          token: token,
        );
      }
      return TrackerWriteResult.written;
    } on TraktException catch (e) {
      return e.status == 404
          ? TrackerWriteResult.skipped
          : TrackerWriteResult.failed;
    } catch (_) {
      return TrackerWriteResult.failed;
    }
  }
}
