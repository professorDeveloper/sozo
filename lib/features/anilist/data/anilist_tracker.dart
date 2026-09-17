import 'package:flutter/foundation.dart';

import 'package:soplay/core/content/content_mode.dart';
import 'package:soplay/features/anilist/data/anilist_link_store.dart';
import 'package:soplay/features/anilist/data/anilist_api.dart';
import 'package:soplay/features/anilist/data/anilist_service.dart';
import 'package:soplay/features/anilist/domain/entities/anilist_entities.dart';

/// Turns "an episode finished playing" into "AniList knows about it".
///
/// Sits between the player and [AnilistService] because the decision of WHETHER
/// to write is the hard part, not the write itself. Three rules govern it, and
/// all three exist to protect a list the user curated by hand:
///
///   1. never write to a title the user has not linked (or that did not match
///      exactly) — a wrong media id silently rewrites the wrong show;
///   2. never move progress backwards — a rewatch, or a second device that is
///      further ahead, must not undo real progress;
///   3. never surface a failure to the viewer — this runs during playback.
class AnilistTracker {
  AnilistTracker({
    required AnilistService service,
    required AnilistLinkStore links,
  }) : _service = service,
       _links = links;

  final AnilistService _service;
  final AnilistLinkStore _links;

  AnilistLinkStore get links => _links;

  /// The underlying API, for callers that need a lookup this class does not
  /// wrap. Search and media reads are public, so this is usable even when
  /// AniList itself is not connected — which is what lets the MyAnimeList
  /// tracker borrow AniList purely as a matcher.
  AnilistApi get api => _service.api;

  static const String _tag = '[AniList]';

  /// Titles already looked up and found to have no confident match, so a
  /// hopeless auto-match is not retried on every single episode.
  final Set<String> _autoMatchFailed = <String>{};

  bool get isConnected => _service.isConnected;

  /// Records that [episodeNumber] of a local title has been watched.
  ///
  /// Returns the media id it wrote to, or null when nothing was written — which
  /// is the common and correct outcome for an unlinked title.
  Future<int?> reportEpisode({
    required String provider,
    required String contentUrl,
    required String title,
    required int episodeNumber,
  }) async {
    if (!isConnected || episodeNumber <= 0 || contentUrl.trim().isEmpty) {
      return null;
    }

    final mediaId = await _resolveMediaId(
      provider: provider,
      contentUrl: contentUrl,
      title: title,
    );
    if (mediaId == null) return null;

    return await _write(mediaId: mediaId, episodeNumber: episodeNumber)
        ? mediaId
        : null;
  }

  /// Records that [chapterNumber] of a local title has been read.
  ///
  /// Delegates to [reportEpisode] because on AniList they are the same write:
  /// a list entry has one `progress` field, counting whichever unit the media
  /// has, and `entryState` already reads `chapters` as the total for a title
  /// that has no episodes. What keeps the two apart is [_resolveMediaId],
  /// which searches the MANGA half of the catalogue for a reader's provider.
  ///
  /// It is still its own method: a reader calling `reportEpisode` would read
  /// as a mistake at the call site, and the next person to need a
  /// chapter-specific rule would have nowhere to put it.
  Future<int?> reportChapter({
    required String provider,
    required String contentUrl,
    required String title,
    required int chapterNumber,
  }) => reportEpisode(
    provider: provider,
    contentUrl: contentUrl,
    title: title,
    episodeNumber: chapterNumber,
  );

  /// Finds the AniList id for a local title: an existing link first, then an
  /// exact title match.
  Future<int?> _resolveMediaId({
    required String provider,
    required String contentUrl,
    required String title,
  }) async {
    final existing = _links.mediaIdFor(provider, contentUrl);
    if (existing != null) return existing;

    final key = AnilistLinkStore.keyFor(provider, contentUrl);
    if (_autoMatchFailed.contains(key)) return null;

    // Which half of AniList to look in, taken from the source: a reader's
    // title is not in the anime index at all, so searching it there would
    // fail every time and then be remembered as hopeless.
    final match = await findExactMatch(
      title,
      type: provider.contentMode == ContentMode.video ? 'ANIME' : 'MANGA',
    );
    if (match == null) {
      _autoMatchFailed.add(key);
      return null;
    }

    await _links.save(
      AnilistLink(
        provider: provider,
        contentUrl: contentUrl,
        mediaId: match.id,
        title: match.displayTitle,
        coverImage: match.coverImage,
        // Episodes for an anime, chapters for a manga — the same unit the
        // progress written against this link is counted in, chosen once on the
        // media rather than again here.
        totalEpisodes: match.totalUnits,
        linkedAt: DateTime.now().millisecondsSinceEpoch,
        auto: true,
      ),
    );
    return match.id;
  }

