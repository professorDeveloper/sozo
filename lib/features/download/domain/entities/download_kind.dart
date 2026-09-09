/// What a download actually is on disk.
///
/// The old code answered this by looking at the url — `contains('.m3u8')` —
/// from four different places, which meant a playlist served from a url
/// without the extension was downloaded as one file and then handed to the
/// player as HLS. The kind is decided once, when the download is queued, and
/// travels with the item.
enum DownloadKind {
  /// One file: `<id>/video.<ext>`.
  video('video'),

  /// A playlist plus its segments: `<id>/index.m3u8` + `<id>/seg_N.ts`.
  hls('hls'),

  /// A folder of images: `<id>/p_000.jpg` …
  manga('manga');

  const DownloadKind(this.id);

  /// Persisted. Never rename one.
  final String id;

  static DownloadKind fromId(String? id) {
    for (final k in DownloadKind.values) {
      if (k.id == id) return k;
    }
    return DownloadKind.video;
  }

  /// What the old `kind` field held: `'video'` or `'manga'`, with HLS hidden
  /// inside `'video'` and re-detected from the url at every read.
  static DownloadKind fromLegacy(String? legacyKind, String url) {
    if (legacyKind == 'manga') return DownloadKind.manga;
    return looksLikeHls(url) ? DownloadKind.hls : DownloadKind.video;
  }

  /// The one place that decides whether a url is a playlist.
  ///
  /// Matches on the PATH rather than the whole url: these links routinely
  /// carry a `?next=…m3u8` parameter, and a `contains` over the query string
  /// sent progressive files down the segment path.
  static bool looksLikeHls(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
    return path.endsWith('.m3u8') || path.contains('.m3u8');
  }

  bool get isManga => this == DownloadKind.manga;

  /// Whether the artefact is a directory of parts rather than a single file.
  bool get isMultiPart => this != DownloadKind.video;
}

/// What the two progress counters are counting.
///
/// They used to be bytes for a direct download and segment COUNTS for HLS —
/// same fields, two meanings, decided by sniffing the url at the call site.
/// A finished HLS item then flipped from `600 / 648` to `224962314 /
/// 224962314` mid-flight, so the list showed "648 B" for a 214 MB episode.
enum DownloadUnit {
  bytes('bytes'),
  segments('segments'),
  pages('pages');

  const DownloadUnit(this.id);

  final String id;

  static DownloadUnit fromId(String? id) {
    for (final u in DownloadUnit.values) {
      if (u.id == id) return u;
    }
    return DownloadUnit.bytes;
  }

  static DownloadUnit forKind(DownloadKind kind) => switch (kind) {
        DownloadKind.video => DownloadUnit.bytes,
        DownloadKind.hls => DownloadUnit.segments,
        DownloadKind.manga => DownloadUnit.pages,
      };
}
