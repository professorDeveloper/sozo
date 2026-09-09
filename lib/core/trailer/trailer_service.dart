import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'package:soplay/core/trailer/trailer_query.dart';
import 'package:soplay/core/trailer/trailer_title_lookup.dart';

/// A trailer that is ready to hand to the app's own player.
@immutable
class TrailerResult {
  const TrailerResult({
    required this.videoId,
    required this.title,
    required this.author,
    required this.streamUrl,
    required this.thumbnail,
    required this.duration,
  });

  final String videoId;
  final String title;
  final String author;

  /// A direct, muxed (video + audio) URL. Progressive, not adaptive — the
  /// point is that the existing player can open it with no extra machinery.
  final String streamUrl;

  final String thumbnail;
  final Duration? duration;

  /// These URLs are signed and short-lived, so a result that has been sitting
  /// in a cache is worse than no result: it plays for a second and stops.
  static const Duration freshness = Duration(minutes: 20);
}

/// Turns a YouTube video id into something the app's player can open.
///
/// ## Why the title is never searched here
///
/// The obvious design is "give me a title, I will find the trailer", and it
/// was the first one tried here. It does not work. `youtube_explode_dart`'s
/// search is broken against YouTube's current response shape — every query
/// throws `NoSuchMethodError: … has no instance method 'getT'` before a single
/// result comes back — and even when it worked, matching a title to a video by
/// scoring search results is a guess. A wrong trailer is worse than none: it
/// looks like a bug, and on an open platform it can put something entirely
/// unrelated in front of somebody.
///
/// TMDB already knows the answer. The detail call the backend makes for every
/// TMDB-backed provider requests `videos` and the response carries the
/// official trailer's YouTube key; it was simply being discarded. So the
/// *finding* happens where the catalogue is, against data curated by the
/// people who own the film, and this class does only the part that has to
/// happen on the device: resolving a known id to a playable URL. That path —
/// `getManifest` — works, and is the stable half of the package.
///
/// A provider with no TMDB backing carries no id on its detail payload, and
/// used to have no trailer at all — no button, on every anime source and every
/// Uzbek catalogue in the app. The backend now answers a name with a video id
/// (`/contents/trailer`, see [TrailerTitleLookup]), so the finding still
/// happens against TMDB rather than by guessing at YouTube, and this class
/// still does only the id-to-stream half. [resolveFor] is the entry point that
/// covers both.
class TrailerService {
  TrailerService({YoutubeExplode? client, TrailerTitleLookup? titles})
      : _yt = client ?? YoutubeExplode(),
        _titles = titles ?? TrailerTitleLookup();

  final YoutubeExplode _yt;
  final TrailerTitleLookup _titles;

  /// Resolved streams, keyed by video id.
  ///
  /// Bounded because a long browsing session touches many titles; the cap is
  /// what stops the cache growing with the session.
  static const int _maxCacheEntries = 40;
  final Map<String, _CacheEntry> _cache = {};

  /// A trailer playing at 1080p on a phone buys nothing over mobile data and
  /// starts noticeably slower than the 720p copy of the same clip.
  static const VideoQuality maxQuality = VideoQuality.high720;

  /// The playable stream for [query], or null when the title has no trailer.
  ///
  /// This is what the screen asks. The name lookup sits behind it, here,
  /// rather than in the widgets, because the trailer button and the header
  /// preview are on the same page for the same title: a lookup in each one's
  /// `initState` is two requests for one answer, and a page revisited later is
  /// two more. This service is a singleton and both of its caches outlive the
  /// widgets, so whichever consumer asks second is answered from memory.
  ///
  /// It is not done when the detail page loads either. That would put a TMDB
  /// search on the critical path of every page open, including the ones nobody
  /// stays on long enough to see a trailer, and the detail response is cached
  /// per provider URL so the same film reached through two providers would pay
  /// for it twice.
  Future<TrailerResult?> resolveFor(TrailerQuery query) async {
    final id = query.youtubeId ?? await _titles.youtubeIdFor(query);
    if (id == null) return null;
    return resolve(id);
  }

  /// The playable stream for [youtubeId], or null when it cannot be resolved.
  Future<TrailerResult?> resolve(String youtubeId) async {
    final id = youtubeId.trim();
    if (id.isEmpty) return null;

    final cached = _cache[id];
    if (cached != null) {
      if (DateTime.now().difference(cached.at) < TrailerResult.freshness) {
        return cached.result;
      }
      _cache.remove(id);
    }

    try {
      final result = await _resolve(id);
      _remember(id, result);
      return result;
    } catch (e) {
      // A failed lookup is not an error worth surfacing: the button simply
      // does not appear. Caching the null matters more than the log — without
      // it, every rebuild of the detail page tries again.
      debugPrint('TrailerService: could not resolve $id ($e)');
      _remember(id, null);
      return null;
    }
  }

  Future<TrailerResult?> _resolve(String id) async {
    final videoId = VideoId(id);

    // Metadata and streams in parallel: they are independent requests and the
    // button is waiting on both.
    final results = await Future.wait([
      _yt.videos.get(videoId),
      _yt.videos.streamsClient.getManifest(videoId),
    ]);
    final video = results[0] as Video;
    final manifest = results[1] as StreamManifest;

    // Muxed, because it is a single URL carrying both tracks. The adaptive
    // streams are higher quality but arrive as separate video and audio, and
    // combining them needs machinery a trailer button does not justify.
    final muxed = manifest.muxed.sortByVideoQuality();
    if (muxed.isEmpty) return null;

    // sortByVideoQuality puts the best first, so the first one at or below the
    // cap is the best acceptable one. `muxed.last` is the lowest quality, and
    // is the right fallback when everything on offer exceeds the cap.
    final stream = muxed.firstWhere(
      (s) => s.videoQuality.index <= maxQuality.index,
      orElse: () => muxed.last,
    );

    return TrailerResult(
      videoId: id,
      title: video.title,
      author: video.author,
      streamUrl: stream.url.toString(),
      thumbnail: video.thumbnails.highResUrl,
      duration: video.duration,
    );
  }

  void _remember(String id, TrailerResult? result) {
    if (_cache.length >= _maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
    _cache[id] = _CacheEntry(result, DateTime.now());
  }

  void dispose() {
    _cache.clear();
    _titles.clear();
    _yt.close();
  }
}

class _CacheEntry {
  const _CacheEntry(this.result, this.at);
  final TrailerResult? result;
  final DateTime at;
}
