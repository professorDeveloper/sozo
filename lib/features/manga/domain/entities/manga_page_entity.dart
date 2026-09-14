class MangaPageEntity {
  final int index;

  final String imageUrl;

  /// `Cookie:` header value for this page's image host, when the source had
  /// cookies for it.
  ///
  /// Per-page rather than shared with the chapter's headers because image CDNs
  /// often sit on a different host than the API, and one host's cookies must
  /// not be sent to another. Null means "no cookies for this host" — which is
  /// the normal case for sources that are not behind Cloudflare.
  final String? cookie;

  /// What to cache this image under, when [imageUrl] is not a stable identity.
  ///
  /// Pages are served from a loopback port that changes every run, so caching
  /// by url would miss on every launch and fill the disk with duplicates. The
  /// source's own image url is the thing that does not change.
  final String? cacheKey;
  final Map<String, String> headers;

  const MangaPageEntity({
    required this.index,
    required this.imageUrl,
    this.cookie,
    this.cacheKey,
    this.headers = const {},
  });
}
