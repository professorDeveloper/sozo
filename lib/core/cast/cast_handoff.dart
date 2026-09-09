/// What crosses to the receiver when an episode is handed to a television.
///
/// The hand-off carries three things a receiver cannot work out for itself: the
/// headers the CDN requires, the subtitle track the viewer is actually reading,
/// and the position they are at. Missing any one turns casting into a worse way
/// to watch — a 403, the wrong language, or starting the episode over.
///
/// The header part is a straight copy. The other two are decisions, they lived
/// inline in a widget State where neither could be exercised, and one of them
/// was wrong.
///
/// Pure: tracks and a position in, a payload description out. No Flutter, no
/// getIt, no I/O.
library;

abstract final class CastHandoff {
  /// The subtitle format a receiver should be told to expect.
  ///
  /// From the path's extension, with the query string and fragment removed
  /// first. That is the whole point of this function: the check it replaces was
  /// `file.toLowerCase().contains('.srt')`, which is true for
  /// `https://cdn.srt-host.net/track.vtt` and for any signed url whose token
  /// happens to contain those four characters. A WebVTT file announced as
  /// SubRip parses to nothing, and nothing is what the television shows —
  /// silently, with no error anywhere.
  ///
  /// WebVTT is the fallback because it is what Chromecast requires and what
  /// every backend here serves unless it says otherwise.
  static String subtitleFormatFor(String url) {
    var path = url;
    for (final cut in ['#', '?']) {
      final at = path.indexOf(cut);
      if (at >= 0) path = path.substring(0, at);
    }
    return path.toLowerCase().endsWith('.srt') ? 'srt' : 'vtt';
  }

  /// Whether a track is worth sending.
  ///
  /// An empty file is a track that was listed but never fetched; sending it
  /// gives the receiver a url it cannot load and the viewer a subtitle option
  /// that does nothing.
  static bool isSendable(String file) => file.trim().isNotEmpty;

  /// Where the receiver should start.
  ///
  /// Null on a live channel: there is no seekable timeline to start into, and a
  /// receiver told to seek on one either ignores it or drops the stream.
  /// Otherwise the viewer's own position — casting mid-episode is the common
  /// case, because the phone was the wrong screen all along.
  static Duration? startPositionFor({
    required bool isLive,
    required Duration? position,
  }) {
    if (isLive) return null;
    if (position == null || position <= Duration.zero) return null;
    return position;
  }
}
