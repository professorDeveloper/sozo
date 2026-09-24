import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:soplay/features/trakt/data/trakt_api.dart';
import 'package:soplay/features/trakt/data/trakt_hub_models.dart';
import 'package:soplay/features/trakt/data/trakt_service.dart';

/// One list on the Trakt screen, loaded on first view and kept.
class TraktSection {
  List<TraktEntry> items = const [];
  bool loading = false;
  bool loaded = false;
  String? error;

  /// History only: another page is waiting.
  bool more = false;
  int page = 0;
}

/// The viewer's Trakt, for the in-app screen.
///
/// Each tab loads when it is first shown rather than all at once: "up next"
/// alone is a request per show, and someone opening the screen for the
/// watchlist should not wait for it.
class TraktHubController extends ChangeNotifier {
  TraktHubController({required this.service});

  final TraktService service;
  TraktApi get _api => service.api;

  TraktStats? stats;
  final TraktSection playback = TraktSection();
  final TraktSection upNext = TraktSection();
  final TraktSection watchlist = TraktSection();
  final TraktSection history = TraktSection();
  final TraktSection calendar = TraktSection();
  final TraktSection recommendedMovies = TraktSection();
  final TraktSection recommendedShows = TraktSection();
  final TraktSection ratings = TraktSection();
  final TraktSection trendingMovies = TraktSection();
  final TraktSection trendingShows = TraktSection();

  /// Rows with an action in flight, by Trakt id, so their buttons wait.
  final Set<int> busy = {};

  bool _disposed = false;

