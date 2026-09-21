// A CDN that only answers a signed request must never be asked directly.
//
// uzmovi's media host 301s every unsigned request to its own home page, so the
// player is handed HTML, reports "failed to open" and names a url that looks
// perfectly reasonable. The local proxy — which does work, verified against the
// live CDN — was reached only when `_currentSourceIndex` pointed at a source
// whose `videoUrl` was byte-identical to the url about to play.
//
// Both halves of that are fragile in a way that fails silently: the index is -1
// until a ladder pick lands, it is not updated when a master playlist is
// expanded into per-quality rows mid-play, and a mirror switch, a retry or a
// sniffed url all arrive with the list in a state the index no longer
// describes. For an ordinary source being wrong there costs nothing. For this
// one it costs everything.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final media = File(
    'lib/features/detail/presentation/pages/player_page.media.dart',
  ).readAsStringSync();

  test('the source is found by url, not by index', () {
    expect(media, contains('VideoSourceEntity? _sourceForUrl(String url)'));
    expect(media, contains('final source = _sourceForUrl(url);'));
  });

  test('an exact url match is preferred over everything', () {
    final body = media.substring(media.indexOf('_sourceForUrl(String url)'));
    final exact = body.indexOf('s.videoUrl == url');
    final byIndex = body.indexOf('_currentSourceIndex >=');
    final byHost = body.indexOf("Uri.tryParse(s.videoUrl)?.host == host");
    expect(exact, greaterThan(-1));
    expect(exact, lessThan(byIndex), reason: 'index checked before exact url');
    expect(byIndex, lessThan(byHost), reason: 'host checked before index');
  });

  test('a host match only ever rescues a source that asked for a proxy', () {
    // Sending an unrelated stream through another source's signing transform
    // would produce a confidently wrong request rather than an honest direct
    // one.
    final body = media.substring(media.indexOf('_sourceForUrl(String url)'));
    final hostLoop = body.substring(body.indexOf('final host = Uri.tryParse'));
    expect(hostLoop, contains('if (!s.useLocalProxy) continue;'));
  });

  test('and there is no blind fallback to source zero', () {
    final body = media.substring(
      media.indexOf('_sourceForUrl(String url)'),
      media.indexOf('Future<_ProxiedTarget?> _maybeRouteThroughLocalProxy'),
    );
    expect(body, isNot(contains('_videoSources.first')));
    expect(body, isNot(contains('_videoSources[0]')));
  });

  test('nothing claiming the url is still an honest direct play', () {
    expect(media, contains('local proxy skipped: no source carries this url'));
  });
}
