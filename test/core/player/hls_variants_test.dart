import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/player/hls_variants.dart';

const _base = 'https://cdn.example.test/hls/master.m3u8';

void main() {
  final base = Uri.parse(_base);

  test('the best rendition wins, not the first one listed', () {
    // The shape that caused the bug: packagers list the lowest bitrate first so
    // a client starts conservatively. Taking the first entry saved 480p of a
    // film the player was showing at 1080p.
    const master = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=854x480
index-s480p-v1-a1.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2400000,RESOLUTION=1280x720
index-s720p-v1-a1.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=6000000,RESOLUTION=1920x1080
index-s1080p-v1-a1.m3u8
''';
    final variants = parseHlsVariants(master, base);

    expect(variants.map((v) => v.height), [1080, 720, 480]);
    expect(variants.first.url, endsWith('index-s1080p-v1-a1.m3u8'));
  });

  test('a widescreen film is named by its packager, not its pixel height', () {
    // A 2.40:1 film encoded at 1080p carries RESOLUTION=1920x800. Ranking on
    // the pixel height alone would sort it below a true 1080p variant and call
    // it 800p in the menu.
    const master = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=6000000,RESOLUTION=1920x800
index-s1080p-v1-a1.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2400000,RESOLUTION=1280x536
index-s720p-v1-a1.m3u8
''';
    final variants = parseHlsVariants(master, base);

    expect(variants.first.height, 1080);
    expect(variants.last.height, 720);
  });

  test('RESOLUTION carries it when the uri has no name token', () {
    const master = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=854x480
low/playlist.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=6000000,RESOLUTION=1920x1080
high/playlist.m3u8
''';
    final variants = parseHlsVariants(master, base);

    expect(variants.first.height, 1080);
    expect(variants.first.url, 'https://cdn.example.test/hls/high/playlist.m3u8');
  });

  test('relative and absolute variant uris both resolve', () {
    const master = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=6000000,RESOLUTION=1920x1080
https://other.example.test/v/1080.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=854x480
../low/480.m3u8
''';
    final variants = parseHlsVariants(master, base);

    expect(variants.first.url, 'https://other.example.test/v/1080.m3u8');
    expect(variants.last.url, 'https://cdn.example.test/low/480.m3u8');
  });

  test('a directory base resolves the same as the master url', () {
    // What the downloader actually passes: `_baseOf` trims to the directory
    // and keeps the trailing slash. The two must agree or the file saved is
    // not the file the parser ranked.
    const master = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=6000000,RESOLUTION=1920x1080
index-s1080p-v1-a1.m3u8
''';
    final fromMaster = parseHlsVariants(master, base);
    final fromDir =
        parseHlsVariants(master, Uri.parse('https://cdn.example.test/hls/'));

    expect(fromDir.single.url, fromMaster.single.url);
    expect(fromDir.single.url,
        'https://cdn.example.test/hls/index-s1080p-v1-a1.m3u8');
  });

  test('a media playlist yields nothing, so the caller keeps its own url', () {
    const media = '''
#EXTM3U
#EXT-X-TARGETDURATION:10
#EXTINF:10.0,
segment0.ts
#EXTINF:10.0,
segment1.ts
#EXT-X-ENDLIST
''';
    expect(parseHlsVariants(media, base), isEmpty);
  });

  test('a variant stating neither a name nor a resolution is skipped', () {
    // Skipped rather than ranked at zero: a nameless entry sorted last would
    // still be returned when it is the only one, and the caller has a better
    // fallback than a variant it knows nothing about.
    const master = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=800000
mystery.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=6000000,RESOLUTION=1920x1080
index-s1080p-v1-a1.m3u8
''';
    final variants = parseHlsVariants(master, base);

    expect(variants, hasLength(1));
    expect(variants.single.height, 1080);
  });
}
