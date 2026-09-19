/// The `Sec-Fetch-*` headers a browser attaches and an HTTP client does not.
///
/// This is not cosmetic. A CDN behind Cloudflare was serving the master
/// playlist happily and refusing every SEGMENT with a 403 — the same block
/// whatever User-Agent, Referer or cookie jar was sent — and measured against
/// the live host, the single header that cleared it was `Sec-Fetch-Site`. The
/// rule is looking for fetch metadata, which every real browser attaches to
/// every subresource request and no bare HTTP client sends at all. So the
/// player was refused on a request the same device's browser is allowed to
/// make, and an episode "loaded, retried three times and errored" on a source
/// that plays fine in a browser.
///
/// The value is computed the way a browser computes it rather than pinned to
/// `same-origin`. The header is a CLAIM about the relationship between the page
/// and the request; a CDN on another host is genuinely cross-site, and stating
/// otherwise is the same kind of lie as a hard-coded User-Agent — the thing
/// these rules exist to catch.
library;

/// `none`, `same-origin`, `same-site` or `cross-site`, as a browser would
/// label the step from [referer] to [uri].
String fetchSite(String? referer, Uri uri) {
  if (referer == null || referer.isEmpty) return 'none';
  final from = Uri.tryParse(referer);
  if (from == null || from.host.isEmpty) return 'none';
  if (from.host == uri.host && from.scheme == uri.scheme) return 'same-origin';
  return _registrable(from.host) == _registrable(uri.host)
      ? 'same-site'
      : 'cross-site';
}

/// The registrable domain, approximated by the last two labels.
///
/// Good enough for the distinction being drawn here, and wrong only for
/// multi-part public suffixes like `co.uk`, where it errs towards `same-site`
/// for two unrelated hosts. The consequence of being wrong either way is a
/// header a server may ignore; a full public-suffix list is not worth carrying
/// for it.
String _registrable(String host) {
  final parts = host.split('.');
  return parts.length < 2 ? host : parts.sublist(parts.length - 2).join('.');
}

/// Adds the trio to [headers], unless the caller set any of them itself.
///
/// All or nothing: a source that has worked out what its CDN wants knows
/// better than a default, and half-overwriting the set is its own fingerprint.
/// Dest and Mode describe a script-driven media fetch, which is what an HLS
/// player is — a native `<video>` would say `video`/`no-cors`, but the request
/// being imitated is the one an in-page player makes.
void addFetchMetadata(Map<String, String> headers, Uri uri) {
  if (headers.keys.any((k) => k.toLowerCase().startsWith('sec-fetch-'))) {
    return;
  }
  final referer = headers.entries
      .where((e) => e.key.toLowerCase() == 'referer')
      .map((e) => e.value)
      .firstOrNull;
  headers['Sec-Fetch-Dest'] = 'empty';
  headers['Sec-Fetch-Mode'] = 'cors';
  headers['Sec-Fetch-Site'] = fetchSite(referer, uri);
}
