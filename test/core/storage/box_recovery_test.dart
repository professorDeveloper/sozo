// A damaged box must not cost the user their data, and must not stop the app.
//
// Hive's default is `crashRecovery: true`, and what that does on a bad checksum
// is truncate the file to the last frame it could read. For a torn tail that is
// right; for damage near the front it is the whole box, and the only trace is a
// print on a console nobody is attached to. The nine boxes behind it are the
// history, the resume positions, My List and the downloads index.
//
// The other half: those nine were opened by bare `Hive.openBox` calls inside one
// `Future.wait` before `runApp`, so a file the filesystem would not hand over
// was a blank screen with no message.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/core/storage/box_recovery.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('box_recovery');
    Hive.init(dir.path);
    BoxRecovery.resetForTest();
  });

  tearDown(() async {
    await Hive.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  File fileOf(String name) => File('${dir.path}/${name.toLowerCase()}.hive');

  /// Writes a real box, then damages it after [keepFrames] entries.
  Future<void> writeThenDamage(
    String name, {
    required int entries,
    required int keepFrames,
  }) async {
    final box = await Hive.openBox(name);
    for (var i = 0; i < entries; i++) {
      await box.put('k$i', 'v$i');
    }
    await box.close();
    final file = fileOf(name);
    final bytes = await file.readAsBytes();
    // Each put is one frame; overwrite the tail with bytes no reader can make a
    // frame out of, which is what an interrupted write leaves behind.
    final cut = (bytes.length * keepFrames / entries).floor();
    final broken = <int>[
      ...bytes.sublist(0, cut),
      for (var i = 0; i < 64; i++) 0xFF,
    ];
    await file.writeAsBytes(broken, flush: true);
  }

  test('a clean box opens and is not reported as damaged', () async {
    final box = await Hive.openBox('clean');
    await box.put('a', 1);
    await box.close();

    final reopened = await BoxRecovery.open('clean', directory: dir.path);
    expect(reopened.get('a'), 1);
    expect(BoxRecovery.damaged, isEmpty);
    expect(File('${fileOf('clean').path}.unreadable').existsSync(), isFalse);
  });

  test('a torn tail keeps every frame before the damage', () async {
    await writeThenDamage('history', entries: 10, keepFrames: 7);

    final box = await BoxRecovery.open('history', directory: dir.path);
    expect(box.get('k0'), 'v0');
    expect(box.length, greaterThan(1), reason: 'recovery kept nothing');
    expect(BoxRecovery.damaged, contains('history'));
  });

  test('and the original file is still there to recover from', () async {
    await writeThenDamage('history', entries: 10, keepFrames: 7);
    final before = await fileOf('history').readAsBytes();

    await BoxRecovery.open('history', directory: dir.path);

    final kept = File('${fileOf('history').path}.unreadable');
    expect(kept.existsSync(), isTrue);
    expect(
      kept.readAsBytesSync(),
      before,
      reason: 'the copy has to predate the truncation, byte for byte',
    );
    // The live file was rewritten shorter; that is the point of the copy.
    expect(fileOf('history').lengthSync(), lessThan(before.length));
  });

  test('a second bad launch does not overwrite the first copy', () async {
    await writeThenDamage('history', entries: 10, keepFrames: 7);
    final original = await fileOf('history').readAsBytes();
    await BoxRecovery.open('history', directory: dir.path);
    await Hive.box('history').close();

    // Damage it again, now that it holds far less.
    await writeThenDamage('history', entries: 3, keepFrames: 1);
    BoxRecovery.resetForTest();
    await BoxRecovery.open('history', directory: dir.path);

    expect(
      File('${fileOf('history').path}.unreadable').readAsBytesSync(),
      original,
      reason: 'the newer, emptier file replaced the one worth keeping',
    );
  });

  test('a file that is not a box at all still opens, empty', () async {
    // Damage at the very front: nothing is recoverable, so the box has to come
    // back empty rather than the launch coming back not at all.
    await fileOf(
      'settings',
    ).writeAsBytes(List<int>.filled(256, 0x7F), flush: true);

    final box = await BoxRecovery.open('settings', directory: dir.path);
    expect(box.isOpen, isTrue);
    expect(box.isEmpty, isTrue);
    expect(BoxRecovery.damaged, contains('settings'));
    expect(
      File('${fileOf('settings').path}.unreadable').existsSync(),
      isTrue,
      reason: 'unreadable is not the same as worthless',
    );
  });

  test('the fresh box is writable, not a read-only stand-in', () async {
    await fileOf(
      'settings',
    ).writeAsBytes(List<int>.filled(256, 0x7F), flush: true);
    final box = await BoxRecovery.open('settings', directory: dir.path);
    await box.put('theme', 'dark');
    await box.close();

    final again = await Hive.openBox('settings');
    expect(again.get('theme'), 'dark');
  });

  test('with nowhere to preserve it, the box still opens', () async {
    // No directory means no copy can be made, and overwriting the file would be
    // the exact loss this class exists to stop. So it runs in memory.
    await fileOf(
      'streak',
    ).writeAsBytes(List<int>.filled(256, 0x7F), flush: true);
    final before = fileOf('streak').lengthSync();

    final box = await BoxRecovery.open('streak');
    expect(box.isOpen, isTrue);
    expect(
      fileOf('streak').lengthSync(),
      before,
      reason: 'the file was touched',
    );
  });
}
