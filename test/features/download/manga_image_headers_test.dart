import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/download/data/datasources/download_transfer_data_source.dart';
import 'package:soplay/features/download/data/models/download_item_model.dart';
import 'package:soplay/features/download/domain/entities/download_item.dart';
import 'package:soplay/features/download/domain/entities/download_kind.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test('page headers survive persistence, copying and old rows', () {
    const item = DownloadItem(
      id: 'chapter',
      contentUrl: '/book',
      provider: 'my:test',
      title: 'Book',
      sourceUrl: '',
      relativePath: 'downloads/chapter',
      createdAt: 1,
      imageHeaders: [
        {'Authorization': 'first'},
        {'Cookie': 'second'},
      ],
    );
    final saved = DownloadItemModel.toJson(item.copyWith(updatedAt: 2));
    expect(DownloadItemModel.fromJson(saved).imageHeaders, item.imageHeaders);
    saved.remove('imageHeaders');
    expect(DownloadItemModel.fromJson(saved).imageHeaders, isEmpty);
  });
  test(
    'each image transfer gets its own headers with case-insensitive overrides',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final dir = await Directory.systemTemp.createTemp('sozo-image-headers-');
      final received = <String>[];
      server.listen((request) async {
        received.add(request.headers.value('authorization') ?? 'missing');
        request.response.headers.contentType = ContentType('image', 'png');
        request.response.add([137, 80, 78, 71, 13, 10, 26, 10, 1, 2, 3]);
        await request.response.close();
      });
      try {
        final url = 'http://127.0.0.1:${server.port}';
        final result = await DownloadTransferDataSource(dio: Dio()).run(
          id: 'chapter',
          dirPath: dir.path,
          kind: DownloadKind.manga,
          sourceUrl: '',
          pageUrls: ['$url/1.png', '$url/2.png'],
          headers: {'authorization': 'shared'},
          imageHeaders: [
            {'Authorization': 'first'},
            {'Authorization': 'second'},
          ],
          cancel: CancelToken(),
          onProgress: (_) {},
        );
        expect(result.ok, isTrue, reason: result.detail);
        expect(received, ['first', 'second']);
      } finally {
        await server.close(force: true);
        await dir.delete(recursive: true);
      }
    },
  );
}
