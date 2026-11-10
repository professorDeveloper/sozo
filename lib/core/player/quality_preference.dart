import 'package:soplay/features/detail/domain/video_option_groups.dart';

/// The viewer's standing answer to "which rendition do I start on".
///
/// Stored as a height, with two sentinels: [auto] leaves the choice to the
/// engine, [dataSaver] asks for the smallest thing on offer whatever it is.
abstract final class QualityPreference {
  static const int auto = 0;
  static const int dataSaver = -1;

  static const List<int> choices = [auto, 2160, 1080, 720, 480, 360, dataSaver];

  static int normalize(Object? raw) {
    final v = raw is num ? raw.toInt() : null;
    return v != null && choices.contains(v) ? v : auto;
  }

  /// The height to pin out of [available], or null to stay adaptive.
  ///
  /// The closest at or below the preference, so a 1080p preference on a
  /// 720p/480p ladder plays 720p rather than jumping to whatever is biggest;
  /// only when everything is above it does the lowest one win.
  static int? pick(Iterable<int> available, int preference) {
    final heights = {
      for (final h in available)
        if (h > 0) h,
    }.toList()..sort();
    if (heights.isEmpty || preference == auto) return null;
    if (preference == dataSaver) return heights.first;
    final atOrBelow = heights.where((h) => h <= preference);
    return atOrBelow.isNotEmpty ? atOrBelow.last : heights.first;
  }

  /// The height to pin a parsed master to, or [auto] to let the engine choose.
  ///
  /// The viewer's [preference] first — a pick, a remembered height or the
  /// standing setting. Failing that, on an engine that adapts on its own
  /// ([adaptiveEngine]: ExoPlayer, AVPlayer) the height the source's own label
  /// names. Such an engine starts a master from a bandwidth estimate, which
  /// on mobile data is the bottom rung, so a server labelled "1080p" played
  /// at 320p under a button that said 1080p. Pinning the named height makes
  /// the label true. libmpv is left alone: its Auto opens the top rendition
  /// (PlayerController.hlsBitrateFor) and never adapts afterwards.
  static int pinFor({
    required int preference,
    required int? labelledHeight,
    required bool adaptiveEngine,
  }) {
    if (preference != auto) return preference;
    if (adaptiveEngine && labelledHeight != null && labelledHeight > 0) {
      return labelledHeight;
    }
    return auto;
  }

  /// Whether the source playing is a lone adaptive stream whose master is
  /// worth reading for renditions.
  ///
  /// Provider labels can describe the maximum, even when the URL is adaptive.
  /// Read that master; existing sibling rendition rows prevent duplicate work.
  static bool shouldExpand({
    required String label,
    required String url,
    required String? type,
    required Iterable<String> siblingLabels,
  }) {
    if (url.isEmpty) return false;
    final kind = type?.toLowerCase();
    final lower = url.toLowerCase();
    final looksHls = kind == 'hls' || kind == 'm3u8' || lower.contains('.m3u8');
    final looksDash = kind == 'dash' || lower.contains('.mpd');
    if (!looksHls && !looksDash) return false;
    // Nothing to add when this server already offers resolutions: the
    // provider's own ladder ("Auto", "1080p", "720p"), or rows parsed from
    // this master before. Checking only for "<label> · …" rows missed the
    // first, and the same resolutions were listed twice.
    final server = VideoOptionGroups.serverOf(label);
    return !siblingLabels.any(
      (l) =>
          l != label &&
          VideoOptionGroups.serverOf(l) == server &&
          VideoOptionGroups.resolutionOf(l) != null,
    );
  }

  /// The height a viewer would call a decoded picture of [width]×[height].
  ///
  /// By the long side as well as the short one: a scope film at 1920×800 is
  /// what every other player calls 1080p, and 800p reads as a fault.
  static int? displayHeight(int width, int height) {
    if (width <= 0 || height <= 0) return null;
    final short = width < height ? width : height;
    final long = width < height ? height : width;
    final effective = short > long * 9 / 16 ? short : long * 9 / 16;
    for (final std in const [2160, 1440, 1080, 720, 480, 360, 240]) {
      if ((effective - std).abs() <= std * 0.08) return std;
    }
    return effective.round();
  }
}
