// A download has to say exactly what it is about to fetch.
//
// The renditions list came off the master playlist as bare heights, and a
// master routinely carries the same resolution two or three times at different
// bitrates. Rendered raw that is "1080p, 1080p, 720p, 720p": rows identical on
// screen, that are not the same file, with no way to tell which one you are
// choosing or which is actually better.
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/player/hls_variants.dart';

const _base = 'https://cdn.test/movie/';

List<HlsVariant> parse(String body) =>
    parseHlsVariants(body, Uri.parse('${_base}master.m3u8'));

void main() {
  group('a rendition carries its bitrate', () {
    test('BANDWIDTH is read', () {
      final v = parse(
        '#EXTM3U\n'
        '#EXT-X-STREAM-INF:BANDWIDTH=4000000,RESOLUTION=1920x1080\n1080/i.m3u8\n',
      );
      expect(v.single.height, 1080);
      expect(v.single.bandwidth, 4000000);
    });

    test('AVERAGE-BANDWIDTH is not mistaken for it', () {
      // The average contains the substring BANDWIDTH, so a naive pattern picks
      // it up and ranks two renditions by the wrong number.
      final v = parse(
        '#EXTM3U\n'
        '#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=1000000,BANDWIDTH=5000000,'
        'RESOLUTION=1920x1080\n1080/i.m3u8\n',
      );
      expect(v.single.bandwidth, 5000000);
    });

    test('a packager that declares none leaves it at zero', () {
      final v = parse(
        '#EXTM3U\n#EXT-X-STREAM-INF:RESOLUTION=1280x720\n720/i.m3u8\n',
      );
      expect(v.single.bandwidth, 0);
    });
  });

  group('ordering', () {
    const twoOf1080 =
        '#EXTM3U\n'
        '#EXT-X-STREAM-INF:BANDWIDTH=2000000,RESOLUTION=1920x1080\n1080lo/i.m3u8\n'
        '#EXT-X-STREAM-INF:BANDWIDTH=8000000,RESOLUTION=1920x1080\n1080hi/i.m3u8\n'
        '#EXT-X-STREAM-INF:BANDWIDTH=900000,RESOLUTION=854x480\n480/i.m3u8\n';

    test('best height first', () {
      expect(parse(twoOf1080).map((v) => v.height), [1080, 1080, 480]);
    });

    test('and the better bitrate first within a height', () {
      // This is what makes "just take the first one" mean "take the best one".
      // Packagers commonly list the LOWEST bitrate first, because a client is
      // meant to start conservatively and adapt.
      final v = parse(twoOf1080);
      expect(v.first.url, '${_base}1080hi/i.m3u8');
      expect(v.first.bandwidth, 8000000);
    });

    test('bestPerHeight keeps one row per resolution, the good one', () {
      final v = bestPerHeight(parse(twoOf1080));
      expect(v.map((x) => x.height), [1080, 480]);
      expect(v.first.url, '${_base}1080hi/i.m3u8');
    });
  });

  group('what the row reads', () {
    test('height and bitrate together', () {
      expect(
        describeVariant((height: 1080, bandwidth: 4000000, url: 'u')),
        '1080p · 4.0 Mbps',
      );
    });

    test('a big bitrate drops the decimal', () {
      expect(
        describeVariant((height: 2160, bandwidth: 24000000, url: 'u')),
        '2160p · 24 Mbps',
      );
    });

    test('a small one is shown in kbps', () {
      expect(
        describeVariant((height: 480, bandwidth: 900000, url: 'u')),
        '480p · 900 kbps',
      );
    });

    test('and with no bitrate it is just the height', () {
      // Never "1080p · 0 Mbps": a number nobody declared is worse than no
      // number at all.
      expect(describeVariant((height: 1080, bandwidth: 0, url: 'u')), '1080p');
    });
  });

  test('a media playlist offers no renditions', () {
    // Segments rather than #EXT-X-STREAM-INF — the caller's signal that the
    // url it already has IS the thing to download.
    final v = parse(
      '#EXTM3U\n#EXTINF:10.0,\nseg0.ts\n#EXTINF:10.0,\nseg1.ts\n',
    );
    expect(v, isEmpty);
  });

  test('a rendition with no height at all is skipped', () {
    // An audio-only or subtitle rendition has no business in a quality list.
    final v = parse(
      '#EXTM3U\n'
      '#EXT-X-STREAM-INF:BANDWIDTH=64000,CODECS="mp4a.40.2"\naudio/i.m3u8\n'
      '#EXT-X-STREAM-INF:BANDWIDTH=4000000,RESOLUTION=1920x1080\n1080/i.m3u8\n',
    );
    expect(v.map((x) => x.height), [1080]);
  });
}
