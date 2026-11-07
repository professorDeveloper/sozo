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
    clock = DateTime.now().millisecondsSinceEpoch;
    // The store reads the same clock the service writes with, so a test that
    // moves time forward does not leave the store judging the age of a
    // verdict stamped in its future.
    store = SourceCheckStore(box: box, now: () => clock);
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

    test('a catalogue with nothing in it is not a working source', () async {
      // kisskh, measured against the live API: `/contents/home` answers 200
      // with an empty `sections` and no banner, because the site shut the
      // backend out and the backend reported what it got. Zero items is not
      // health, and the check run has to name it.
      final s = service({
        'kisskh': [const SourceAttempt(items: 0, ms: 240, empty: true)],
      });
      expect((await s.check('kisskh')).verdict, SourceVerdict.empty);
      expect(store.of('kisskh')!.isBad, isTrue);
    });

    test('an answer with nothing and no reason given does not throw', () async {
      // An attempt built without the empty flag used to reach `failure!`.
      final s = service({
        'a': [const SourceAttempt(items: 0, ms: 10)],
      });
      expect((await s.check('a')).verdict, SourceVerdict.empty);
    });

    test('an empty answer does not wipe the failures before it', () async {
      final s = service({
        'a': [
          fail('HTTP error 500'),
          const SourceAttempt(items: 0, ms: 50, empty: true),
          fail('HTTP error 500'),
        ],
      });
      expect((await s.check('a')).verdict, SourceVerdict.failing);
      final empty = await s.check('a');
      expect(empty.verdict, SourceVerdict.empty);
      expect(empty.fails, 1);
      clock += const Duration(minutes: 11).inMilliseconds;
      // Second real failure, eleven minutes after the first: the streak ran
      // through the empty answer rather than starting over, so this settles it.
      expect((await s.check('a')).verdict, SourceVerdict.dead);
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

  group('at scale', () {
    test('Mangayomi sources go one at a time; others share the rest', () async {
      var myNow = 0, myPeak = 0, allNow = 0, allPeak = 0;
      final s = SourceCheckService(
        browse: SourceBrowseRepository(dio: Dio(), bridge: _Bridge()),
        store: store,
        now: () => clock,
        attempt: (id) async {
          allNow++;
          if (allNow > allPeak) allPeak = allNow;
          if (id.startsWith('my:')) {
            myNow++;
            if (myNow > myPeak) myPeak = myNow;
          }
          await Future<void>.delayed(const Duration(milliseconds: 5));
          if (id.startsWith('my:')) myNow--;
          allNow--;
          return ok();
        },
      );
      final ids = [
        for (var i = 0; i < 10; i++) 'my:$i',
        for (var i = 0; i < 10; i++) 'cs:$i',
      ];
      final last = await s.checkAll(ids).last;
      expect(last.done, 20);
      expect(myPeak, 1);
      expect(allPeak, greaterThan(1));
      expect(allPeak, lessThanOrEqualTo(SourceCheckService.parallel));
    });

    test('a stopped run keeps the answers it got', () async {
      late SourceCheckService s;
      var calls = 0;
      s = SourceCheckService(
        browse: SourceBrowseRepository(dio: Dio(), bridge: _Bridge()),
        store: store,
        now: () => clock,
        attempt: (id) async {
          if (++calls == 3) s.cancel();
          return ok();
        },
      );
      await s.checkAll(['my:a', 'my:b', 'my:c', 'my:d', 'my:e']).drain<void>();
      expect(store.verdictOf('my:a'), SourceVerdict.alive);
      expect(store.of('my:e'), isNull);
    });

    test('the unchecked go first, the recently working last', () async {
      await store.put(
        'fine',
        SourceCheck(verdict: SourceVerdict.alive, at: clock),
      );
      await store.put(
        'bad',
        SourceCheck(verdict: SourceVerdict.dead, at: clock, fails: 2),
      );
      final s = service({});
      expect(s.plan(['fine', 'bad', 'new']), ['new', 'bad', 'fine']);
      expect(s.staleOf(['fine', 'bad', 'new']), ['new']);
      expect(s.troubledOf(['fine', 'bad', 'new']), ['bad']);
    });

    test('a sweep asks only a few of the stale ones', () async {
      final asked = <String>[];
      final s = SourceCheckService(
        browse: SourceBrowseRepository(dio: Dio(), bridge: _Bridge()),
        store: store,
        now: () => clock,
        attempt: (id) async {
          asked.add(id);
          return ok();
        },
      );
      await store.put(
        'fresh',
        SourceCheck(verdict: SourceVerdict.alive, at: clock),
      );
      await s.sweep(['fresh', for (var i = 0; i < 30; i++) 'x$i'], limit: 5);
      expect(asked, hasLength(5));
      expect(asked, isNot(contains('fresh')));
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
        // Retry, retry: the same failure seen again, not a second one.
        await s.observe('a', ok: false, error: 'HTTP error 404');
        await s.observe('a', ok: false, error: 'HTTP error 404');
        expect(store.verdictOf('a'), SourceVerdict.failing);
        clock += const Duration(minutes: 2).inMilliseconds;
        await s.observe('a', ok: false, error: 'HTTP error 404');
        expect(store.verdictOf('a'), SourceVerdict.dead);
        await s.observe('a', ok: true);
        expect(store.verdictOf('a'), SourceVerdict.alive);
      },
    );
  });
  group('how long a verdict lasts', () {
    test('past the stale window it is not shown, and the table drops it',
        () async {
      await store.put('a', SourceCheck(verdict: SourceVerdict.dead, at: clock));
      expect(store.verdictOf('a'), SourceVerdict.dead);
      clock += (SourceCheckStore.staleAfter + const Duration(hours: 1))
          .inMilliseconds;
      expect(store.of('a'), isNull);
      expect(store.verdictOf('a'), SourceVerdict.unknown);
      // And the next write takes it out of the stored table, so it is not
      // carried and re-serialised for ever.
      await store.put('b', SourceCheck(verdict: SourceVerdict.alive, at: clock));
      expect((box.get('source_checks') as Map).keys, ['b']);
    });

    test('a verdict stamped in the future is not shown either', () async {
      await store.put(
        'a',
        SourceCheck(
          verdict: SourceVerdict.dead,
          at: clock + const Duration(days: 2).inMilliseconds,
        ),
      );
      expect(store.of('a'), isNull);
    });

    test('a stale verdict is re-checked rather than trusted', () async {
      await store.put('a', SourceCheck(verdict: SourceVerdict.alive, at: clock));
      clock += (SourceCheckStore.staleAfter + const Duration(hours: 1))
          .inMilliseconds;
      final s = service({});
      expect(s.staleOf(['a']), ['a']);
    });
  });
}
