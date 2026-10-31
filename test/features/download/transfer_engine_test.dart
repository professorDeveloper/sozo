// The in-process downloader against a real socket: segments several at a
// time, byte-range playlists cut into their slices, and a file whose
// connection drops picking up where it stopped.
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/download/data/datasources/download_transfer_data_source.dart';
import 'package:soplay/features/download/domain/entities/download_failure.dart';
import 'package:soplay/features/download/domain/entities/download_kind.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  group('reading a playlist', () {
    test('byte ranges continue from the previous slice of the same file', () {
      const playlist = '''
#EXTM3U
#EXT-X-MAP:URI="main.mp4",BYTERANGE="700@0"
#EXTINF:4,
#EXT-X-BYTERANGE:1000@700
main.mp4
#EXTINF:4,
#EXT-X-BYTERANGE:500
main.mp4
#EXTINF:4,
other.ts
''';
      final segments = DownloadTransferDataSource.mediaSegments(
        playlist,
        'https://cdn.test/v/',
      );
      expect(segments.map((s) => s.url), [
        'https://cdn.test/v/main.mp4',
        'https://cdn.test/v/main.mp4',
        'https://cdn.test/v/other.ts',
      ]);
      expect(segments[0].range, (offset: 700, length: 1000));
      expect(segments[1].range, (offset: 1700, length: 500));
      expect(segments[2].range, isNull);

      final aux = DownloadTransferDataSource.auxiliaryUris(playlist);
      expect(aux.single.range, (offset: 0, length: 700));

      final local = DownloadTransferDataSource.localPlaylist(playlist, {
        aux.single.key: 'init_0.mp4',
      });
      expect(local, isNot(contains('BYTERANGE')));
      expect(local, contains('#EXT-X-MAP:URI="init_0.mp4"'));
      expect(local, contains('seg_0.ts'));
      expect(local, contains('seg_2.ts'));
    });
  });

  test('without heights, the highest bitrate that has a picture', () {
    const master = '''
#EXTM3U
#EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=232370,CODECS="mp4a.40.2, avc1.4d4015"
gear1/prog_index.m3u8
#EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=1927833,CODECS="mp4a.40.2, avc1.4d401f"
gear4/prog_index.m3u8
#EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=9000000,CODECS="mp4a.40.2"
audio/prog_index.m3u8
''';
    expect(
      DownloadTransferDataSource.bestByBandwidth(master, 'https://cdn.test/'),
      'https://cdn.test/gear4/prog_index.m3u8',
    );
  });

  group('against a server', () {
    late HttpServer server;
    late Directory dir;
    late String base;
    final hits = <String>[];
    var inFlight = 0;
    var peak = 0;
    // What a handler serves for a path.
    late Future<void> Function(HttpRequest) handle;

    setUp(() async {
      hits.clear();
      inFlight = 0;
      peak = 0;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      dir = await Directory.systemTemp.createTemp('sozo-transfer-');
      base = 'http://127.0.0.1:${server.port}';
      server.listen((request) async {
        hits.add(
          '${request.uri.path} ${request.headers.value('range') ?? ''}'.trim(),
        );
        inFlight++;
        if (inFlight > peak) peak = inFlight;
        try {
          await handle(request);
        } finally {
          inFlight--;
        }
      });
    });

    tearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });

    Future<TransferResult> run(DownloadKind kind, String url, {int? height}) =>
        DownloadTransferDataSource(dio: Dio()).run(
          id: 'x',
          dirPath: dir.path,
          kind: kind,
          sourceUrl: url,
          videoHeight: height,
          headers: const {},
          pageUrls: const [],
          cancel: CancelToken(),
          onProgress: (_) {},
        );

    test('segments are fetched several at a time, and all of them', () async {
      final playlist = StringBuffer('#EXTM3U\n');
      for (var i = 0; i < 12; i++) {
        playlist.write('#EXTINF:4,\ns$i.ts\n');
      }
      handle = (r) async {
        if (r.uri.path.endsWith('.m3u8')) {
          r.response.headers.contentType = ContentType(
            'application',
            'vnd.apple.mpegurl',
          );
          r.response.write(playlist);
        } else {
          await Future<void>.delayed(const Duration(milliseconds: 40));
          r.response.headers.contentType = ContentType('video', 'mp2t');
          r.response.add(List.filled(188, 0x47));
        }
        await r.response.close();
      };
      final result = await run(DownloadKind.hls, '$base/index.m3u8');
      expect(result.ok, isTrue, reason: result.detail);
      expect(result.totalUnits, 12);
      expect(peak, greaterThan(1));
      for (var i = 0; i < 12; i++) {
        expect(File('${dir.path}/seg_$i.ts').lengthSync(), 188);
      }
    });

    test(
      'a byte-range playlist saves slices, not copies of the file',
      () async {
        final media = Uint8List.fromList(List.generate(3000, (i) => i % 251));
        handle = (r) async {
          if (r.uri.path.endsWith('.m3u8')) {
            r.response.write('''
#EXTM3U
#EXT-X-MAP:URI="main.mp4",BYTERANGE="100@0"
#EXTINF:4,
#EXT-X-BYTERANGE:900@100
main.mp4
#EXTINF:4,
#EXT-X-BYTERANGE:2000
main.mp4
''');
            await r.response.close();
            return;
          }
          r.response.headers.contentType = ContentType('video', 'mp4');
          final range = r.headers.value('range');
          // The second slice is asked of a server that ignores ranges.
          if (range != null && !range.startsWith('bytes=1000')) {
            final m = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(range)!;
            final from = int.parse(m.group(1)!), to = int.parse(m.group(2)!);
            r.response.statusCode = 206;
            r.response.headers.set(
              'content-range',
              'bytes $from-$to/${media.length}',
            );
            r.response.add(media.sublist(from, to + 1));
          } else {
            r.response.add(media);
          }
          await r.response.close();
        };
        final result = await run(DownloadKind.hls, '$base/index.m3u8');
        expect(result.ok, isTrue, reason: result.detail);
        expect(
          File('${dir.path}/init_0.mp4').readAsBytesSync(),
          media.sublist(0, 100),
        );
        expect(
          File('${dir.path}/seg_0.ts').readAsBytesSync(),
          media.sublist(100, 1000),
        );
        expect(
          File('${dir.path}/seg_1.ts').readAsBytesSync(),
          media.sublist(1000, 3000),
        );
        final local = File('${dir.path}/index.m3u8').readAsStringSync();
        expect(local, isNot(contains('BYTERANGE')));
      },
    );

    test(
      'audio that is a rendition of its own is saved with the video',
      () async {
        handle = (r) async {
          final path = r.uri.path;
          if (path == '/master.m3u8') {
            r.response.write('''
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud",NAME="English",LANGUAGE="en",DEFAULT=NO,URI="audio/en.m3u8"
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud",NAME="Japanese",LANGUAGE="ja",DEFAULT=YES,URI="audio/ja.m3u8"
#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="en",URI="subs/en.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=6000000,RESOLUTION=1920x1080,AUDIO="aud",SUBTITLES="subs"
video/1080.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=900000,RESOLUTION=1280x720,AUDIO="aud",SUBTITLES="subs"
video/720.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=300000,RESOLUTION=640x360,AUDIO="aud",SUBTITLES="subs"
video/360.m3u8
''');
          } else if (path.endsWith('.m3u8')) {
            final stem = path.split('/').last.replaceAll('.m3u8', '');
            r.response.write(
              '#EXTM3U\n#EXTINF:4,\n$stem-0.ts\n#EXTINF:4,\n$stem-1.ts\n',
            );
          } else {
            r.response.headers.contentType = ContentType('video', 'mp2t');
            r.response.write(path);
          }
          await r.response.close();
        };
        final result = await run(
          DownloadKind.hls,
          '$base/master.m3u8',
          height: 720,
        );
        expect(result.ok, isTrue, reason: result.detail);
        expect(result.totalUnits, 4);
        String read(String name) =>
            File('${dir.path}/$name').readAsStringSync();
        expect(read('seg_0.ts'), '/video/720-0.ts');
        // The default track of the variant's group.
        expect(read('aud_1.ts'), '/audio/ja-1.ts');
        expect(read('audio.m3u8'), contains('aud_0.ts'));
        expect(read('video.m3u8'), contains('seg_1.ts'));
        final index = read('index.m3u8');
        expect(index, contains('NAME="Japanese"'));
        expect(index, contains('URI="audio.m3u8"'));
        expect(index, contains('DEFAULT=YES'));
        expect(index, contains('AUDIO="aud"'));
        expect(index, isNot(contains('SUBTITLES')));
        expect(index.trim().split('\n').last, 'video.m3u8');
        expect(hits, isNot(contains('/audio/en.m3u8')));
        expect(hits, isNot(contains('/video/1080.m3u8')));
      },
    );

    test('TS segments labelled text/html, as vidapi and anikoto serve them, '
        'are saved', () async {
      handle = (r) async {
        if (r.uri.path.endsWith('.m3u8')) {
          r.response.write(
            '#EXTM3U\n#EXTINF:4,\npage-0.html\n#EXTINF:4,\nseg-1-f1.html\n',
          );
        } else {
          r.response.headers.contentType = ContentType(
            'text',
            'html',
            charset: 'UTF-8',
          );
          r.response.add([0x47, 0x40, 0x00, 0x30, ...List.filled(184, 0xff)]);
        }
        await r.response.close();
      };
      final result = await run(DownloadKind.hls, '$base/index.m3u8');
      expect(result.ok, isTrue, reason: result.detail);
      expect(File('${dir.path}/seg_0.ts').readAsBytesSync().take(2), [
        0x47,
        0x40,
      ]);
      expect(File('${dir.path}/seg_1.ts').lengthSync(), 188);
    });

    test('a segment that is a real web page fails once, not three times, '
        'whatever its label', () async {
      handle = (r) async {
        if (r.uri.path.endsWith('.m3u8')) {
          r.response.write('#EXTM3U\n#EXTINF:4,\nchallenge.ts\n');
        } else {
          r.response.headers.contentType = ContentType('video', 'mp2t');
          // The markup arrives after a lone newline, in a chunk of its own.
          r.response.bufferOutput = false;
          r.response.write('\n');
          await r.response.flush();
          await Future<void>.delayed(const Duration(milliseconds: 20));
          r.response.write('<!DOCTYPE html><html>Just a moment</html>');
        }
        await r.response.close();
      };
      final result = await run(DownloadKind.hls, '$base/index.m3u8');
      expect(result.ok, isFalse);
      expect(result.failure, DownloadFailureKind.notMedia);
      expect(result.detail, startsWith('not media'));
      expect(result.detail, contains('video/mp2t'));
      expect(hits.where((h) => h == '/challenge.ts'), hasLength(1));
      expect(File('${dir.path}/seg_0.ts').existsSync(), isFalse);
    });

    test('a direct file is judged by its bytes, not its label', () async {
      final mp4 = [0, 0, 0, 24, ...'ftypmp42'.codeUnits, ...List.filled(500, 7)];
      handle = (r) async {
        if (r.uri.path == '/page.mp4') {
          r.response.headers.contentType = ContentType('video', 'mp4');
          r.response.write('<html><body>File not found</body></html>');
        } else {
          r.response.headers.contentType = ContentType('text', 'plain');
          r.response.add(mp4);
        }
        await r.response.close();
      };
      final saved = await run(DownloadKind.video, '$base/film.mp4');
      expect(saved.ok, isTrue, reason: saved.detail);
      expect(File(saved.artefactPath).readAsBytesSync(), mp4);

      await dir.delete(recursive: true);
      await dir.create();
      final page = await run(DownloadKind.video, '$base/page.mp4');
      expect(page.failure, DownloadFailureKind.notMedia);
      expect(hits.where((h) => h == '/page.mp4'), hasLength(1));
      expect(File('${dir.path}/video.mp4.part').existsSync(), isFalse);
      expect(File('${dir.path}/video.mp4').existsSync(), isFalse);
    });

    test('a file cut off midway resumes from its bytes', () async {
      final body = Uint8List.fromList(List.generate(40000, (i) => i % 256));
      var calls = 0;
      handle = (r) async {
        calls++;
        r.response.headers.contentType = ContentType('video', 'mp4');
        final range = r.headers.value('range');
        if (range == null) {
          // Promises everything, sends a third, and hangs up.
          r.response.contentLength = body.length;
          final socket = await r.response.detachSocket();
          socket.add(body.sublist(0, 15000));
          await socket.flush();
          socket.destroy();
          return;
        }
        final from = int.parse(
          RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!,
        );
        r.response.statusCode = 206;
        r.response.headers.set(
          'content-range',
          'bytes $from-${body.length - 1}/${body.length}',
        );
        r.response.contentLength = body.length - from;
        r.response.add(body.sublist(from));
        await r.response.close();
      };
      final result = await run(DownloadKind.video, '$base/film.mp4');
      expect(result.ok, isTrue, reason: result.detail);
      expect(calls, 2);
      expect(File(result.artefactPath).readAsBytesSync(), body);
    });
  });
}
