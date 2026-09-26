// What the app sends to support and what it reads back. Real HTTP against a
// local server, so no test binding (it answers every request with a 400).
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/support/data/support_models.dart';
import 'package:soplay/features/support/data/support_repository.dart';

void main() {
  group('SupportRepository', () {
    late HttpServer server;
    final seen = <({String method, String path, String? key, Object? body})>[];
    var status = 200;
    Map<String, Object?> answer = {};

    setUp(() async {
      seen.clear();
      status = 200;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final raw = await utf8.decoder.bind(req).join();
        seen.add((
          method: req.method,
          path: req.uri.path,
          key: req.headers.value('x-support-key'),
          body: raw.isEmpty ? null : jsonDecode(raw),
        ));
        req.response
          ..statusCode = status
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(answer));
        await req.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    SupportRepository repo() => SupportRepository(
      dio: Dio(BaseOptions(baseUrl: 'http://127.0.0.1:${server.port}/api')),
      deviceKey: () => 'k' * 43,
    );

    final ticketJson = {
      'id': 't1',
      'category': 'playback',
      'status': 'answered',
      'userUnread': true,
      'hasDiagnostics': true,
      'preview': 'Try another source',
      'lastFrom': 'admin',
      'lastMessageAt': '2026-09-26T09:00:00Z',
      'createdAt': '2026-09-26T08:00:00Z',
      'messages': [
        {
          'id': 'm1',
          'from': 'user',
          'body': 'It will not play',
          'at': '2026-09-26T08:00:00Z',
        },
        {
          'id': 'm2',
          'from': 'admin',
          'body': 'Try another source',
          'at': '2026-09-26T09:00:00Z',
        },
      ],
    };

    test(
      'every call carries the device key; a ticket reads back whole',
      () async {
        answer = {'ticket': ticketJson};
        final t = await repo().create(
          category: SupportCategory.playback,
          message: 'It will not play',
          contact: '  ',
          diagnostics: {'app': '3.2.0', 'engine': 'mpv'},
        );
        expect(seen.single.key, 'k' * 43);
        expect(seen.single.path, '/api/support/tickets');
        final body = seen.single.body as Map;
        expect(body['category'], 'playback');
        expect(
          body.containsKey('contact'),
          isFalse,
          reason: 'a blank contact is not sent',
        );
        expect(body['diagnostics'], {'app': '3.2.0', 'engine': 'mpv'});

        expect(t.status, SupportStatus.answered);
        expect(t.unread, isTrue);
        expect(t.messages.map((m) => m.fromSupport), [false, true]);
      },
    );

    test('no diagnostics means none are sent', () async {
      answer = {'ticket': ticketJson};
      await repo().create(
        category: SupportCategory.idea,
        message: 'Dark AMOLED theme',
      );
      expect((seen.single.body as Map).containsKey('diagnostics'), isFalse);
    });

    test('an inbox counts its unread answers', () async {
      answer = {
        'items': [ticketJson],
        'unread': 1,
      };
      final inbox = await repo().list();
      expect(inbox.tickets.single.id, 't1');
      expect(inbox.unread, 1);
      expect(seen.single.key, 'k' * 43);
    });

    test(
      'refusals are the app\'s own words, never the server\'s Uzbek',
      () async {
        status = 429;
        answer = {'message': "Juda ko'p so'rov"};
        await expectLater(
          repo().create(category: SupportCategory.bug, message: 'Crashes'),
          throwsA(
            isA<SupportException>().having(
              (e) => e.message,
              'message',
              'support.error_too_many',
            ),
          ),
        );
        status = 400;
        answer = {'message': 'Xabar juda qisqa', 'code': 'SUPPORT_MESSAGE'};
        await expectLater(
          repo().reply('t1', 'ok'),
          throwsA(
            isA<SupportException>().having(
              (e) => e.code,
              'code',
              'SUPPORT_MESSAGE',
            ),
          ),
        );
      },
    );
  });
}
