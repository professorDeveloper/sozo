/// Reading the renditions out of an HLS master playlist.
///
/// Shared because two places need the same answer and disagreed: the player
/// built its quality menu from the master, while the downloader took whichever
/// variant happened to be listed first. Packagers commonly list the lowest
/// bitrate first — a client is meant to start conservatively and adapt — so
/// "first" meant a film downloaded at 480p while the player was happily showing
/// 1080p of the very same stream.
library;

/// One rendition: the height a viewer would call it, and where it lives.
typedef HlsVariant = ({int height, String url});

final _namedHeight = RegExp(r'[-_/]s(\d{3,4})p\b');
final _resolution = RegExp(r'RESOLUTION=\d+x(\d+)');

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

    out.add((height: height, url: base.resolve(uri).toString()));
  }
  // Best first. A master often carries one resolution twice at different
  // bitrates; callers that show a list dedupe by height, callers that just want
  // the best do not care which of the two they get.
  out.sort((a, b) => b.height.compareTo(a.height));
  return out;
}
