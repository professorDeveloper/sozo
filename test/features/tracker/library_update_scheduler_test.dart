// Followed titles are checked on a schedule now, not only when the Following
// page is opened. These are the rules for when.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/features/tracker/data/follow_service.dart';
import 'package:soplay/features/tracker/data/library_update_scheduler.dart';

class _Follow implements FollowService {
  int calls = 0;
  Object? error;
  @override
  Future<int> checkForUpdates({
    int concurrency = 3,
    Duration timeout = const Duration(seconds: 12),
    bool notify = true,
  }) async {
    calls++;
    if (error != null) throw error!;
    return 2;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Box box;
  late _Follow follow;
  var now = DateTime(2026, 9, 23, 12);

  setUpAll(() async {
    Hive.init('${Directory.systemTemp.path}/sozo_library_update');
    box = await Hive.openBox('sozo_library_update');
  });
  tearDownAll(() async => Hive.close());

  setUp(() async {
    await box.clear();
    now = DateTime(2026, 9, 23, 12);
    follow = _Follow();
  });

  LibraryUpdateScheduler make() =>
      LibraryUpdateScheduler(follow: follow, box: box, now: () => now);

  test(
    'a first check is due, then not again until the interval passes',
    () async {
      final s = make();
      expect(s.intervalHours, LibraryUpdateScheduler.defaultHours);
      expect(await s.maybeRun(), 2);
      expect(await s.maybeRun(), 0, reason: 'just checked');
      now = now.add(const Duration(hours: 11));
      expect(s.due, isFalse);
      now = now.add(const Duration(hours: 1));
      expect(s.due, isTrue);
      expect(follow.calls, 1);
    },
  );

  test('off means never', () async {
    final s = make();
    await s.setIntervalHours(0);
    expect(s.due, isFalse);
    expect(await s.maybeRun(), 0);
    expect(follow.calls, 0);
  });

  test('a failed check is not retried on every resume', () async {
    follow.error = Exception('x');
    final s = make();
    expect(await s.maybeRun(), 0);
    expect(s.due, isFalse);
  });

  test('an unknown stored value falls back to the default', () async {
    await box.put('library_update_hours', 7);
    expect(make().intervalHours, LibraryUpdateScheduler.defaultHours);
  });
}
