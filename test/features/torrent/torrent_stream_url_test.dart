import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/torrent/torrent_stream_url.dart';

/// These two decide, for every single playback in the app, whether a URL is
/// handed to ExoPlayer or to the torrent engine. A false positive sends a
/// working stream to a torrent server that will never resolve it; a false
/// negative hands ExoPlayer a magnet and produces "Source error".
void main() {
  group('TorrentStreamUrl.parse', () {
    test('reads back a URL the engine produced', () {
      final parsed = TorrentStreamUrl.parse(
        'http://127.0.0.1:8090/stream/Episode%2001.mkv'
        '?link=7287ec428ad3c76c565297c54fc8c9d2a397c63f&index=3&play',
      )!;

      expect(parsed.port, 8090);
      expect(parsed.hash, '7287ec428ad3c76c565297c54fc8c9d2a397c63f');
      expect(parsed.fileIndex, 3);
    });

    test('defaults the file index to 1, never 0', () {
      // TorrServer file ids are 1-based; index 0 is not a file.
      final parsed = TorrentStreamUrl.parse(
        'http://127.0.0.1:8090/stream/a.mkv?link=abc&play',
      )!;
      expect(parsed.fileIndex, 1);
    });

    test('refuses a remote host using the same query names', () {
      // `link` and `index` are ordinary parameter names. Polling a CDN as if it
      // were a torrent server is the failure this host check prevents.
      expect(
        TorrentStreamUrl.parse('https://cdn.example.com/stream/a.mkv?link=abc&index=1'),
        isNull,
      );
    });

    test('refuses anything that is not a stream path or has no hash', () {
      expect(
        TorrentStreamUrl.parse('http://127.0.0.1:8090/torrents?link=abc'),
        isNull,
      );
      expect(TorrentStreamUrl.parse('http://127.0.0.1:8090/stream/a.mkv'), isNull);
      expect(TorrentStreamUrl.parse(''), isNull);
      expect(TorrentStreamUrl.parse(null), isNull);
    });
  });

  group('TorrentLinks.isTorrentLink', () {
    test('recognises magnets and .torrent files', () {
      expect(TorrentLinks.isTorrentLink('magnet:?xt=urn:btih:abc'), isTrue);
      expect(TorrentLinks.isTorrentLink('MAGNET:?xt=urn:btih:abc'), isTrue);
      expect(
        TorrentLinks.isTorrentLink('https://nyaa.si/download/2150071.torrent'),
        isTrue,
      );
    });

    test('leaves ordinary streams alone', () {
      for (final url in [
        'https://cdn.example.com/video.mp4',
        'https://cdn.example.com/master.m3u8',
        'https://cdn.example.com/manifest.mpd',
        '/storage/emulated/0/Movies/a.mkv',
        '',
      ]) {
        expect(TorrentLinks.isTorrentLink(url), isFalse, reason: url);
      }
    });

    test('does not match a stream whose query merely mentions torrent', () {
      // Matching on `contains` instead of the path would send this real video
      // to the torrent engine.
      expect(
        TorrentLinks.isTorrentLink('https://cdn.example.com/v.mp4?from=torrent'),
        isFalse,
      );
      expect(
        TorrentLinks.isTorrentLink('https://cdn.example.com/v.mp4?f=a.torrent'),
        isFalse,
      );
    });

    test('does not treat the engine\'s own output as input again', () {
      // Feeding a local stream URL back in would be an infinite regress.
      expect(
        TorrentLinks.isTorrentLink(
          'http://127.0.0.1:8090/stream/a.torrent?link=abc&index=1&play',
        ),
        isFalse,
      );
    });
  });
}
