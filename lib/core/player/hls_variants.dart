/// Reading the renditions out of an HLS master playlist.
///
/// Shared because two places need the same answer and disagreed: the player
/// built its quality menu from the master, while the downloader took whichever
/// variant happened to be listed first. Packagers commonly list the lowest
/// bitrate first — a client is meant to start conservatively and adapt — so
/// "first" meant a film downloaded at 480p while the player was happily showing
/// 1080p of the very same stream.
library;

/// One rendition: the height a viewer would call it, where it lives, and how
/// many bits per second it spends getting there.
///
/// [bandwidth] is 0 when the packager did not declare one. It is what tells two
/// renditions of the SAME height apart — a master routinely carries 1080p twice
/// at different bitrates — so it is both how the list dedupes and the only
/// honest thing to show beside a height that is otherwise identical.
typedef HlsVariant = ({int height, int bandwidth, String url});

final _namedHeight = RegExp(r'[-_/]s(\d{3,4})p\b');
final _resolution = RegExp(r'RESOLUTION=\d+x(\d+)');
final _bandwidth = RegExp(r'[^-]BANDWIDTH=(\d+)');

/// Every rendition in [playlist], best first, resolved against [base].
///
/// Returns empty for a media playlist — one with segments rather than
/// `#EXT-X-STREAM-INF` — which is the caller's signal that the url it has is
/// already the thing to download.
List<HlsVariant> parseHlsVariants(String playlist, Uri base) {
  final out = <HlsVariant>[];
  final lines = playlist.split(RegExp(r'\r?\n'));
  for (var i = 0; i < lines.length - 1; i++) {
    final tag = lines[i].trim();
    if (!tag.startsWith('#EXT-X-STREAM-INF')) continue;
    final uri = lines[i + 1].trim();
    if (uri.isEmpty || uri.startsWith('#')) continue;

    // The packager's own name for the variant beats RESOLUTION, because the two
    // disagree more often than not: a 2.40:1 film encoded at 1080p carries
    // RESOLUTION=1920x800, and naming it after the pixel height would offer
    // `800p` for the stream every other player calls 1080p. The `s1080p` token
    // in `index-s1080p-v1-a1` is what the packager called it.
    final named = _namedHeight.firstMatch(uri);
    final res = _resolution.firstMatch(tag);
    final height = int.tryParse(named?.group(1) ?? res?.group(1) ?? '') ?? 0;
    if (height <= 0) continue;

    // AVERAGE-BANDWIDTH also contains the substring BANDWIDTH, so the pattern
    // requires a non-hyphen before it: matching the average would rank two
    // renditions by the wrong number.
    final bw = int.tryParse(_bandwidth.firstMatch(tag)?.group(1) ?? '') ?? 0;

    out.add((
      height: height,
      bandwidth: bw,
      url: base.resolve(uri).toString(),
    ));
  }
  // Best first, and by bitrate within a height — so the 1080p a caller takes
  // when it just wants "the best" is the better of the two 1080p renditions
  // rather than whichever the packager happened to list first.
  out.sort((a, b) {
    final byHeight = b.height.compareTo(a.height);
    return byHeight != 0 ? byHeight : b.bandwidth.compareTo(a.bandwidth);
  });
  return out;
}

/// One rendition per height, keeping the best bitrate of each.
///
/// For a list somebody has to choose from. A master commonly offers the same
/// resolution two or three times at different bitrates, and rendering those
/// raw gives "1080p, 1080p, 720p, 720p" — rows that are identical on screen
/// and are not the same file. Since [parseHlsVariants] already orders by
/// bitrate within a height, the first of each height is the best one.
List<HlsVariant> bestPerHeight(List<HlsVariant> variants) {
  final seen = <int>{};
  return [
    for (final v in variants)
      if (seen.add(v.height)) v,
  ];
}

/// `1080p`, plus the bitrate when there is one to show.
///
/// The number alone is what a viewer calls the quality; the bitrate is what
/// makes two same-height rows distinguishable, and is the closest thing to an
/// honest answer about which is actually better.
String describeVariant(HlsVariant v) {
  if (v.bandwidth <= 0) return '${v.height}p';
  final mbps = v.bandwidth / 1000000;
  final rate = mbps >= 1
      ? '${mbps.toStringAsFixed(mbps >= 10 ? 0 : 1)} Mbps'
      : '${(v.bandwidth / 1000).round()} kbps';
  return '${v.height}p · $rate';
}
