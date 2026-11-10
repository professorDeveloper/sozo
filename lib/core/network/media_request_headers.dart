import 'package:soplay/core/network/fetch_metadata.dart';
import 'package:soplay/core/network/http_headers.dart';
import 'package:soplay/core/network/user_agent.dart';

/// The Referer a provider's CDN wants when the source itself names none.
String? defaultMediaReferer(String? provider) {
  switch (provider?.toLowerCase()) {
    case 'asilmedia':
      return 'https://asilmedia.org/';
    default:
      return null;
  }
}

/// The headers a stream is fetched with: the app's defaults, then whatever
/// the source asked for on top, then browser fetch metadata.
///
/// One rule for the player and the downloader. The downloader used to send
/// the source's headers and nothing else, and most sources name only a
/// Referer — so the file went out under `Dalvik/2.1.0` (the Android service's
/// HttpURLConnection) or `Dart/3.x (dart:io)`, while the player had asked for
/// the same url as the device's browser. Hosts that turn a bare HTTP client
/// away with a page rather than a status served that page, and the episode
/// that played failed in Downloads as "a web page instead of the video".
///
/// Loopback urls (the app's own proxies) get the source's headers unchanged:
/// the proxy carries the upstream ones itself.
Map<String, String> mediaRequestHeaders(
  Uri uri,
  Map<String, String> sourceHeaders, {
  String? provider,
}) {
  if (uri.host == '127.0.0.1' || uri.host == 'localhost') {
    return Map.of(sourceHeaders);
  }
  final referer = defaultMediaReferer(provider);
  final merged = mergeHttpHeaders([
    {
      'User-Agent': kSozoUserAgent,
      'Accept': '*/*',
      'Accept-Language': 'uz,ru;q=0.9,en;q=0.8',
      'Referer': ?referer,
    },
    sourceHeaders,
  ]);
  addFetchMetadata(merged, uri);
  return merged;
}
