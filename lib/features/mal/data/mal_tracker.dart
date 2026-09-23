import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:soplay/features/anilist/data/anilist_tracker.dart';
import 'package:soplay/features/mal/data/mal_link_store.dart';
import 'package:soplay/features/mal/data/mal_service.dart';
import 'package:soplay/features/mal/domain/entities/mal_entities.dart';
import 'package:soplay/features/anilist/domain/entities/tracker_lookup.dart';
import 'package:soplay/features/tracker/data/tracker_outbox.dart';

/// Turns "an episode finished playing" into "MyAnimeList knows about it".
///
/// Governed by the same three rules as [AnilistTracker], and for the same
/// reasons: never write to a title that was not matched confidently, never move
/// progress backwards, never surface a failure during playback.
///
/// What differs is how the id is found. MAL's own search is poor at the
/// transliterated and translated titles Sozo's sources carry, and matching the
/// same show twice — once per tracker — would double both the work and the
/// number of ways it can be wrong. AniList already solves this and publishes
/// the MAL id for the same entry, so the AniList match is reused and `idMal`
/// read off it. MAL's search is only the fallback for entries AniList has no
/// counterpart for.
///
/// Anime only, and that is a limit rather than an oversight: every id here is
/// an ANIME id and every call below is an anime endpoint, while MAL numbers
/// manga in a separate space and reads their progress from `num_chapters_read`
/// on `/manga/{id}`. Handing a manga's `idMal` to `updateProgress` would
/// therefore write a chapter count onto whatever anime happens to hold that
/// number. The reader reports to AniList alone for this reason; adding manga
/// here means adding the manga endpoints to MalApi first, not calling these
/// with a different id.
///
/// A write that fails for a reason that says nothing about the title goes to
/// the [TrackerOutbox] and is sent again later, as AniList's does.
class MalTracker {
  MalTracker({
    required MalService service,
    required MalLinkStore links,
    required AnilistTracker anilist,
    TrackerOutbox? outbox,
  }) : _service = service,
       _links = links,
       _anilist = anilist,
       _outbox = outbox {
    outbox?.register(
      outboxName,
      send: (w) => _report(
        provider: w.provider,
        contentUrl: w.contentUrl,
        title: w.title,
        number: w.number,
      ).then((r) => r.result),
      account: _account,
    );
  }

  final MalService _service;
  final MalLinkStore _links;
  final TrackerOutbox? _outbox;

  /// This tracker's name in the [TrackerOutbox].
  static const String outboxName = 'mal';

  /// Who is connected, for binding a queued write to one account.
  String? _account() {
    final viewer = _service.viewer;
    if (viewer != null) return '${viewer.id}';
    return isConnected ? 'connected' : null;
  }

  /// Used only as a MATCHER. AniList search needs no token, so this works even
  /// when the user has connected MAL and nothing else.
  final AnilistTracker _anilist;

  static const String _tag = '[MAL]';

  /// Titles already looked up and found to have no confident match, so a
  /// hopeless lookup is not retried on every single episode.
  final Set<String> _autoMatchFailed = <String>{};

  bool get isConnected => _service.isConnected;

  MalLinkStore get links => _links;

  /// Records that [episodeNumber] of a local title has been watched.
  ///
  /// Returns the anime id it wrote to, or null when nothing was written — which
  /// is the common and correct outcome for an unmatched title.
  Future<int?> reportEpisode({
    required String provider,
    required String contentUrl,
    required String title,
    required int episodeNumber,
  }) async {
    if (!isConnected || episodeNumber <= 0 || contentUrl.trim().isEmpty) {
      return null;
    }
    final outcome = await _report(
      provider: provider,
      contentUrl: contentUrl,
      title: title,
      number: episodeNumber,
    );
    final outbox = _outbox;
    switch (outcome.result) {
      case TrackerWriteResult.failed when outbox != null:
        // Bound to the account it was meant for, so a switch of account can
        // never deliver it somewhere else.
        final account = _account();
        if (account == null) break;
        unawaited(
          outbox.queue(
            PendingTrackerWrite(
              tracker: outboxName,
              provider: provider,
              contentUrl: contentUrl,
              title: title,
              number: episodeNumber,
              account: account,
              queuedAt: DateTime.now().millisecondsSinceEpoch,
            ),
          ),
        );
      case TrackerWriteResult.written when outbox != null:
        unawaited(outbox.flush());
      default:
        break;
    }
    return outcome.result == TrackerWriteResult.written ? outcome.id : null;
  }

