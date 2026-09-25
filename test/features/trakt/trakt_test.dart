// Trakt on the device: the title map keeps a user's choice over a guess and
// travels to the account, and the device-flow polls become the states the
// connect sheet draws.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/features/trakt/data/trakt_link_store.dart';
import 'package:soplay/features/trakt/data/trakt_service.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.answer);
  final Map<String, dynamic> Function(RequestOptions o) answer;
  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? _,
    Future<void>? _,
  ) async => ResponseBody.fromString(
    jsonEncode(answer(o)),
    200,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );
  @override
  void close({bool force = false}) {}
}

void main() {
  late Box box;
  setUpAll(() async {
    Hive.init('${Directory.systemTemp.path}/sozo_trakt_test');
    box = await Hive.openBox('sozo_trakt_test');
  });
  tearDownAll(() async => Hive.close());
  setUp(() async => box.clear());

  TraktLink link({bool auto = false, int id = 1, int? season}) => TraktLink(
    provider: 'vidapi',
    contentUrl: 'https://x/show',
    traktId: id,
    kind: 'show',
    title: 'Show',
    season: season,
    auto: auto,
  );

  test('a guess never replaces a choice; a choice replaces a guess', () async {
    final s = TraktLinkStore(box: box);
    await s.save(link(auto: true, id: 5));
    await s.save(link(id: 7));
    expect(s.get('vidapi', 'https://x/show')!.traktId, 7);
    await s.save(link(auto: true, id: 9));
    expect(s.get('vidapi', 'https://x/show')!.traktId, 7);
  });

  test('links and removals travel, and come back from the account', () async {
    final s = TraktLinkStore(box: box);
    await s.save(link(id: 7, season: 2));
    final out = s.pendingChanges().single;
    expect(out['mediaId'], 7);
    expect(out['kind'], 'show');
    expect(out['season'], 2);
    await s.applyRemote([
      {...out, 'updatedAt': DateTime.now().toIso8601String()},
    ]);
    final back = s.get('vidapi', 'https://x/show')!;
    expect(back.traktId, 7);
    expect(back.season, 2);
    await s.remove('vidapi', 'https://x/show');
    expect(s.pendingChanges().single.containsKey('deletedAt'), isTrue);
  });

  test('each device-flow poll answer becomes one state', () async {
    for (final (status, want) in [
      ('pending', TraktPoll.pending),
      ('slow_down', TraktPoll.slowDown),
      ('denied', TraktPoll.denied),
      ('expired', TraktPoll.expired),
      ('used', TraktPoll.expired),
    ]) {
      final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
        ..httpClientAdapter = _Adapter((_) => {'status': status});
      final svc = TraktService(
        backendDio: dio,
        links: TraktLinkStore(box: box),
        box: box,
      );
      expect(await svc.poll(), want, reason: status);
    }
  });

  test('a linked poll stores the token and client id', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
      ..httpClientAdapter = _Adapter(
        (o) => o.path.endsWith('/poll')
            ? {
                'status': 'linked',
                'trakt': {
                  'accessToken': 'AT',
                  'clientId': 'CID',
                  'name': 'Azamov',
                  'userId': 'azamov',
                },
              }
            : {'items': []},
      );
    final svc = TraktService(
      backendDio: dio,
      links: TraktLinkStore(box: box),
      box: box,
    );
    expect(await svc.poll(), TraktPoll.linked);
    expect(svc.isConnected, isTrue);
    expect(svc.viewer!.name, 'Azamov');
    expect(svc.clientId, 'CID');
  });
}
