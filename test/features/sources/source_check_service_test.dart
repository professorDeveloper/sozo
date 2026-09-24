// Which sources still answer: dead is a claim over time, a bot wall is not
// death, and a run the network ruined marks nothing.
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/features/sources/data/source_browse_repository.dart';
import 'package:soplay/features/sources/data/source_check_store.dart';
import 'package:soplay/features/sources/domain/source_check_service.dart';
import 'package:soplay/features/sources/domain/source_failure.dart';
import 'package:soplay/features/extensions/data/mangayomi_bridge.dart';

class _Bridge implements MangayomiBridge {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

SourceAttempt ok() => const SourceAttempt(items: 12, ms: 300);
SourceAttempt fail(String raw) =>
    SourceAttempt(items: 0, ms: 900, failure: SourceFailure.of(raw));

void main() {
  late Box box;
  late SourceCheckStore store;
  var clock = 0;

  setUpAll(() async {
    Hive.init('${Directory.systemTemp.path}/sozo_source_check_test');
    box = await Hive.openBox('source_check_test');
  });
  tearDownAll(() async => Hive.close());

  setUp(() async {
    await box.clear();
    store = SourceCheckStore(box: box);
    clock = DateTime.now().millisecondsSinceEpoch;
  });

  SourceCheckService service(Map<String, List<SourceAttempt>> script) {
    return SourceCheckService(
      browse: SourceBrowseRepository(dio: Dio(), bridge: _Bridge()),
      store: store,
      now: () => clock,
      attempt: (id) async {
        final queue = script[id]!;
        return queue.length > 1 ? queue.removeAt(0) : queue.first;
      },
    );
  }

  group('a single source', () {
    test('one failure is a bad minute, not a death', () async {
      final s = service({
        'a': [fail('java.net.SocketTimeoutException: timeout')],
      });
      expect((await s.check('a')).verdict, SourceVerdict.failing);
    });

    test('two failures ten minutes apart are', () async {
      final s = service({
        'a': [fail('UnknownHostException: a.test')],
      });
      await s.check('a');
      clock += const Duration(minutes: 11).inMilliseconds;
      expect((await s.check('a')).verdict, SourceVerdict.dead);
    });

    test('a site that says "gone" twice is dead at once', () async {
      final s = service({
        'a': [fail('HTTP error 404')],
      });
      await s.check('a');
      expect((await s.check('a')).verdict, SourceVerdict.dead);
    });

    test('a bot wall is not death, and an old API needs an update', () async {
      final s = service({
        'cf': [fail('HTTP 403 cloudflare')],
        'old': [fail('MissingFieldException: Fields [x] are required')],
      });
      for (var i = 0; i < 3; i++) {
        expect((await s.check('cf')).verdict, SourceVerdict.blocked);
      }
      expect((await s.check('old')).verdict, SourceVerdict.outdated);
    });

    test('an answer clears the record', () async {
      final s = service({
        'a': [fail('HTTP error 404'), fail('HTTP error 404'), ok()],
      });
      await s.check('a');
      await s.check('a');
      expect(store.verdictOf('a'), SourceVerdict.dead);
      expect((await s.check('a')).verdict, SourceVerdict.alive);
    });
  });

  group('a run over many', () {
    test('failures get a second try, and gone is settled in one run', () async {
      final s = service({
        'good': [ok()],
        'gone': [fail('HTTP error 404')],
        'blip': [fail('SocketTimeoutException'), ok()],
        'wall': [fail('HTTP 403 cloudflare')],
      });
      final last = await s.checkAll(['good', 'gone', 'blip', 'wall']).last;
      expect(last.finished, isTrue);
      expect(store.verdictOf('good'), SourceVerdict.alive);
      expect(store.verdictOf('gone'), SourceVerdict.dead);
      expect(store.verdictOf('blip'), SourceVerdict.alive);
      expect(store.verdictOf('wall'), SourceVerdict.blocked);
      expect(last.counts[SourceVerdict.dead], 1);
    });

    test('a run the network ruined marks nothing', () async {
      final s = service({
        for (final id in ['a', 'b', 'c', 'd', 'e'])
          id: [fail('SocketException: Failed host lookup')],
      });
      final last = await s.checkAll(['a', 'b', 'c', 'd', 'e']).last;
      expect(last.networkDown, isTrue);
      expect(store.of('a'), isNull);
    });
  });

  group('ordinary use', () {
    test(
      'a failure that could be the connection is not held against it',
      () async {
        final s = service({});
        await s.observe('a', ok: false, error: 'SocketException: offline');
        expect(store.of('a'), isNull);
        await s.observe('a', ok: false, error: 'HTTP error 404');
        expect(store.verdictOf('a'), SourceVerdict.failing);
        await s.observe('a', ok: true);
        expect(store.verdictOf('a'), SourceVerdict.alive);
      },
    );
  });
}