  /// One report, start to finish, saying how it went.
  Future<({TrackerWriteResult result, int? id})> _report({
    required String provider,
    required String contentUrl,
    required String title,
    required int number,
  }) async {
    if (!isConnected) return (result: TrackerWriteResult.skipped, id: null);
    final resolved = await _resolveAnimeId(
      provider: provider,
      contentUrl: contentUrl,
      title: title,
    );
    final animeId = resolved.id;
    if (animeId == null) {
      return (
        result: resolved.unanswered
            ? TrackerWriteResult.failed
            : TrackerWriteResult.skipped,
        id: null,
      );
    }
    return (
      result: await _write(animeId: animeId, episodeNumber: number),
      id: animeId,
    );
  }

  /// Finds the MAL id for a local title.
  ///
  /// In order: a MAL link already made; the AniList link the USER made by hand;
  /// an automatic AniList match; MAL's own search.
  ///
  /// The second step is the one that matters most and is easiest to leave out.
  /// A manual AniList link exists precisely because no search could match that
  /// title — an Uzbek dub, a transliteration, a source's own naming. Skipping
  /// straight to matching would re-run the search that already failed, fall
  /// through to MAL's weaker one, and quietly track nothing for exactly the
  /// titles the user took the trouble to link.
  ///
  /// [unanswered] when there is no id because a catalogue was not reached.
  Future<({int? id, bool unanswered})> _resolveAnimeId({
    required String provider,
    required String contentUrl,
    required String title,
  }) async {
    final existing = _links.mediaIdFor(provider, contentUrl);
    if (existing != null) return (id: existing, unanswered: false);

    final key = MalLinkStore.keyFor(provider, contentUrl);
    if (_autoMatchFailed.contains(key)) return (id: null, unanswered: false);

    int? animeId;
    String linkTitle = title;
    String? cover;
    int? total;

    final linked = _anilist.links.get(provider, contentUrl);
    if (linked != null && linked.mediaId > 0) {
      animeId = await _malIdFor(linked.mediaId);
      linkTitle = linked.title.isNotEmpty ? linked.title : title;
      cover = linked.coverImage;
      total = linked.totalEpisodes;
    }

    // Whether every catalogue asked actually answered. Two lookups follow, and
    // either can fail for a reason that says nothing about the title: it takes
    // only one unanswered request to make giving up permanently wrong.
    var allAnswered = true;

    // No hand-made link, or AniList has no MAL counterpart for the one there
    // is. Fall back to matching by title.
    if (animeId == null) {
      final lookup = await _anilist.lookUpExactMatch(title);
      allAnswered = allAnswered && lookup.answered;
      final match = lookup.value;
      // AniList matched, and knows the MAL counterpart — the free path, and the
      // one that runs for almost every anime.
      animeId = match?.idMal;
      if (animeId != null) {
        linkTitle = match!.displayTitle;
        cover = match.coverImage;
        total = match.episodes;
      }
    }

    // Nothing on the AniList side knows this entry. Ask MAL directly, with the
    // same exact-title rule — a fuzzy best-result would quietly attach season 2
    // to season 1 and write into it for months.
    if (animeId == null) {
      final lookup = await _lookUpMal(title);
      allAnswered = allAnswered && lookup.answered;
      final fallback = lookup.value;
      if (fallback == null) {
        // Remembered as hopeless only when both catalogues actually said so.
        // Recording an unanswered request here stopped the title ever
        // auto-linking again for the life of the process.
        if (allAnswered) _autoMatchFailed.add(key);
        return (id: null, unanswered: !allAnswered);
      }
      animeId = fallback.id;
      linkTitle = fallback.title;
      cover = fallback.picture;
      total = fallback.episodes;
    }

    await _links.save(
      MalLink(
        provider: provider,
        contentUrl: contentUrl,
        mediaId: animeId,
        title: linkTitle,
        coverImage: cover,
        totalEpisodes: total,
        linkedAt: DateTime.now().millisecondsSinceEpoch,
        auto: true,
      ),
    );
    return (id: animeId, unanswered: false);
  }

