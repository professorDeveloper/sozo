import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/detail/domain/download_choices.dart';
import 'package:soplay/features/detail/domain/entities/video_source_entity.dart';

void main() {
  const proxied = 'http://127.0.0.1:40123/hls/ab12/v/master.m3u8?t=1';
  const source = VideoSourceEntity(
    quality: '1080p',
    videoUrl: 'https://cdn.test/v/master.m3u8?t=1',
    isDefault: true,
    accessible: true,
    type: 'hls',
  );

  test('the local HLS proxy is recognised, the torrent stream is not', () {
    expect(DownloadChoices.isLocalProxyUrl(proxied), isTrue);
    expect(
      DownloadChoices.isLocalProxyUrl('http://localhost:9/hls/x/a.m3u8'),
      isTrue,
    );
    expect(
      DownloadChoices.isLocalProxyUrl('http://127.0.0.1:8090/stream/film.mkv'),
      isFalse,
    );
    expect(
      DownloadChoices.isLocalProxyUrl('https://cdn.test/hls/x/a.m3u8'),
      isFalse,
    );
  });

  test('a proxied stream offers the url the proxy fetches, not 127.0.0.1', () {
    final offers = DownloadChoices.from(
      sources: const [source],
      currentIndex: 0,
      currentUrl: proxied,
      currentHeaders: const {},
      hasDirective: false,
      currentUpstreamUrl: 'https://cdn.test/v/master.m3u8?t=1',
      currentUpstreamHeaders: const {'Referer': 'https://site.test/'},
    );
    expect(offers, hasLength(1));
    expect(offers.single.url, 'https://cdn.test/v/master.m3u8?t=1');
    expect(offers.single.headers, {'Referer': 'https://site.test/'});
    expect(offers.single.isCurrent, isTrue);
  });

  test('without an upstream url, or when not proxied, nothing changes', () {
    final bare = DownloadChoices.from(
      sources: const [source],
      currentIndex: 0,
      currentUrl: proxied,
      currentHeaders: const {},
      hasDirective: false,
    );
    expect(bare.first.url, proxied);

    final direct = DownloadChoices.from(
      sources: const [source],
      currentIndex: 0,
      currentUrl: 'https://cdn.test/signed.m3u8?sig=2',
      currentHeaders: const {'Referer': 'r'},
      hasDirective: false,
      currentUpstreamUrl: 'https://cdn.test/unsigned.m3u8',
    );
    // A signed url is not swapped for the unsigned file it came from.
    expect(direct.first.url, 'https://cdn.test/signed.m3u8?sig=2');
    expect(direct.first.headers, {'Referer': 'r'});
  });
}
