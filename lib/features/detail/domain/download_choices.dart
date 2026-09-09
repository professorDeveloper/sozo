import 'package:soplay/core/player/source_ladder.dart';
import 'package:soplay/features/detail/domain/entities/video_source_entity.dart';
import 'package:soplay/features/detail/domain/video_option_groups.dart';

/// One offer in the download picker.
class DownloadChoice {
  const DownloadChoice({
    required this.url,
    required this.headers,
    required this.label,
    required this.detail,
    required this.isCurrent,
    this.needsSniff = false,
    this.sizeBytes,
  });

  final String url;

  /// The headers THIS mirror needs, not the playing one's.
  ///
  /// Mirrors gate on their own Referer and User-Agent, so sending the current
  /// stream's headers to a sibling host is how a picked download 403s. The
  /// current offer carries the resolved (post-sniff) headers; every other one
  /// carries what its own source declared.
  final Map<String, String> headers;

  /// The host — "DoodStream", "Voe". What a viewer recognises.
  final String label;

  /// Everything else worth knowing before committing to a file:
  /// "720p · HLS", "Direct", "1080p · h265 · 2.1 GB".
  final String detail;

  /// Whether this is the stream on screen. Marked because it is the one offer
  /// guaranteed to work — see [DownloadChoices.from].
  final bool isCurrent;

  /// Whether [url] is an embed PAGE that must be sniffed before it can be
  /// handed to the downloader.
  ///
  /// True only for a non-playing mirror under an extractor directive. The
  /// caller runs the same WebView extraction playback runs, then downloads the
  /// stream that comes back. Offering these was the alternative to telling
  /// somebody they may only keep the quality they happen to be watching.
  final bool needsSniff;

  final int? sizeBytes;
}

/// Which sources a viewer may download, given what is playing.
///
/// Downloading used to take `_videoUrl` and nothing else: whatever was on
/// screen. Somebody watching 480p to save data had no way to keep the 1080p
/// without first switching playback to it, waiting for it to load, and only
/// then pressing download.
///
/// The catch is that when the resolve carries an extractor directive the urls
/// in the list are embed PAGES: the playable stream exists only after a WebView
/// has sniffed it, and the downloader does no sniffing, so handing it one saves
/// an HTML document with a .mp4 name. Those mirrors are therefore offered with
/// [DownloadChoice.needsSniff] set, and the caller runs the same extraction
/// playback runs before queueing the file. Refusing them outright — the first
/// version of this — meant the sheet had one row and never opened on the
/// providers that carry a directive, which is most of them.
///
/// Pure: entities in, offers out, no Flutter and no I/O.
abstract final class DownloadChoices {
  /// Human bytes, or null when the source did not state a size.
  static String? formatSize(int? bytes) {
    if (bytes == null || bytes <= 0) return null;
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    // A decimal earns its place under 10 and stops helping above it:
    // "1.5 MB" is worth knowing, "16.0 GB" just reads worse than "16 GB".
    final text = value >= 10 || unit == 0
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
    return '$text ${units[unit]}';
  }

  /// Whether a resolve's own top-level url may be handed to the downloader.
  ///
  /// Under an extractor directive it may NOT: that url is the embed PAGE, and
  /// the playable stream only exists after a WebView has sniffed it.
  /// [DownloadService] does no sniffing, so downloading it saves an HTML
  /// document under a video's name — a file that completes, sits in the list,
  /// and fails the first time it is opened.
  ///
  /// For the player this question does not arise: it offers embed mirrors with
  /// [DownloadChoice.needsSniff] and resolves the pick. The episode list and the
  /// detail page have no sniff step and no place to show one, so for them an
  /// embed url is simply refused, with advice to play it once first.
  static bool isDownloadableUrl({
    required String url,
    required String? type,
    required bool hasDirective,
  }) {
    if (url.isEmpty) return false;
    // What the url IS decides this, not whether a directive travelled with the
    // response. Providers like videasy and rareanimes attach an extractor block
    // as a FALLBACK while still returning a real manifest, and marking every
    // such response undownloadable broke downloads that had always worked.
    // They say which they sent: `iframe` for the embed page, `hls` for the
    // manifest.
    final kind = type?.toLowerCase();
    if (kind == 'iframe') return false;
    // Unknown shape plus an expected sniff is the one case worth refusing on
    // the directive alone — there is nothing else to go on.
    if (kind == null && hasDirective) return false;
    return true;
  }