  /// AniList media id -> MAL anime id, swallowing a lookup that cannot be made.
  ///
  /// A failure here must fall through to matching rather than abort: being
  /// offline for one request is not a reason to stop tracking a title forever.
  Future<int?> _malIdFor(int anilistMediaId) async {
    try {
      return await _anilist.api.malIdFor(anilistMediaId);
    } catch (e) {
      debugPrint('$_tag idMal lookup failed for AniList $anilistMediaId: $e');
      return null;
    }
  }

  /// Searches MAL and returns a result only when one of its titles matches
  /// [title] EXACTLY once normalized.
  ///
  /// Reports whether MAL answered, not just what it answered — see
  /// [TrackerLookup].
  Future<TrackerLookup<MalAnime>> _lookUpMal(String title) async {
    final token = _service.token;
    // No token is not a miss and not a network failure: there is nobody to ask.
    // Treated as unanswered so a signed-out moment cannot poison the set.
    if (token == null) return const TrackerLookup.unreachable();

    final wanted = AnilistTracker.normalizeTitle(title);
    if (wanted.isEmpty) return const TrackerLookup.noMatch();

    try {
      final results = await _service.api.search(title, token: token);
      for (final anime in results) {
        for (final candidate in anime.searchTitles) {
          if (AnilistTracker.normalizeTitle(candidate) == wanted) {
            return TrackerLookup.found(anime);
          }
        }
      }
      return const TrackerLookup.noMatch();
    } catch (e) {
      debugPrint('$_tag search failed for "$title": $e');
      return const TrackerLookup.unreachable();
    }
  }

  /// Reads the account's current position, then writes only if this episode is
  /// genuinely ahead of it.
  Future<TrackerWriteResult> _write({
    required int animeId,
    required int episodeNumber,
  }) async {
    final token = _service.token;
    if (token == null) return TrackerWriteResult.skipped;

    try {
      final state = await _service.api.entryState(
        token: token,
        animeId: animeId,
      );
      if (state != null && episodeNumber <= state.watchedEpisodes) {
        // Already at or beyond this episode — a rewatch, or another device got
        // here first. Writing would move the list backwards.
        return TrackerWriteResult.skipped;
      }

      final result = await _service.api.updateProgress(
        token: token,
        animeId: animeId,
        episodes: episodeNumber,
        status: statusFor(
          current: state?.status,
          isRewatching: state?.isRewatching ?? false,
          episode: episodeNumber,
          total: state?.totalEpisodes,
        ),
      );
      debugPrint(
        '$_tag anime $animeId → episode ${result.watchedEpisodes} '
        '(${result.status})',
      );
      return TrackerWriteResult.written;
    } catch (e) {
      // Playback must not be disturbed by a tracker outage — it is queued
      // and sent later instead.
      debugPrint('$_tag write failed for anime $animeId: $e');
      return TrackerWriteResult.failed;
    }
  }

  /// The status to send alongside a progress write.
  ///
  /// Returns null — meaning "leave it alone" — whenever the existing status
  /// already describes active viewing.
  ///
  /// A rewatch is the case worth naming: MAL models it as a flag on a
  /// `completed` entry rather than as a status, so sending any status at all
  /// would knock the entry out of `completed` and end the rewatch.
  ///
  /// Public because the library screen makes the same decision when the user
  /// steps progress by hand. Two copies of this would drift, and every way it
  /// can be wrong is invisible until somebody's list already is.
  static String? statusFor({
    required String? current,
    required bool isRewatching,
    required int episode,
    required int? total,
  }) {
    if (isRewatching) return null;
    if (total != null && total > 0 && episode >= total) {
      return MalStatus.completed;
    }
    if (current == MalStatus.watching) return null;
    return MalStatus.watching;
  }
}
