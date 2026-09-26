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
    final puts = <({String path, String? type, int length, int bytes})>[];
    Map<String, Object?> answer = {};

    setUp(() async {
      seen.clear();
      puts.clear();
      status = 200;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        if (req.method == 'PUT') {
          final bytes = await req.fold<List<int>>([], (a, b) => a..addAll(b));
          puts.add((
            path: req.uri.path,
            type: req.headers.contentType?.mimeType,
            length: req.headers.contentLength,
            bytes: bytes.length,
          ));
          req.response.statusCode = 200;
          await req.response.close();
          return;
        }
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

    SupportRepository repo({String? token}) => SupportRepository(
      dio: Dio(BaseOptions(baseUrl: 'http://127.0.0.1:${server.port}/api')),
      deviceKey: () => 'k' * 43,
      pushToken: token == null ? null : () async => token,
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

    test(
      'a screenshot goes to its signed slot with its own size and type',
      () async {
        final dir = await Directory.systemTemp.createTemp('sozo_shot_');
        addTearDown(() => dir.delete(recursive: true));
        final file = File('${dir.path}/shot.png')
          ..writeAsBytesSync(List.filled(2048, 7));
        answer = {
          'uploadUrl':
              'http://127.0.0.1:${server.port}/put/support/k/abc/1.png',
          'key': 'support/k/abc/1.png',
        };
        final key = await repo().uploadScreenshot(file);
        expect(key, 'support/k/abc/1.png');
        final slot = seen.single;
        expect(slot.path, '/api/support/uploads');
        expect(slot.key, 'k' * 43);
        expect(slot.body, {'contentType': 'image/png', 'size': 2048});
        expect(puts.single.path, '/put/support/k/abc/1.png');
        expect(puts.single.type, 'image/png');
        expect(puts.single.length, 2048);
        expect(puts.single.bytes, 2048);
      },
    );

    test(
      'a file the server would refuse is refused before any request',
      () async {
        final dir = await Directory.systemTemp.createTemp('sozo_shot_');
        addTearDown(() => dir.delete(recursive: true));
        final gif = File('${dir.path}/a.gif')..writeAsBytesSync([1, 2, 3]);
        await expectLater(
          repo().uploadScreenshot(gif),
          throwsA(
            isA<SupportException>().having(
              (e) => e.message,
              'message',
              'support.error_attachment_type',
            ),
          ),
        );
        final big = File('${dir.path}/big.jpg')
          ..writeAsBytesSync(
            List.filled(SupportRepository.maxAttachmentBytes + 1, 0),
          );
        await expectLater(
          repo().uploadScreenshot(big),
          throwsA(
            isA<SupportException>().having(
              (e) => e.message,
              'message',
              'support.error_attachment_size',
            ),
          ),
        );
        expect(seen, isEmpty);
      },
    );

    test(
      'a message carries its screenshots, the language and the push token',
      () async {
        answer = {'ticket': ticketJson};
        await repo(
          token: 'fcm-token-0123456789-abcdef',
        ).reply('t1', '', attachments: ['support/k/abc/1.png'], language: 'ru');
        final body = seen.single.body as Map;
        expect(body['attachments'], ['support/k/abc/1.png']);
        expect(body['language'], 'ru');
        expect(body['pushToken'], 'fcm-token-0123456789-abcdef');
        seen.clear();
        await repo().create(
          category: SupportCategory.bug,
          message: 'No token here',
        );
        expect((seen.single.body as Map).containsKey('pushToken'), isFalse);
      },
    );

    test('screenshots on a message read back with their signed URLs', () {
      final m = SupportMessage.fromJson({
        'id': 'm',
        'from': 'user',
        'body': '',
        'at': '2026-09-26T09:00:00Z',
        'attachments': [
          {
            'url': 'https://r2/get/a.jpg',
            'contentType': 'image/jpeg',
            'size': 900,
          },
          {'contentType': 'image/jpeg'},
        ],
      });
      expect(m.attachments.map((a) => a.url), ['https://r2/get/a.jpg']);
      expect(m.body, isEmpty);
    });
  });
}
