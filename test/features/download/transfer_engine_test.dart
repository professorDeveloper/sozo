// The in-process downloader against a real socket: segments several at a
// time, byte-range playlists cut into their slices, and a file whose
// connection drops picking up where it stopped.
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/download/data/datasources/download_transfer_data_source.dart';
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

    Future<TransferResult> run(DownloadKind kind, String url) =>
        DownloadTransferDataSource(dio: Dio()).run(
          id: 'x',
          dirPath: dir.path,
          kind: kind,
          sourceUrl: url,
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
