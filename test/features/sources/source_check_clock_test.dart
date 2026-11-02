// A phone whose clock is wrong must not lose what it knows.
//
// Every rule in the check table is about elapsed time, so a clock set forward —
// for an app, or because the device booted before it found the time — stamps
// every verdict in the future. Those rows are hidden while the clock is out,
// which is right. Deleting them is not: the correction comes minutes later and
// the table is gone for good.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/features/sources/data/source_check_store.dart';

void main() {
  late Box box;
  var clock = 0;

  setUpAll(() async {
    Hive.init('${Directory.systemTemp.path}/sozo_source_check_clock_test');
    box = await Hive.openBox('source_check_clock_test');
  });
  tearDownAll(Hive.close);

  setUp(() async {
    await box.clear();
    clock = DateTime.now().millisecondsSinceEpoch;
  });

  SourceCheckStore store() => SourceCheckStore(box: box, now: () => clock);

  test('a clock set forward hides the check table and then gives it back', () async {
    final written = store();
    for (final id in ['mn:1', 'mn:2', 'mn:3']) {
      await written.put(id, SourceCheck(verdict: SourceVerdict.alive, at: clock));
    }
    expect(written.of('mn:1')?.verdict, SourceVerdict.alive);

    // The clock jumps back two hours — every row is now stamped in the future.
    clock -= const Duration(hours: 2).inMilliseconds;
    final shifted = store();
    expect(
      shifted.of('mn:1'),
      isNull,
      reason: 'a verdict dated in the future is not shown',
    );

    // Any write at all rewrites the whole table. This is where three hundred
    // verdicts used to be deleted.
    await shifted.put(
      'mn:9',
      SourceCheck(verdict: SourceVerdict.alive, at: clock),
    );

    // The clock is corrected.
    clock += const Duration(hours: 2).inMilliseconds;
    final corrected = store();
    for (final id in ['mn:1', 'mn:2', 'mn:3']) {
      expect(
        corrected.of(id)?.verdict,
        SourceVerdict.alive,
        reason: '$id survived the write made under the wrong clock',
      );
    }
    // And from disk, not only from the copy in memory.
    expect(
      (box.get('source_checks') as Map).keys.map((k) => '$k').toSet(),
      {'mn:1', 'mn:2', 'mn:3', 'mn:9'},
    );
  });

  test('a verdict older than a week is still dropped on the way out', () async {
    final s = store();
    await s.put(
      'mn:old',
      SourceCheck(
        verdict: SourceVerdict.dead,
        at: clock - SourceCheckStore.staleAfter.inMilliseconds - 1,
      ),
    );
    await s.put('mn:new', SourceCheck(verdict: SourceVerdict.alive, at: clock));
    expect(
      (box.get('source_checks') as Map).keys.map((k) => '$k').toSet(),
      {'mn:new'},
      reason: 'the table stays the size of what was checked this week',
    );
  });
}
