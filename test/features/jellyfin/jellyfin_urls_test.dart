import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/jellyfin/domain/jellyfin_urls.dart';
import 'package:soplay/features/sources/domain/source_ecosystem.dart';

void main() {
  group('normalizeBaseUrl', () {
    test('adds http:// to a bare LAN address', () {
      expect(
        JellyfinUrls.normalizeBaseUrl('192.168.1.20:8096'),
        'http://192.168.1.20:8096',
      );
    });

    test('drops trailing slashes and a pasted web-client path', () {
      expect(
        JellyfinUrls.normalizeBaseUrl('https://media.example.com/web/#/home'),
        'https://media.example.com',
      );
      expect(
        JellyfinUrls.normalizeBaseUrl('http://nas:8096///'),
        'http://nas:8096',
      );
    });

    test('keeps a reverse-proxy base path', () {
      expect(
        JellyfinUrls.normalizeBaseUrl(' https://Example.com/jellyfin/web/ '),
        'https://example.com/jellyfin',
      );
    });

    test('rejects what is not an address', () {
      expect(JellyfinUrls.normalizeBaseUrl(''), '');
      expect(JellyfinUrls.normalizeBaseUrl('   '), '');
    });
  });

  test('keyParam follows the server version', () {
    expect(JellyfinUrls.keyParam('10.8.13'), 'api_key');
    expect(JellyfinUrls.keyParam('10.9.11'), 'ApiKey');
    expect(JellyfinUrls.keyParam('10.10.3'), 'ApiKey');
    expect(JellyfinUrls.keyParam('12.1.0'), 'ApiKey');
    expect(JellyfinUrls.keyParam(''), 'ApiKey');
  });

  test('authorization header carries client, device and token', () {
    final header = JellyfinUrls.authorization(
      deviceName: 'Sozo Android',
      deviceId: 'dev1',
      version: '2.0.0',
      token: 'tok',
    );
    expect(
      header,
      'MediaBrowser Client="Sozo", Device="Sozo Android", DeviceId="dev1", '
      'Version="2.0.0", Token="tok"',
    );
    expect(
      JellyfinUrls.authorization(deviceName: 'd', deviceId: 'i', version: 'v'),
      isNot(contains('Token')),
    );
  });

  test('direct stream is static, typed by container, and keyed', () {
    final url = Uri.parse(
      JellyfinUrls.directStream(
        base: 'http://nas:8096',
        itemId: 'abc',
        mediaSourceId: 'abc',
        container: 'mov,mp4,m4a',
        token: 'tok',
        keyParam: 'ApiKey',
        deviceId: 'dev',
        playSessionId: 'ps1',
      ),
    );
    expect(url.path, '/Videos/abc/stream.mov');
    expect(url.queryParameters, {
      'static': 'true',
      'MediaSourceId': 'abc',
      'DeviceId': 'dev',
      'PlaySessionId': 'ps1',
      'ApiKey': 'tok',
    });
  });

  test('hls transcode asks for H.264/AAC at the given ceiling', () {
    final url = Uri.parse(
      JellyfinUrls.hls(
        base: 'https://host/jf',
        itemId: 'abc',
        mediaSourceId: 'ms',
        token: 'tok',
        keyParam: 'api_key',
        deviceId: 'dev',
        videoBitrate: 4000000,
        maxHeight: 720,
        playSessionId: 'ps',
        audioStreamIndex: 2,
      ),
    );
    expect(url.path, '/jf/Videos/abc/master.m3u8');
    final q = url.queryParameters;
    expect(q['VideoCodec'], 'h264');
    expect(q['AudioCodec'], 'aac');
    expect(q['MaxHeight'], '720');
    expect(q['VideoBitrate'], '4000000');
    expect(q['AudioStreamIndex'], '2');
    expect(q['PlaySessionId'], 'ps');
    expect(q['api_key'], 'tok');
  });

  test('subtitle url points at the WebVTT rendition', () {
    expect(
      JellyfinUrls.subtitle(
        base: 'http://nas:8096',
        itemId: 'abc',
        mediaSourceId: 'ms',
        index: 3,
        token: 'tok',
        keyParam: 'ApiKey',
      ),
      'http://nas:8096/Videos/abc/ms/Subtitles/3/0/Stream.vtt?ApiKey=tok',
    );
  });

  test('withKey adds the key only when missing', () {
    expect(
      JellyfinUrls.withKey('http://h/a.vtt?x=1', 'ApiKey', 't'),
      'http://h/a.vtt?x=1&ApiKey=t',
    );
    expect(
      JellyfinUrls.withKey('http://h/a.m3u8?api_key=old', 'ApiKey', 't'),
      'http://h/a.m3u8?api_key=old',
    );
  });

  test('item id is recovered from any stream url, dashed or not', () {
    expect(
      JellyfinUrls.itemIdFromStreamUrl(
        'http://h/videos/b8015922-6d16-576d-4c06-13750e27c072/master.m3u8?x=1',
      ),
      'b80159226d16576d4c0613750e27c072',
    );
    expect(
      JellyfinUrls.itemIdFromStreamUrl(
        'http://h/jf/Videos/ABC123/stream.mkv?static=true',
      ),
      'abc123',
    );
    expect(JellyfinUrls.itemIdFromStreamUrl('http://h/Items/x'), isNull);
  });

  test('ticks and milliseconds convert both ways', () {
    expect(JellyfinUrls.msToTicks(const Duration(seconds: 90)), 900000000);
    expect(
      JellyfinUrls.ticksToDuration(12914650830),
      const Duration(milliseconds: 1291465),
    );
    expect(JellyfinUrls.ticksToDuration(null), Duration.zero);
  });

  test('jf: providers belong to the Jellyfin ecosystem', () {
    expect(SourceEcosystem.of('jf:f0b3381645f0'), SourceEcosystem.jellyfin);
    expect(SourceEcosystem.jellyfin.labelKey, 'sources.eco_jellyfin');
  });
}
