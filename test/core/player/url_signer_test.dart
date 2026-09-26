// A file the device signs itself: asked with the player's own User-Agent,
// read out of the host's JSON map, and not asked twice.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/player/url_signer.dart';

void main() {
  late HttpServer server;
  final asked = <({String file, String? ua, String? referer})>[];

  setUp(() async {
    asked.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final file = req.uri.queryParameters['u[]'] ?? '';
      asked.add((
        file: file,
        ua: req.headers.value('user-agent'),
        referer: req.headers.value('referer'),
      ));
      req.response.headers.contentType = ContentType.json;
      req.response.write(
        jsonEncode(
          file.isEmpty ? {} : {file: '$file?token=abc&ua=${asked.last.ua}'},
        ),
      );
      await req.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  UrlSigner signer() => UrlSigner.fromJson({
    'url': 'http://127.0.0.1:${server.port}/fayllar-sign.php',
    'param': 'u[]',
    'headers': {'Referer': 'https://asilmedia.org/'},
  })!;

  test(
    'signs with the player\'s own User-Agent and the host\'s headers',
    () async {
      final signed = await signer().sign(
        "https://fayllar1.ru/9/Film%20720p%20O'zbek.mp4",
        {'User-Agent': 'PlayerUA/1'},
      );
      expect(
        signed,
        "https://fayllar1.ru/9/Film 720p O'zbek.mp4?token=abc&ua=PlayerUA/1",
      );
      // Sent decoded, as the page itself sends it.
      expect(asked.single.file, "https://fayllar1.ru/9/Film 720p O'zbek.mp4");
      expect(asked.single.referer, 'https://asilmedia.org/');
    },
  );

  test('asks once per file and User-Agent', () async {
    final s = signer();
    await s.sign('https://fayllar1.ru/9/a.mp4', {'User-Agent': 'X'});
    await s.sign('https://fayllar1.ru/9/a.mp4', {'User-Agent': 'X'});
    expect(asked, hasLength(1));
    await s.sign('https://fayllar1.ru/9/a.mp4', {'User-Agent': 'Y'});
    expect(asked, hasLength(2));
  });

  test('no signer without a url and a parameter', () {
    expect(UrlSigner.fromJson(const {}), isNull);
    expect(UrlSigner.fromJson(const {'url': 'https://x'}), isNull);
  });
}
