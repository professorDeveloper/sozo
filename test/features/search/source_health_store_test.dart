import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/features/search/data/source_health_store.dart';

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

  test('a fast answer is ok, a slow one is slow, a failure is broken',
      () async {
    final s = SourceHealthStore();
    await s.record('fast', succeeded: true, elapsed: const Duration(milliseconds: 300), budget: base);
    await s.record('slow', succeeded: true, elapsed: const Duration(seconds: 9), budget: base);
    await s.record('dead', succeeded: false, elapsed: base, budget: base);

    expect(s.statusOf('fast'), SourceHealth.ok);
    expect(s.statusOf('slow'), SourceHealth.slow);
    expect(s.statusOf('dead'), SourceHealth.broken);
  });

  test('a source that answered at the buzzer is not called healthy', () async {
    // Both of these "succeeded". Only one of them should be asked first next
    // time, which is the entire reason elapsed time is recorded at all.
    final s = SourceHealthStore();
    await s.record('a', succeeded: true, elapsed: const Duration(seconds: 8), budget: base);
    expect(s.statusOf('a'), SourceHealth.slow);
  });

  test('the queue is ordered healthiest first, stably', () async {
    final s = SourceHealthStore();
    await s.record('dead', succeeded: false, elapsed: base, budget: base);
    await s.record('slow', succeeded: true, elapsed: const Duration(seconds: 9), budget: base);

    const set = <_Src>[(id: 'dead'), (id: 'good1'), (id: 'slow'), (id: 'good2')];
    final ordered = s.order(set, (r) => r.id);

    expect(ordered.map((r) => r.id).toList(), ['good1', 'good2', 'slow', 'dead']);
  });

  test('an untouched set is returned exactly as the user arranged it', () {
    // The order sources are listed in is the user's choice. Nothing has been
    // observed here, so there is nothing to justify moving any of it.
    const set = <_Src>[(id: 'c'), (id: 'a'), (id: 'b')];
    final ordered = SourceHealthStore().order(set, (r) => r.id);
    expect(identical(ordered, set), isTrue);
  });

  test('a broken source keeps its place in the queue, on a shorter leash',
      () async {
    // Ordered down, never dropped. "Down" is one observation from one device on
    // one network, and a source unreachable on mobile data is often fine on
    // wifi — the shorter budget lets it prove that without holding up the run.
    final s = SourceHealthStore();
    await s.record('dead', succeeded: false, elapsed: base, budget: base);

    expect(s.order(const <_Src>[(id: 'dead')], (r) => r.id), hasLength(1));
    expect(s.budgetFor('dead', base), SourceHealthStore.brokenBudget);
    expect(s.budgetFor('healthy', base), base);
  });

  test('a budget already shorter than the penalty is left alone', () {
    // Never lengthen a caller's timeout in the name of shortening it.
    const tight = Duration(seconds: 2);
    expect(SourceHealthStore().budgetFor('dead', tight), tight);
  });

  test('recovery is recorded, not held against the source', () async {
    final s = SourceHealthStore();
    await s.record('x', succeeded: false, elapsed: base, budget: base);
    expect(s.statusOf('x'), SourceHealth.broken);

    await s.record('x', succeeded: true, elapsed: const Duration(milliseconds: 200), budget: base);
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
}
