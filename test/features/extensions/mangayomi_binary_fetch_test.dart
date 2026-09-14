import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/js/dart_fetch.dart';

class ByteAdapter implements HttpClientAdapter {
  ByteAdapter(this.reply);
  final ResponseBody Function(RequestOptions) reply;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => reply(options);
  @override
  void close({bool force = false}) {}
}

void main() {
  const public =
      'https://93.184.216.34'; // Adapter supplies bytes; no HTTP network IO.
  test('EPUB bytes remain binary and reuse the HTTP cookie jar', () async {
    final fetch = DartFetch.create();
    String? cookie;
    fetch.dio.httpClientAdapter = ByteAdapter((request) {
      if (request.path.endsWith('/login')) {
        return ResponseBody.fromString(
          'ok',
          200,
          headers: {
            'set-cookie': ['session=fixture; Path=/'],
          },
        );
      }
      cookie = request.headers['cookie']?.toString();
      return ResponseBody.fromBytes(
        [0, 255, 128, 42],
        200,
        headers: {
          'content-type': ['application/epub+zip'],
        },
      );
    });
    await fetch.dio.get('$public/login');
    expect(await fetch.fetchBytes('$public/book.epub', {}), [0, 255, 128, 42]);
    expect(cookie, contains('session=fixture'));
    final image = await fetch.headersForImage('$public/image.png', {
      'Referer': 'https://book.example',
    });
    expect(image['Cookie'], 'session=fixture');
    expect(image['Referer'], 'https://book.example');
    expect(
      await fetch.headersForImage('https://other.example/image.png', {}),
      isEmpty,
    );
    fetch.dio.close(force: true);
  });
  test('EPUB size guard handles streams without Content-Length', () async {
    final fetch = DartFetch.create();
    fetch.dio.httpClientAdapter = ByteAdapter(
      (_) => ResponseBody.fromBytes([1, 2, 3, 4, 5], 200),
    );
    await expectLater(
      fetch.fetchBytes('$public/book.epub', {}, maxBytes: 4),
      throwsStateError,
    );
    fetch.dio.close(force: true);
  });
  test(
    'HTTP error and private destination never become cached books',
    () async {
      final fetch = DartFetch.create();
      var requests = 0;
      fetch.dio.httpClientAdapter = ByteAdapter((_) {
        requests++;
        return ResponseBody.fromBytes([1], 503);
      });
      await expectLater(
        fetch.fetchBytes('http://127.0.0.1/book.epub', {}),
        throwsStateError,
      );
      expect(requests, 0);
      await expectLater(
        fetch.fetchBytes('$public/book.epub', {}),
        throwsA(isA<DioException>()),
      );
      fetch.dio.close(force: true);
    },
  );
}
