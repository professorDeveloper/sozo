import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/features/profile/data/models/provider_model.dart';
import 'package:soplay/features/profile/domain/entities/provider_entity.dart';
import 'package:soplay/features/search/data/source_health_store.dart';
import 'package:soplay/features/search/domain/entities/cross_search_result.dart';

/// A source, reduced to the only thing the store cares about.
typedef _Src = ({String id});

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('sozo_health_');
    Hive.init(dir.path);
    await Hive.openBox(AppConstants.settingsBox);
  });

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  setUp(() async => SourceHealthStore().clear());

  const base = Duration(seconds: 10);

  test('a source nobody has searched is treated as healthy', () {
    // A newly added source must not start life behind the known-broken ones —
    // it has done nothing wrong, and the first search is exactly when someone
    // is watching to see whether adding it worked.
    expect(SourceHealthStore().statusOf('brand-new'), SourceHealth.ok);
  });

  test(
    'a fast answer is ok, a slow one is slow, a failure is broken',
    () async {
      final s = SourceHealthStore();
      await s.record(
        'fast',
        succeeded: true,
        elapsed: const Duration(milliseconds: 300),
        budget: base,
      );
      await s.record(
        'slow',
        succeeded: true,
        elapsed: const Duration(seconds: 9),
        budget: base,
      );
      await s.record('dead', succeeded: false, elapsed: base, budget: base);

      expect(s.statusOf('fast'), SourceHealth.ok);
      expect(s.statusOf('slow'), SourceHealth.slow);
      expect(s.statusOf('dead'), SourceHealth.broken);
    },
  );

  test('a source that answered at the buzzer is not called healthy', () async {
    // Both of these "succeeded". Only one of them should be asked first next
    // time, which is the entire reason elapsed time is recorded at all.
    final s = SourceHealthStore();
    await s.record(
      'a',
      succeeded: true,
      elapsed: const Duration(seconds: 8),
      budget: base,
    );
    expect(s.statusOf('a'), SourceHealth.slow);
  });

  test('the queue is ordered healthiest first, stably', () async {
    final s = SourceHealthStore();
    await s.record('dead', succeeded: false, elapsed: base, budget: base);
    await s.record(
      'slow',
      succeeded: true,
      elapsed: const Duration(seconds: 9),
      budget: base,
    );

    const set = <_Src>[
      (id: 'dead'),
      (id: 'good1'),
      (id: 'slow'),
      (id: 'good2'),
    ];
    final ordered = s.order(set, (r) => r.id);

    expect(ordered.map((r) => r.id).toList(), [
      'good1',
      'good2',
      'slow',
      'dead',
    ]);
  });

  test('an untouched set is returned exactly as the user arranged it', () {
    // The order sources are listed in is the user's choice. Nothing has been
    // observed here, so there is nothing to justify moving any of it.
    const set = <_Src>[(id: 'c'), (id: 'a'), (id: 'b')];
    final ordered = SourceHealthStore().order(set, (r) => r.id);
    expect(identical(ordered, set), isTrue);
  });

  test(
    'a broken source keeps its place in the queue, on a shorter leash',
    () async {
      // Ordered down, never dropped. "Down" is one observation from one device on
      // one network, and a source unreachable on mobile data is often fine on
      // wifi — the shorter budget lets it prove that without holding up the run.
      final s = SourceHealthStore();
      await s.record('dead', succeeded: false, elapsed: base, budget: base);

      expect(s.order(const <_Src>[(id: 'dead')], (r) => r.id), hasLength(1));
      expect(s.budgetFor('dead', base), SourceHealthStore.brokenBudget);
      expect(s.budgetFor('healthy', base), base);
    },
  );

  test('a budget already shorter than the penalty is left alone', () {
    // Never lengthen a caller's timeout in the name of shortening it.
    const tight = Duration(seconds: 2);
    expect(SourceHealthStore().budgetFor('dead', tight), tight);
  });

  test('recovery is recorded, not held against the source', () async {
    final s = SourceHealthStore();
    await s.record('x', succeeded: false, elapsed: base, budget: base);
    expect(s.statusOf('x'), SourceHealth.broken);

    await s.record(
      'x',
      succeeded: true,
      elapsed: const Duration(milliseconds: 200),
      budget: base,
    );
    expect(s.statusOf('x'), SourceHealth.ok);
    expect(s.budgetFor('x', base), base, reason: 'and it gets its budget back');
  });

  test('a stale mark expires rather than punishing a source forever', () async {
    // Written by hand with an old timestamp: sources come back, networks
    // change, and a mark from this morning is not evidence about tonight.
    final box = Hive.box(AppConstants.settingsBox);
    await box.put('search_source_health', {
      'old': {
        'state': 'broken',
        'at': DateTime.now()
            .subtract(SourceHealthStore.ttl + const Duration(minutes: 1))
            .millisecondsSinceEpoch,
      },
    });
    expect(SourceHealthStore().statusOf('old'), SourceHealth.ok);
  });

  test('a corrupt record reads as healthy instead of throwing', () async {
    final box = Hive.box(AppConstants.settingsBox);
    await box.put('search_source_health', 'not a map');
    expect(SourceHealthStore().statusOf('anything'), SourceHealth.ok);
  });

  group('the server\'s verdicts', () {
    Map<String, dynamic> report({
      DateTime? checkedAt,
      List<String> down = const [],
      List<String> up = const [],
    }) => {
      'checkedAt': (checkedAt ?? DateTime.now()).toIso8601String(),
      'sources': {
        for (final id in up) id: {'ok': true},
        for (final id in down) id: {'ok': false, 'failedAt': 'domain'},
      },
    };

    test('a source the harness found dead starts at the back, on the short '
        'leash, before this device has tried it', () async {
      final s = SourceHealthStore(
        remote: () async => report(down: ['dead'], up: ['fine']),
      );
      await s.refreshRemote();

      const set = <_Src>[(id: 'dead'), (id: 'fine'), (id: 'unknown')];
      expect(s.order(set, (r) => r.id).map((r) => r.id).toList(), [
        'fine',
        'unknown',
        'dead',
      ]);
      expect(s.budgetFor('dead', base), SourceHealthStore.brokenBudget);
      expect(s.budgetFor('fine', base), base);
    });

    test(
      'this device\'s own fresh observation wins over the server\'s',
      () async {
        // "It worked from here ten minutes ago" is better evidence about the
        // next ten minutes than a run from another network two days ago — and
        // the only way a recovered source gets its place back before the next
        // scheduled run.
        final s = SourceHealthStore(remote: () async => report(down: ['x']));
        await s.refreshRemote();
        expect(s.statusOf('x'), SourceHealth.broken);

        await s.record(
          'x',
          succeeded: true,
          elapsed: const Duration(milliseconds: 200),
          budget: base,
        );
        expect(s.statusOf('x'), SourceHealth.ok);
      },
    );

    test('the server is asked once per window, not once per search', () async {
      var calls = 0;
      final s = SourceHealthStore(
        remote: () async {
          calls++;
          return report(down: ['x']);
        },
      );
      await s.refreshRemote();
      await s.refreshRemote();
      await s.refreshRemote();
      expect(calls, 1);
      expect(s.statusOf('x'), SourceHealth.broken);
    });

    test('a verdict older than the window is forgotten', () async {
      final s = SourceHealthStore(
        remote: () async => report(
          down: ['x'],
          checkedAt: DateTime.now().subtract(
            SourceHealthStore.remoteTtl + const Duration(hours: 1),
          ),
        ),
      );
      await s.refreshRemote();
      expect(s.statusOf('x'), SourceHealth.ok);
    });

    test('a failed fetch keeps what the server said last time', () async {
      var fail = false;
      final s = SourceHealthStore(
        remote: () async {
          if (fail) throw Exception('offline');
          return report(down: ['x']);
        },
      );
      await s.refreshRemote();
      fail = true;
      // Past the window, so the fetch really happens and really fails.
      final box = Hive.box(AppConstants.settingsBox);
      final raw = Map<String, dynamic>.from(
        box.get('search_source_health_remote') as Map,
      );
      raw['fetchedAt'] = DateTime.now()
          .subtract(
            SourceHealthStore.remoteRefreshEvery + const Duration(minutes: 1),
          )
          .millisecondsSinceEpoch;
      await box.put('search_source_health_remote', raw);

      await s.refreshRemote();
      expect(s.statusOf('x'), SourceHealth.broken);
    });

    test('with no server to ask, nothing changes and nothing throws', () async {
      final s = SourceHealthStore();
      await s.refreshRemote();
      expect(s.statusOf('x'), SourceHealth.ok);
    });
  });

  group('a penalty cannot become a life sentence', () {
    const honest = Duration(seconds: 45);

    /// The state an extension source lands in after its first search: the APK
    /// download legitimately took most of the honest budget, the batch gave up,
    /// and the source was marked broken.
    Future<void> markBroken(SourceHealthStore s) => s.record(
      'cs:some',
      succeeded: false,
      elapsed: honest,
      budget: honest,
      honestBudget: honest,
    );

    test('a failure under a shortened budget does not renew the mark', () async {
      // The trap. Once broken, every attempt is clamped to four seconds — less
      // than the download it is being punished for never finishing — so it
      // times out again, and that timeout used to rewrite `at` and push the
      // six-hour TTL forward. Search once an hour and the source is dead
      // forever on a device where it would work.
      final store = SourceHealthStore();
      await markBroken(store);
      final markedAt = store.rawRecordedAt('cs:some');
      expect(markedAt, isNotNull);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      await store.record(
        'cs:some',
        succeeded: false,
        elapsed: SourceHealthStore.brokenBudget,
        budget: SourceHealthStore.brokenBudget,
        honestBudget: honest,
      );

      expect(
        store.rawRecordedAt('cs:some'),
        markedAt,
        reason: 'the sentence renewed itself, so the TTL could never run out',
      );
      expect(store.statusOf('cs:some'), SourceHealth.broken);
    });

    test('but a failure on the honest budget is real evidence', () async {
      // The other half: this must not become "a broken source is never
      // updated again", which would freeze the record instead of the TTL.
      final store = SourceHealthStore();
      await markBroken(store);
      final markedAt = store.rawRecordedAt('cs:some');

      await Future<void>.delayed(const Duration(milliseconds: 20));
      await store.record(
        'cs:some',
        succeeded: false,
        elapsed: honest,
        budget: honest,
        honestBudget: honest,
      );

      expect(store.rawRecordedAt('cs:some'), isNot(markedAt));
    });

    test('and a success always lands, however short the budget was', () async {
      // A recovered source proving itself in two seconds is the entire point
      // of asking a broken source at all.
      final store = SourceHealthStore();
      await markBroken(store);

      await store.record(
        'cs:some',
        succeeded: true,
        elapsed: const Duration(seconds: 1),
        budget: SourceHealthStore.brokenBudget,
        honestBudget: honest,
      );

      expect(store.statusOf('cs:some'), SourceHealth.ok);
    });
  });

  group('the penalty is for batches, not for what the user asked for', () {
    test('a broken source is put on a short leash in a batch', () async {
      final store = SourceHealthStore();
      await store.record(
        'cs:some',
        succeeded: false,
        elapsed: const Duration(seconds: 45),
        budget: const Duration(seconds: 45),
        honestBudget: const Duration(seconds: 45),
      );
      expect(
        store.budgetFor('cs:some', const Duration(seconds: 45)),
        SourceHealthStore.brokenBudget,
      );
    });

    test('but not when the user asked for that source by name', () async {
      // Retry only ever appears beside a source that just failed, so before
      // this every retry ran on the penalty budget and confirmed the failure
      // it inherited. The source diagnostic did the same.
      final store = SourceHealthStore();
      await store.record(
        'cs:some',
        succeeded: false,
        elapsed: const Duration(seconds: 45),
        budget: const Duration(seconds: 45),
        honestBudget: const Duration(seconds: 45),
      );
      expect(
        store.budgetFor(
          'cs:some',
          const Duration(seconds: 45),
          deliberate: true,
        ),
        const Duration(seconds: 45),
      );
    });

    test('a healthy source keeps its budget either way', () {
      final store = SourceHealthStore();
      expect(store.budgetFor('fresh', base), base);
      expect(store.budgetFor('fresh', base, deliberate: true), base);
    });
  });

  group('extension verdicts', () {
    Map<String, dynamic> report({
      DateTime? extCheckedAt,
      Map<String, Map<String, dynamic>> extensions = const {},
    }) => {
      'checkedAt': DateTime.now().toIso8601String(),
      'sources': const <String, dynamic>{},
      'extCheckedAt': (extCheckedAt ?? DateTime.now()).toIso8601String(),
      'extensions': extensions,
    };

    Future<SourceHealthStore> storeWith(
      Map<String, Map<String, dynamic>> extensions, {
      DateTime? extCheckedAt,
    }) async {
      final s = SourceHealthStore(
        remote: () async =>
            report(extensions: extensions, extCheckedAt: extCheckedAt),
      );
      await s.refreshRemote();
      return s;
    }

    test('a dead extension goes last, on the short leash', () async {
      final s = await storeWith({
        'mn:1': {'state': 'dead', 'cf': false, 'reason': 'dns'},
      });
      const set = <_Src>[(id: 'mn:1'), (id: 'mn:2')];
      expect(s.order(set, (r) => r.id).map((r) => r.id), ['mn:2', 'mn:1']);
      expect(s.budgetFor('mn:1', base), SourceHealthStore.brokenBudget);
      final v = s.badgeOf('mn:1')!;
      expect(v.state, RemoteHealth.dead);
      expect(v.reason, 'dns');
      expect(v.checkedAt, isNotNull);
    });

    test('a Cloudflare wall sits between healthy and dead, with its full '
        'budget', () async {
      final s = await storeWith({
        'an:dead': {'state': 'dead', 'reason': 'parked'},
        'an:cf': {'state': 'cloudflare', 'cf': true, 'reason': 'blocked'},
      });
      const set = <_Src>[(id: 'an:dead'), (id: 'an:cf'), (id: 'an:ok')];
      expect(s.order(set, (r) => r.id).map((r) => r.id), [
        'an:ok',
        'an:cf',
        'an:dead',
      ]);
      expect(s.budgetFor('an:cf', base), base);
      expect(s.badgeOf('an:cf')!.state, RemoteHealth.cloudflare);
      expect(s.isDown('an:cf'), isFalse);
    });

    test('slow is used for ordering but never badged', () async {
      final s = await storeWith({
        'my:s': {'state': 'slow', 'reason': 'slow_response'},
      });
      expect(s.statusOf('my:s'), SourceHealth.slow);
      expect(s.remoteVerdictOf('my:s')!.state, RemoteHealth.slow);
      expect(s.badgeOf('my:s'), isNull);
    });

    test('CloudStream verdicts are found through the plugin key', () async {
      final s = await storeWith({
        'csp:FooProvider': {'state': 'dead', 'reason': 'maintainer_down'},
      });
      expect(s.statusOf('cs:Foo'), SourceHealth.ok);
      expect(s.statusOf('cs:Foo', key: 'csp:FooProvider'), SourceHealth.broken);
      expect(
        s.badgeOf('cs:Foo', key: 'csp:FooProvider')?.reason,
        'maintainer_down',
      );
      const set = <_Src>[(id: 'cs:Foo'), (id: 'cs:Bar')];
      expect(
        s
            .order(
              set,
              (r) => r.id,
              keyOf: (r) => r.id == 'cs:Foo' ? 'csp:FooProvider' : r.id,
            )
            .map((r) => r.id),
        ['cs:Bar', 'cs:Foo'],
      );
    });

    test('a sweep older than the window says nothing', () async {
      final s = await storeWith(
        {
          'mn:1': {'state': 'dead'},
        },
        extCheckedAt: DateTime.now().subtract(
          SourceHealthStore.remoteTtl + const Duration(hours: 1),
        ),
      );
      expect(s.statusOf('mn:1'), SourceHealth.ok);
      expect(s.badgeOf('mn:1'), isNull);
    });

    test('unknown states are ignored rather than trusted', () async {
      final s = await storeWith({
        'mn:1': {'state': 'exploded'},
        'mn:2': {'state': 'ok'},
      });
      expect(s.remoteVerdictOf('mn:1'), isNull);
      expect(s.remoteVerdictOf('mn:2'), isNull);
    });

    test('a record saved before extension verdicts existed is refetched at '
        'once', () async {
      final box = Hive.box(AppConstants.settingsBox);
      await box.put('search_source_health_remote', {
        'fetchedAt': DateTime.now().millisecondsSinceEpoch,
        'checkedAt': DateTime.now().millisecondsSinceEpoch,
        'down': <String>[],
      });
      var calls = 0;
      final s = SourceHealthStore(
        remote: () async {
          calls++;
          return report(
            extensions: {
              'mn:1': {'state': 'dead'},
            },
          );
        },
      );
      await s.refreshRemote();
      await s.refreshRemote();
      expect(calls, 1);
      expect(s.isDown('mn:1'), isTrue);
    });

    test('a fresh success on this device clears the Down badge', () async {
      final s = await storeWith({
        'mn:1': {'state': 'dead', 'reason': 'timeout'},
      });
      expect(s.isDown('mn:1'), isTrue);
      await s.record(
        'mn:1',
        succeeded: true,
        elapsed: const Duration(milliseconds: 300),
        budget: base,
      );
      expect(s.badgeOf('mn:1'), isNull);
      expect(s.statusOf('mn:1'), SourceHealth.ok);
    });

    test('down rows sink stably, hide on request, and the kept one '
        'stays', () async {
      final s = await storeWith({
        'a': {'state': 'dead'},
        'c': {'state': 'dead'},
        'b': {'state': 'cloudflare'},
      });
      const rows = ['a', 'b', 'c', 'd'];
      expect(s.sinkDown(rows, (r) => r), ['b', 'd', 'a', 'c']);
      expect(s.sinkDown(rows, (r) => r, hide: true), ['b', 'd']);
      expect(s.sinkDown(rows, (r) => r, hide: true, keep: (r) => r == 'c'), [
        'b',
        'd',
        'c',
      ]);
      const clean = ['b', 'd'];
      expect(identical(s.sinkDown(clean, (r) => r), clean), isTrue);
    });

    test('the hide preference persists and announces itself', () async {
      final s = SourceHealthStore();
      var ticks = 0;
      void listener() => ticks++;
      s.changes.addListener(listener);
      addTearDown(() => s.changes.removeListener(listener));
      expect(s.hideDown, isFalse);
      await s.setHideDown(true);
      expect(SourceHealthStore().hideDown, isTrue);
      await s.setHideDown(false);
      expect(s.hideDown, isFalse);
      expect(ticks, 2);
    });
  });

  group('health keys', () {
    ProviderEntity entity(String id, {String internalName = ''}) =>
        ProviderEntity(
          id: id,
          name: id,
          image: '',
          url: '',
          description: '',
          domains: const [],
          internalName: internalName,
        );

    test('CloudStream maps to its plugin, everything else to itself', () {
      expect(
        entity('cs:Foo', internalName: 'FooProvider').healthKey,
        'csp:FooProvider',
      );
      expect(entity('cs:Foo').healthKey, 'cs:Foo');
      expect(entity('mn:123', internalName: 'x').healthKey, 'mn:123');
      expect(entity('hdrezka').healthKey, 'hdrezka');
    });

    test('the key travels into cross-search refs and through json', () {
      final ref = ProviderRef.fromEntity(
        entity('cs:Foo', internalName: 'FooProvider'),
      );
      expect(ref.healthKey, 'csp:FooProvider');
      expect(
        const ProviderRef(
          id: 'x',
          name: 'x',
          kind: ProviderKind.server,
        ).healthKey,
        'x',
      );
      final model = ProviderModel.fromJson({
        'id': 'cs:Foo',
        'name': 'Foo',
        'internalName': 'FooProvider',
      });
      expect(model.healthKey, 'csp:FooProvider');
      expect(model.toJson()['internalName'], 'FooProvider');
    });
  });
}