  ({String clientId, String token})? get _auth {
    final c = service.clientId;
    final t = service.token;
    if (c == null || t == null) return null;
    return (clientId: c, token: t);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  static String describe(Object e) =>
      e is TraktException ? e.message : 'Trakt did not answer';

  Future<void> _load(
    TraktSection section,
    Future<List<TraktEntry>> Function(String clientId, String token) fetch, {
    bool force = false,
  }) async {
    final auth = _auth;
    if (auth == null || section.loading) return;
    if (section.loaded && !force) return;
    section
      ..loading = true
      ..error = null;
    _notify();
    try {
      section.items = await fetch(auth.clientId, auth.token);
      section.loaded = true;
    } catch (e) {
      section.error = describe(e);
    } finally {
      section.loading = false;
      _notify();
    }
  }

  Future<void> loadStats({bool force = false}) async {
    final auth = _auth;
    final slug = service.viewer?.slug;
    if (auth == null || slug == null || slug.isEmpty) return;
    if (stats != null && !force) return;
    try {
      stats = await _api.stats(
        slug,
        clientId: auth.clientId,
        token: auth.token,
      );
      _notify();
    } catch (_) {}
  }

  /// "Continue watching" and the next episode of every show in progress.
  Future<void> loadUpNext({bool force = false}) async {
    await Future.wait([
      _load(
        playback,
        (c, t) => _api.playback(clientId: c, token: t),
        force: force,
      ),
      _load(upNext, _upNext, force: force),
    ]);
  }

  /// The shows most recently watched, each with its next episode, dropping
  /// the ones already caught up. A request per show, so only the latest
  /// [maxShows], a few at a time.
  static const int maxShows = 30;

  Future<List<TraktEntry>> _upNext(String clientId, String token) async {
    final shows = await _api.watchedShows(clientId: clientId, token: token);
    final recent = shows.take(maxShows).toList();
    final out = List<TraktEntry?>.filled(recent.length, null);
    var next = 0;
    Future<void> worker() async {
      while (next < recent.length) {
        final i = next++;
        final show = recent[i];
        try {
          final p = await _api.showProgress(
            show.media.traktId,
            clientId: clientId,
            token: token,
          );
          if (p.next != null && p.completed < p.aired) {
            out[i] = show.copyWith(
              episode: p.next,
              aired: p.aired,
              completed: p.completed,
            );
          }
        } catch (_) {}
      }
    }

    await Future.wait(List.generate(5, (_) => worker()));
    return [for (final e in out) ?e];
  }

  Future<void> loadWatchlist({bool force = false}) => _load(
    watchlist,
    (c, t) => _api.watchlistItems(clientId: c, token: t),
    force: force,
  );

  Future<void> loadHistory({bool force = false}) async {
    final auth = _auth;
    if (auth == null || history.loading) return;
    if (history.loaded && !force) return;
    history
      ..loading = true
      ..error = null
      ..page = 0;
    _notify();
    try {
      final r = await _api.history(clientId: auth.clientId, token: auth.token);
      history
        ..items = r.items
        ..more = r.more
        ..page = 1
        ..loaded = true;
    } catch (e) {
      history.error = describe(e);
    } finally {
      history.loading = false;
      _notify();
    }
  }

  Future<void> loadMoreHistory() async {
    final auth = _auth;
    if (auth == null || history.loading || !history.more) return;
    history.loading = true;
    _notify();
    try {
      final r = await _api.history(
        clientId: auth.clientId,
        token: auth.token,
        page: history.page + 1,
      );
      history
        ..items = [...history.items, ...r.items]
        ..more = r.more
        ..page = history.page + 1;
    } catch (e) {
      history.error = describe(e);
    } finally {
      history.loading = false;
      _notify();
    }
  }

  /// Today and the two weeks after it.
  Future<void> loadCalendar({bool force = false}) {
    final now = DateTime.now();
    return _load(
      calendar,
      (c, t) => _api.calendar(
        DateTime(now.year, now.month, now.day),
        15,
        clientId: c,
        token: t,
      ),
      force: force,
    );
  }

  Future<void> loadRecommendations({bool force = false}) async {
    await Future.wait([
      _load(
        recommendedMovies,
        (c, t) => _api.recommendations('movie', clientId: c, token: t),
        force: force,
      ),
      _load(
        recommendedShows,
        (c, t) => _api.recommendations('show', clientId: c, token: t),
        force: force,
      ),
    ]);
  }

  Future<void> loadRatings({bool force = false}) => _load(
    ratings,
    (c, t) => _api.ratedItems(clientId: c, token: t),
    force: force,
  );

  Future<void> loadTrending({bool force = false}) async {
    await Future.wait([
      _load(
        trendingMovies,
        (c, _) => _api.chart('movie', 'trending', clientId: c),
        force: force,
      ),
      _load(
        trendingShows,
        (c, _) => _api.chart('show', 'trending', clientId: c),
        force: force,
      ),
    ]);
  }

  // ─── actions ────────────────────────────────────────────────────────────

  /// Runs [action] for [media], marking it busy; a failure comes back as a
  /// message for the screen to show.
  Future<String?> _act(
    TraktMedia media,
    Future<void> Function(String clientId, String token) action,
  ) async {
    final auth = _auth;
    if (auth == null) return 'Trakt is not connected';
    if (!busy.add(media.traktId)) return null;
    _notify();
    try {
      await action(auth.clientId, auth.token);
      return null;
    } catch (e) {
      return describe(e);
    } finally {
      busy.remove(media.traktId);
      _notify();
    }
  }

  Future<String?> setWatchlisted(TraktMedia media, bool add) =>
      _act(media, (c, t) async {
        await _api.watchlist(media, add: add, clientId: c, token: t);
        if (!add) {
          watchlist.items = [
            for (final e in watchlist.items)
              if (e.media.traktId != media.traktId) e,
          ];
        } else {
          watchlist.loaded = false;
        }
        // A suggestion that was added is no longer a suggestion.
        for (final s in [recommendedMovies, recommendedShows]) {
          s.items = [
            for (final e in s.items)
              if (e.media.traktId != media.traktId) e,
          ];
        }
      });

  Future<String?> hideRecommendation(TraktMedia media) =>
      _act(media, (c, t) async {
        await _api.hideRecommendation(media, clientId: c, token: t);
        final section = media.isMovie ? recommendedMovies : recommendedShows;
        section.items = [
          for (final e in section.items)
            if (e.media.traktId != media.traktId) e,
        ];
      });

  Future<String?> removePlayback(TraktEntry entry) {
    final id = entry.id;
    if (id == null) return Future.value(null);
    return _act(entry.media, (c, t) async {
      await _api.removePlayback(id, clientId: c, token: t);
      playback.items = [
        for (final e in playback.items)
          if (e.id != id) e,
      ];
    });
  }

  Future<String?> removeHistory(TraktEntry entry) {
    final id = entry.id;
    if (id == null) return Future.value(null);
    return _act(entry.media, (c, t) async {
      await _api.removeHistory([id], clientId: c, token: t);
      history.items = [
        for (final e in history.items)
          if (e.id != id) e,
      ];
      stats = null;
      unawaited(loadStats());
    });
  }

  /// Marks the film, or the show's next episode, as watched now; the up-next
  /// row moves on to the episode after it.
  Future<String?> markWatched(TraktEntry entry) =>
      _act(entry.media, (c, t) async {
        final now = DateTime.now().toUtc().toIso8601String();
        var ep = entry.episode;
        // A show with no episode named: the one after the last watched.
        if (!entry.isMovie && ep == null) {
          final p = await _api.showProgress(
            entry.media.traktId,
            clientId: c,
            token: t,
          );
          ep = p.next;
          if (ep == null) throw const TraktException('Nothing left to watch');
        }
        if (entry.isMovie || ep == null) {
          await _api.addHistory(
            {
              'movies': [
                {...entry.media.ref, 'watched_at': now},
              ],
            },
            clientId: c,
            token: t,
          );
        } else {
          await _api.addHistory(
            {
              'shows': [
                {
                  ...entry.media.ref,
                  'seasons': [
                    {
                      'number': ep.season,
                      'episodes': [
                        {'number': ep.number, 'watched_at': now},
                      ],
                    },
                  ],
                },
              ],
            },
            clientId: c,
            token: t,
          );
          try {
            final p = await _api.showProgress(
              entry.media.traktId,
              clientId: c,
              token: t,
            );
            upNext.items = [
              for (final e in upNext.items)
                if (e.media.traktId != entry.media.traktId)
                  e
                else if (p.next != null && p.completed < p.aired)
                  e.copyWith(
                    episode: p.next,
                    aired: p.aired,
                    completed: p.completed,
                  ),
            ];
          } catch (_) {}
        }
        history.loaded = false;
        stats = null;
        unawaited(loadStats());
      });

  Future<String?> rate(TraktEntry entry, int score) =>
      _act(entry.media, (c, t) async {
        await _api.rate(entry.media, score, clientId: c, token: t);
        ratings.loaded = false;
      });

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
