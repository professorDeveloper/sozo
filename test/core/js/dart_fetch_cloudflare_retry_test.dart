import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/js/dart_fetch.dart';
import 'package:soplay/core/network/cf_bypass_service.dart';
import 'package:soplay/features/extensions/data/mangayomi_runtime.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.reply);
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

class _Solver extends CfBypassService {
  _Solver(this.answer);
  final String? answer;
  final solved = <String>[];
  @override
  Future<String?> solve({
    required String host,
    required String url,
    required String userAgent,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    solved.add(host);
    return answer;
  }
}

ResponseBody _challenge() => ResponseBody.fromString(
  '<title>Just a moment...</title>',
  403,
  headers: {
    'server': ['cloudflare'],
  },
);

void main() {
  const site = 'https://93.184.216.34/novels';

  test(
    'a challenged call is solved and run again with the clearance',
    () async {
      final solver = _Solver('cf_clearance=ok');
      final fetch = DartFetch.create(cfService: solver);
      final cookies = <String?>[];
      fetch.dio.httpClientAdapter = _Adapter((request) {
        final cookie = request.headers['Cookie']?.toString();
        cookies.add(cookie);
        if (cookie == null || !cookie.contains('cf_clearance')) {
          return _challenge();
        }
        return ResponseBody.fromString('<p>chapter</p>', 200);
      });

      var attempts = 0;
      final result = await fetch.retryAfterCloudflare(() {
        attempts++;
        return fetch.call({'url': site});
      });

      expect(attempts, 2);
      expect(solver.solved, ['93.184.216.34']);
      expect(result['status'], 200);
      expect(result['data'], '<p>chapter</p>');
      expect(cookies.last, contains('cf_clearance=ok'));
      fetch.dio.close(force: true);
    },
  );

  test('an unchallenged call runs once and is not solved', () async {
    final solver = _Solver('cf_clearance=ok');
    final fetch = DartFetch.create(cfService: solver);
    fetch.dio.httpClientAdapter = _Adapter(
      (_) => ResponseBody.fromString('ok', 200),
    );
    var attempts = 0;
    await fetch.retryAfterCloudflare(() {
      attempts++;
      return fetch.call({'url': site});
    });
    expect(attempts, 1);
    expect(solver.solved, isEmpty);
    fetch.dio.close(force: true);
  });

  test(
    'a failed solve keeps the first answer and names the challenge',
    () async {
      final fetch = DartFetch.create(cfService: _Solver(null));
      fetch.dio.httpClientAdapter = _Adapter((_) => _challenge());
      final start = fetch.mark();
      var attempts = 0;
      final result = await fetch.retryAfterCloudflare(() {
        attempts++;
        return fetch.call({'url': site});
      });
      expect(attempts, 1);
      expect(result['status'], 403);
      final block = fetch.cloudflareBlockSince(start);
      expect(block, contains('Cloudflare'));
      expect(fetch.cloudflareBlockSince(fetch.mark()), isNull);

      // A plugin's own words for that page, which the error screen could not
      // tell from any other failure.
      final message = MangayomiRuntime.withCloudflareCause(
        'Could not reach site (403) try to open in webview.',
        block,
      );
      expect(message.toLowerCase(), contains('cloudflare'));
      expect(MangayomiRuntime.withCloudflareCause('boom', null), 'boom');
      fetch.dio.close(force: true);
    },
  );
}
