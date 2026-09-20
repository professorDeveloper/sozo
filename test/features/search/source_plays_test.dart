// Searching well and playing are different skills.
//
// The source order was built entirely on evidence from the SEARCH — did it
// answer, and how fast. A source that answers in 200ms and then cannot produce
// a stream therefore sat ahead of one that takes a second and always plays,
// which is the wrong way round for the thing the viewer is actually asking for.
//
// The tally is saturated on purpose. Left to grow it would only ever go up, and
// two sources that had both clearly worked would be ordered by a margin nobody
// can see or change — fifty plays above forty-nine forever, even when the
// forty-nine answers in a fraction of the time.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/features/search/data/source_health_store.dart';

void main() {
  late Directory dir;
  late SourceHealthStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('source_plays');
    Hive.init(dir.path);
    await Hive.openBox(AppConstants.settingsBox);
    store = SourceHealthStore();
    await store.clear();
  });

  tearDown(() async {
    await Hive.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  List<String> order(List<String> ids) => store.order(ids, (id) => id);

  test('nothing has played until something does', () {
    expect(store.playsOf('an:a'), 0);
  });

  test('a play is counted', () async {
    await store.recordPlay('an:a');
    expect(store.playsOf('an:a'), 1);
  });

  test('and stops counting once proven', () async {
    for (var i = 0; i < 20; i++) {
      await store.recordPlay('an:a');
    }
    expect(store.playsOf('an:a'), SourceHealthStore.provenAt);
  });

  test('a proven source is asked before an unproven one', () async {
    await store.recordPlay('an:b');
    expect(order(['an:a', 'an:b', 'an:c']), ['an:b', 'an:a', 'an:c']);
  });

  test('but health still wins over it', () async {
    // A source that timed out last time has not earned the front by having
    // played a week ago, and its shortened budget makes it cheap to ask late.
    await store.recordPlay('an:broken');
    await store.record(
      'an:broken',
      succeeded: false,
      elapsed: const Duration(seconds: 10),
      budget: const Duration(seconds: 10),
    );
    expect(order(['an:broken', 'an:fresh']), ['an:fresh', 'an:broken']);
  });

  test('two proven sources keep the order they were given', () async {
    // The list arrives in the order the user arranged. Once both are proven
    // there is nothing here that should disturb it — which is exactly what the
    // cap is for.
    for (var i = 0; i < 9; i++) {
      await store.recordPlay('an:a');
    }
    await store.recordPlay('an:b');
    await store.recordPlay('an:b');
    await store.recordPlay('an:b');
    expect(order(['an:b', 'an:a']), ['an:b', 'an:a']);
    expect(order(['an:a', 'an:b']), ['an:a', 'an:b']);
  });

  test('with nothing recorded at all the list is returned untouched', () {
    final input = ['an:a', 'an:b', 'an:c'];
    expect(identical(order(input), input), isTrue);
  });

  test('clearing forgets the plays too', () async {
    await store.recordPlay('an:a');
    await store.clear();
    expect(store.playsOf('an:a'), 0);
  });

  test('with no box at all, nothing throws', () async {
    await Hive.close();
    expect(store.playsOf('an:a'), 0);
    expect(() async => store.recordPlay('an:a'), returnsNormally);
  });

  test('the play is recorded at the first frame, not at resolve', () {
    // A resolved url is not a playing one: a dead mirror, a 403 on the first
    // segment and a codec the device cannot decode all resolve perfectly and
    // never play.
    final media = File(
      'lib/features/detail/presentation/pages/player_page.media.dart',
    ).readAsStringSync();
    final recordAt = media.indexOf('recordPlay(');
    final startedAt = media.indexOf("_plog('play started");
    expect(recordAt, greaterThan(-1));
    expect(startedAt, greaterThan(-1));
    expect(recordAt, greaterThan(startedAt));
  });
}
