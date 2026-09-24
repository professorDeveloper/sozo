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

  /// Whether the source playing is a lone adaptive stream whose master is
  /// worth reading for renditions.
  ///
  /// A label that already names a resolution came from the provider, which
  /// knows its catalogue better than a parsed manifest; and rows hung off this
  /// label mean the work is already done.
  static bool shouldExpand({
    required String label,
    required String url,
    required String? type,
    required Iterable<String> siblingLabels,
  }) {
    if (url.isEmpty) return false;
    if (VideoOptionGroups.resolutionOf(label) != null) return false;
    final kind = type?.toLowerCase();
    final looksHls =
        kind == 'hls' || kind == 'm3u8' || url.toLowerCase().contains('.m3u8');
    if (!looksHls) return false;
    final prefix = '$label · ';
    return !siblingLabels.any(
      (l) => l.startsWith(prefix) && VideoOptionGroups.resolutionOf(l) != null,
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