  /// The offers, best first, current stream included.
  ///
  /// [currentUrl] is the RESOLVED url — post-sniff where a sniff happened —
  /// which is why the playing source can always be offered even under a
  /// directive.
  static List<DownloadChoice> from({
    required List<VideoSourceEntity> sources,
    required int currentIndex,
    required String? currentUrl,
    required Map<String, String> currentHeaders,
    required bool hasDirective,
  }) {
    final offers = <DownloadChoice>[];
    final seen = <String>{};

    void add(
      VideoSourceEntity? s,
      String url, {
      required bool isCurrent,
      required Map<String, String> headers,
      bool needsSniff = false,
    }) {
      if (url.isEmpty || !seen.add(url)) return;
      offers.add(
        DownloadChoice(
          url: url,
          headers: headers,
          label: _labelFor(s),
          detail: _detailFor(s),
          isCurrent: isCurrent,
          needsSniff: needsSniff,
          sizeBytes: s?.sizeBytes,
        ),
      );
    }

    // The playing stream leads: it is resolved, so it is the one offer that
    // cannot be an embed page.
    final current =
        (currentIndex >= 0 && currentIndex < sources.length)
            ? sources[currentIndex]
            : null;
    if (currentUrl != null) {
      // The resolved headers, which is what the sniff produced where one ran.
      add(current, currentUrl, isCurrent: true, headers: currentHeaders);
    }

    // Under a directive every other url is an embed page rather than a stream.
    // They are still offered — flagged, so the caller sniffs the chosen one the
    // way playback does. Refusing them meant that on the fourteen providers
    // that carry a directive the sheet had a single row and never opened, and
    // you could only ever keep the quality you happened to be watching.
    for (var i = 0; i < sources.length; i++) {
      if (i == currentIndex) continue;
      final s = sources[i];
      if (!SourceLadder.isPlayable(s, hasDirective: hasDirective)) continue;
      add(
        s,
        s.videoUrl,
        isCurrent: false,
        headers: s.headers,
        needsSniff: hasDirective,
      );
    }
    return offers;
  }

  static String _labelFor(VideoSourceEntity? s) {
    if (s == null) return '';
    final mirror = s.mirror?.trim();
    if (mirror != null && mirror.isNotEmpty) return mirror;
    final server = VideoOptionGroups.serverOf(s.quality).trim();
    if (server.isNotEmpty) return server;
    return s.quality;
  }

  /// The parts that change the file you end up with, in the order they matter.
  static String _detailFor(VideoSourceEntity? s) {
    if (s == null) return '';
    final parts = <String>[];

    final quality = VideoOptionGroups.qualityOf(s.quality).trim();
    if (quality.isNotEmpty) parts.add(quality);

    // Named because the two behave differently offline: a progressive file is
    // one download, an HLS playlist is a manifest plus its segments.
    final type = s.type?.toLowerCase();
    if (type == 'hls' || type == 'm3u8') {
      parts.add('HLS');
    } else if (type == null || type == 'mp4' || type == 'video') {
      parts.add('Direct');
    }

    if (s.codec != null) parts.add(s.codec!);
    if (s.hdr == 'dv') parts.add('Dolby Vision');
    if (s.atmos) parts.add('Atmos');

    final size = formatSize(s.sizeBytes);
    if (size != null) parts.add(size);

    return parts.join(' · ');
  }
}
