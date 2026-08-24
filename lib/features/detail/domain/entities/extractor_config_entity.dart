class ExtractorConfigEntity {
  final String mode;
  final String hostPattern;
  final List<String> urlPatterns;
  final List<String> captureHeaders;

  /// Ad/analytics hosts to swallow so the page settles and no ad creative is
  /// mistaken for the feature. Server-supplied, on top of the extractor's own
  /// baseline list — the app must not need to know which site it is talking to.
  final List<String> blockHosts;
  final int timeoutMs;
  final String? loginUrl;
  final String playType;

  /// How to turn the url that was sniffed into the one worth playing.
  ///
  /// Some players ask for a single rendition and never for the master, so what
  /// the sniffer sees is one fixed quality — the ladder exists, the page just
  /// never requests it. When the master's url is derivable from the variant's,
  /// the server says so here rather than the app knowing which site it is.
  ///
  /// Server-supplied and always optional; without it the sniffed url is played
  /// exactly as captured.
  final UrlRewrite? rewrite;

  const ExtractorConfigEntity({
    required this.hostPattern,
    required this.urlPatterns,
    this.mode = 'shouldInterceptRequest',
    this.captureHeaders = const [],
    this.blockHosts = const [],
    this.timeoutMs = 20000,
    this.loginUrl,
    this.playType = 'hls',
    this.rewrite,
  });
}

/// A regex substitution applied to a sniffed url.
class UrlRewrite {
  final String pattern;
  final String replace;

  /// Fetch the rewritten url before trusting it, and fall back to the original
  /// unless it answers as a playlist. A derived url is a guess about someone
  /// else's naming; a guess that 404s must not cost the user their playback.
  final bool verify;

  const UrlRewrite({
    required this.pattern,
    required this.replace,
    this.verify = true,
  });

  /// The rewritten url, or null when the pattern does not apply.
  String? apply(String url) {
    try {
      final re = RegExp(pattern);
      if (!re.hasMatch(url)) return null;
      final out = url.replaceFirst(re, replace);
      return out == url ? null : out;
    } catch (_) {
      return null;
    }
  }
}
