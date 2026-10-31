import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/player/hls_segment_filter.dart';

void main() {
  group('dropHlsSegments', () {
    // The shape of a live KKPhim playlist, 2026-10-31.
    const playlist =
        '#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-PLAYLIST-TYPE:vod\n'
        '#EXT-X-TARGETDURATION:8\n#EXT-X-MEDIA-SEQUENCE:0\n'
        '#EXTINF:4.0,\nHcTaGA8B.ts\n#EXT-X-DISCONTINUITY\n'
        '#EXTINF:4.0,\nconvertv8/R9SjR8xq.ts\n#EXT-X-DISCONTINUITY\n'
        '#EXTINF:4.0,\n8T4q13t8.ts\n#EXT-X-DISCONTINUITY\n'
        '#EXTINF:3.0,\n/v8/d61a03b1dabe537cc05ffe5c9c280f56/segment_0000.ts\n'
        '#EXTINF:2.0,\n/v8/d61a03b1dabe537cc05ffe5c9c280f56/segment_0001.ts\n'
        '#EXT-X-DISCONTINUITY\n#EXTINF:4.0,\nZFE6Zblx.ts\n#EXT-X-ENDLIST\n';
    final ad = RegExp(r'^/v\d+/[0-9a-f]{32}/');

    test('takes the ad and its timing out, and leaves the film whole', () {
      final out = dropHlsSegments(playlist, ad);
      expect(out, isNot(contains('segment_')));
      expect(out, contains('convertv8/R9SjR8xq.ts'));
      expect(RegExp('#EXTINF').allMatches(out), hasLength(4));
      expect(out, endsWith('ZFE6Zblx.ts\n#EXT-X-ENDLIST\n'));
    });

    test('the two discontinuities around the ad become one', () {
      final out = dropHlsSegments(playlist, ad);
      expect(RegExp('#EXT-X-DISCONTINUITY').allMatches(out), hasLength(3));
      expect(
        out,
        contains(
          '8T4q13t8.ts\n#EXT-X-DISCONTINUITY\n#EXTINF:4.0,\nZFE6Zblx.ts',
        ),
      );
    });

    test('a master playlist is not a list of segments', () {
      const master =
          '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\n/v8/abc/index.m3u8\n';
      expect(dropHlsSegments(master, RegExp('.')), master);
    });

    test('a rule that would empty the playlist is wrong, not the film', () {
      expect(dropHlsSegments(playlist, RegExp('.')), playlist);
    });
  });

  group('transportStreamStart', () {
    final ts = List<int>.generate(188 * 3, (i) => i % 188 == 0 ? 0x47 : 0x11);
    const png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x47, 1, 2];
    const iend = [0, 0, 0, 0, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82];

    test('finds the stream behind the image and its padding', () {
      final bytes = [...png, ...iend, ...List.filled(40, 0xFF), ...ts];
      expect(transportStreamStart(bytes), png.length + iend.length + 40);
    });

    test('a sync byte inside the padding is not the start', () {
      final bytes = [...png, ...iend, 0x47, 0xFF, 0xFF, ...ts];
      expect(transportStreamStart(bytes), png.length + iend.length + 3);
    });

    test('says so when it needs more bytes to be sure', () {
      expect(transportStreamStart([...png, ...iend, ...ts.take(100)]), isNull);
      expect(transportStreamStart(png), isNull);
    });
  });
}
