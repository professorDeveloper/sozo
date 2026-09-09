/// Reads a torrent stream URL back into the pieces that produced it.
///
/// The engine hands the player a plain URL — `http://127.0.0.1:PORT/stream/
/// {name}?link={hash}&index={n}&play` — and that is deliberate: the player has no
/// idea a torrent is involved, which is what let torrent playback ship without
/// touching the playback pipeline at all.
///
/// The cost of that design is that the player also has no *handle* on the
/// torrent, so it cannot show download speed or peer count. Rather than thread
/// a hash through `PlayerArgs` and every call site that builds one, the URL is
/// parsed back. It already carries everything needed, it stays correct for any
/// torrent stream regardless of who created it — including links that arrive
/// from a CloudStream plugin rather than Sozo's own search — and a URL that is
/// not one of ours simply does not parse.
class TorrentStreamUrl {
  const TorrentStreamUrl({
    required this.port,
    required this.hash,
    required this.fileIndex,
  });

  final int port;
  final String hash;
  final int fileIndex;

  /// Parses [url], or returns null when it is not a local torrent stream.
  ///
  /// The host check matters: `link=` and `index=` are ordinary query names that
  /// a remote CDN could use for something else entirely, and treating a real
  /// video URL as a torrent would start a poll against a server that is not
  /// there.
  static TorrentStreamUrl? parse(String? url) {
    if (url == null || url.isEmpty) return null;

    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    if (uri.host != '127.0.0.1' && uri.host != 'localhost') return null;
    if (!uri.path.startsWith('/stream/')) return null;

    final hash = uri.queryParameters['link'];
    if (hash == null || hash.isEmpty) return null;

    final port = uri.port;
    if (port <= 0) return null;

    return TorrentStreamUrl(
      port: port,
      hash: hash,
      fileIndex: int.tryParse(uri.queryParameters['index'] ?? '') ?? 1,
    );
  }
}


/// Recognises links that are torrents rather than streams.
///
/// The player funnels every URL through one place, so asking the question there
/// once covers every route in: Sozo's own torrent search, a CloudStream plugin
/// that returns a magnet, a deeplink someone pasted.
abstract final class TorrentLinks {
  /// True for magnet URIs and HTTP links to a `.torrent` file.
  ///
  /// The `.torrent` check looks at the *path* rather than the whole URL,
  /// because plenty of ordinary video links carry a query string mentioning
  /// the word — matching on `contains` would send real streams to the torrent
  /// engine.
  static bool isTorrentLink(String? url) {
    final value = url?.trim();
    if (value == null || value.isEmpty) return false;
    if (value.toLowerCase().startsWith('magnet:')) return true;

    final uri = Uri.tryParse(value);
    if (uri == null) return false;
    // A local stream URL is what the engine *produces*; feeding it back in
    // would be an infinite regress.
    if (TorrentStreamUrl.parse(value) != null) return false;
    return uri.path.toLowerCase().endsWith('.torrent');
  }
}
