import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/player/local_hls_proxy.dart';

/// The same AVPlayer-shaped probes as local_hls_proxy_avplayer_test.dart, but
/// against the live uzmovi CDN, because the mock upstream can only answer the
/// way we assumed the real one does.
///
/// Off unless `SOZO_LIVE_UZMOVI=1` is in the environment: it needs the network,
/// a healthy backend and a film that is still on the site, none of which belong
/// in the ordinary suite. Run it with
/// `SOZO_LIVE_UZMOVI=1 flutter test test/core/player/local_hls_proxy_live_uzmovi_test.dart`.
void main() {
  final live = Platform.environment['SOZO_LIVE_UZMOVI'] == '1';

  test('the live uzmovi stream survives AVPlayer-shaped requests', () async {
    final api = Dio(BaseOptions(validateStatus: (_) => true));
    final resolve = await api.get<Map<String, dynamic>>(
      'https://apisozo.azamov.me/api/contents/media',
      queryParameters: {
        'provider': 'uzmovi',
        'ref':
            'https://uzmovi.net/comediy/'
            '4014-shrek-1-uzbek-ozbek-tilida-onlayn-korish.html',
      },
    );
    expect(resolve.statusCode, 200);
    final source = (resolve.data!['videoSources'] as List).first as Map;
    final proxy = LocalHlsProxy(Dio(BaseOptions(validateStatus: (_) => true)));
    addTearDown(proxy.dispose);

    final playlistUrl = await proxy.register(
      upstreamUrl: source['videoUrl'] as String,
      headers: Map<String, String>.from(
        (source['headers'] as Map).cast<String, String>(),
      ),
      localProxy: Map<String, dynamic>.from(source['localProxy'] as Map),
      requestTransform: Map<String, dynamic>.from(
        (source['requestTransform'] as Map?) ?? const {},
      ),
    );

    final playlistHead = await _request(playlistUrl, method: 'HEAD');
    expect(playlistHead.statusCode, 200);
    expect(playlistHead.headers['content-type'], contains('mpegurl'));
    expect(int.parse(playlistHead.headers['content-length']!), greaterThan(0));
    expect(playlistHead.bytes, isEmpty);

    final playlist = await _request(playlistUrl);
    expect(playlist.statusCode, 200);
    final text = String.fromCharCodes(playlist.bytes);
    expect(text, startsWith('#EXTM3U'));
    final segmentPath = text
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty && !l.startsWith('#'));
    final segment = Uri.parse(playlistUrl).resolve(segmentPath).toString();

    final segmentHead = await _request(segment, method: 'HEAD');
    expect(segmentHead.statusCode, 200);
    final total = int.parse(segmentHead.headers['content-length']!);
    expect(total, greaterThan(0));
    expect(segmentHead.headers['accept-ranges'], 'bytes');
    expect(segmentHead.bytes, isEmpty);

    final probe = await _request(segment, headers: const {
      'Range': 'bytes=0-1',
    });
    expect(probe.statusCode, 206);
    expect(probe.headers['content-length'], '2');
    expect(probe.headers['content-range'], 'bytes 0-1/$total');
    expect(probe.bytes.length, 2);

    final open = await _request(segment, headers: const {'Range': 'bytes=0-'});
    expect(open.statusCode, 206);
    expect(open.headers['content-range'], 'bytes 0-${total - 1}/$total');
    expect(open.bytes.length, total);

    final plain = await _request(segment);
    expect(plain.statusCode, 200);
    expect(plain.headers['content-length'], '$total');
    expect(plain.bytes.length, total);

    final again = await _request(segment, headers: const {'Range': 'bytes=0-'});
    expect(again.statusCode, 206);
    expect(again.bytes.length, total);

    // The assertions above are our reading of what AVFoundation needs. Point
    // `SOZO_AVPROBE` at a binary that hands the URL to an AVPlayerItem and
    // exits non-zero unless it reaches readyToPlay, and the stream is judged
    // by the media stack itself instead. Only macOS has one, so it stays
    // optional rather than becoming a second thing the suite needs.
    final avprobe = Platform.environment['SOZO_AVPROBE'];
    if (avprobe != null && avprobe.isNotEmpty) {
      final run = await Process.run(avprobe, [playlistUrl]);
      // Printed either way: when the probe does play the stream, what it
      // reports is the only direct evidence in this suite that AVFoundation
      // and not just our reading of it is satisfied.
      debugPrint('[AVPROBE] ${run.stdout}'.trim());
      expect(
        run.exitCode,
        0,
        reason: 'AVFoundation would not play the proxied stream: '
            '${run.stdout}${run.stderr}',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 3)), skip: !live);
}

Future<_Res> _request(
  String url, {
  String method = 'GET',
  Map<String, String> headers = const {},
}) async {
  final client = HttpClient();
  try {
    final req = await client.openUrl(method, Uri.parse(url));
    headers.forEach(req.headers.set);
    final res = await req.close();
    final out = <int>[];
    await for (final chunk in res) {
      out.addAll(chunk);
    }
    final map = <String, String>{};
    res.headers.forEach((name, values) {
      map[name.toLowerCase()] = values.join(',');
    });
    return _Res(statusCode: res.statusCode, headers: map, bytes: out);
  } finally {
    client.close();
  }
}

class _Res {
  const _Res({
    required this.statusCode,
    required this.headers,
    required this.bytes,
  });

  final int statusCode;
  final Map<String, String> headers;
  final List<int> bytes;
}