  /// Searches AniList and returns a result only when one of its titles matches
  /// [title] EXACTLY once normalized.
  ///
  /// Deliberately strict. A fuzzy "best result" would attach season 2 to season
  /// 1, or a recap film to the series, and then quietly write episode numbers
  /// into it for months. When there is no exact match the user is asked instead
  /// — being unlinked is recoverable, being wrongly linked is not obvious.
  ///
  /// [type] defaults to ANIME because that is what the MyAnimeList tracker
  /// borrows this for, and MAL numbers manga separately.
  Future<AnilistMedia?> findExactMatch(
    String title, {
    String type = 'ANIME',
  }) async {
    final wanted = normalizeTitle(title);
    if (wanted.isEmpty) return null;
    try {
      final results = await _service.api.searchMedia(
        title,
        perPage: 10,
        type: type,
      );
      for (final media in results) {
        for (final candidate in media.searchTitles) {
          if (normalizeTitle(candidate) == wanted) return media;
        }
      }
    } catch (e) {
      debugPrint('$_tag auto-match failed for "$title": $e');
    }
    return null;
  }

  /// Reads the account's current position, then writes only if this episode is
  /// genuinely ahead of it.
  Future<bool> _write({
    required int mediaId,
    required int episodeNumber,
  }) async {
    final token = _service.token;
    if (token == null) return false;

    try {
      final state = await _service.api.entryState(
        token: token,
        mediaId: mediaId,
      );
      if (state != null && episodeNumber <= state.progress) {
        // Already at or beyond this episode — a rewatch, or another device got
        // here first. Writing would move the list backwards.
        return false;
      }

      final total = state?.totalEpisodes;
      final result = await _service.api.saveProgress(
        token: token,
        mediaId: mediaId,
        progress: episodeNumber,
        status: _statusFor(
          current: state?.status,
          episode: episodeNumber,
          total: total,
        ),
      );
      debugPrint(
        '$_tag media $mediaId → episode ${result.progress} (${result.status})',
      );
      return true;
    } catch (e) {
      // Playback must not be disturbed by a tracker outage.
      debugPrint('$_tag write failed for media $mediaId: $e');
      return false;
    }
  }

  /// The status to send alongside a progress write.
  ///
  /// Returns null — meaning "leave it alone" — whenever the existing status
  /// already describes active viewing, so a rewatch stays REPEATING instead of
  /// being demoted to CURRENT.
  static String? _statusFor({
    required String? current,
    required int episode,
    required int? total,
  }) {
    if (current == AnilistStatus.repeating.value) return null;
    if (total != null && total > 0 && episode >= total) {
      return AnilistStatus.completed.value;
    }
    if (current == AnilistStatus.current.value) return null;
    return AnilistStatus.current.value;
  }

  /// Strips the noise that makes two names for the same show look different:
  /// case, punctuation, and the release tags source sites append.
  static String normalizeTitle(String raw) {
    var s = raw.toLowerCase().trim();
    for (final pattern in _noise) {
      s = s.replaceAll(pattern, ' ');
    }
    // Strip punctuation by naming it, rather than by keeping a Latin-only
    // character class: titles here are also Cyrillic and Japanese, and a
    // `[^a-z0-9]` filter would erase those scripts entirely.
    s = s.replaceAll(_punctuation, ' ');
    return s.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  static final RegExp _punctuation = RegExp(
    r'''[.,:;!?'"`~@#$%^&*_+=<>/\\|{}\[\]()·・…—–-]+''',
  );

  /// Bracketed tags (`[1080p]`, `(TV)`), quality markers and subtitle labels —
  /// all of which appear in source-site titles and never in an AniList one.
  static final List<RegExp> _noise = [
    RegExp(r'\[[^\]]*\]'),
    RegExp(r'\([^)]*\)'),
    RegExp(r'\b(1080p|720p|480p|4k|hd|fhd|bluray|bd|web-?dl|hevc|x26[45])\b'),
    RegExp(r'\b(sub|dub|subbed|dubbed|uzbek|uzbekcha|tarjima|rus|russian)\b'),
  ];
}
