import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/network/media_request_headers.dart';
import 'package:soplay/core/network/user_agent.dart';

void main() {
  final cdn = Uri.parse('https://cdn.example.net/hls/master.m3u8');

  test('a source that names only a Referer still goes out as the app', () {
    final headers = mediaRequestHeaders(cdn, const {
      'Referer': 'https://site.example.org/',
    });
    expect(headers['User-Agent'], kSozoUserAgent);
    expect(headers['Accept'], '*/*');
    expect(headers['Referer'], 'https://site.example.org/');
    expect(headers['Sec-Fetch-Site'], 'cross-site');
    expect(headers['Sec-Fetch-Mode'], 'cors');
  });

  test('the source wins, whatever case it writes a name in', () {
    final headers = mediaRequestHeaders(cdn, const {
      'user-agent': 'Plugin/1.0',
      'sec-fetch-site': 'same-origin',
    });
    final agents = headers.keys.where((k) => k.toLowerCase() == 'user-agent');
    expect(agents, ['user-agent']);
    expect(headers['user-agent'], 'Plugin/1.0');
    expect(headers['sec-fetch-site'], 'same-origin');
    expect(headers.containsKey('Sec-Fetch-Site'), isFalse);
  });

  test('a provider default Referer applies only when the source has none', () {
    expect(
      mediaRequestHeaders(cdn, const {}, provider: 'asilmedia')['Referer'],
      'https://asilmedia.org/',
    );
    expect(
      mediaRequestHeaders(cdn, const {
        'referer': 'https://other.example/',
      }, provider: 'AsilMedia'),
      isNot(contains('Referer')),
    );
    expect(mediaRequestHeaders(cdn, const {}), isNot(contains('Referer')));
  });

  test('the app\'s own loopback proxies get the source headers as they are', () {
    final local = Uri.parse('http://127.0.0.1:4100/p/abc/https/cdn/x.m3u8');
    expect(mediaRequestHeaders(local, const {'Range': 'bytes=0-'}), {
      'Range': 'bytes=0-',
    });
  });

  test('applying it twice changes nothing', () {
    final once = mediaRequestHeaders(cdn, const {'Referer': 'https://a.b/'});
    expect(mediaRequestHeaders(cdn, once), once);
  });
}
