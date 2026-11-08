// Off Android there is no Crashlytics; the crash log is the only record.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/diagnostics/crash_log.dart';
import 'package:soplay/features/support/data/support_diagnostics.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sozo_crash_');
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  test('records an error with its stack', () {
    final log = CrashLog(dir);
    log.record(StateError('boom'), StackTrace.fromString('#0 main'));
    final text = log.read();
    expect(text, contains('boom'));
    expect(text, contains('#0 main'));
  });

  test('rotates at the size cap and keeps at most maxFiles', () {
    final log = CrashLog(dir, maxBytes: 300, maxFiles: 3);
    for (var i = 0; i < 40; i++) {
      log.record('error number $i ${'x' * 60}', null);
    }
    final files = log.files;
    expect(files, hasLength(3));
    for (final f in files) {
      expect(f.lengthSync(), lessThanOrEqualTo(300));
    }
    expect(
      dir.listSync().whereType<File>().length,
      3,
      reason: 'nothing past the oldest is left behind',
    );
    final text = log.read();
    expect(text, contains('error number 39 '), reason: 'newest kept');
    expect(text, isNot(contains('error number 0 ')), reason: 'oldest gone');
    // Oldest first in what is read back.
    expect(
      text.indexOf('error number 38 '),
      lessThan(text.indexOf('error number 39 ')),
    );
  });

  test('read can be cut to its newest end', () {
    final log = CrashLog(dir);
    log.record('first', null);
    log.record('second', null);
    final tail = log.read(maxChars: 20);
    expect(tail.length, 20);
    expect(tail, contains('second'));
  });

  test('redacts what the player log redacts', () {
    final log = CrashLog(dir);
    log.record('GET https://x.test/v?token=abcdef123456 failed', null);
    expect(log.read(), isNot(contains('abcdef123456')));
  });

  test('clear removes every file', () {
    final log = CrashLog(dir, maxBytes: 100);
    for (var i = 0; i < 10; i++) {
      log.record('e$i ${'y' * 50}', null);
    }
    log.clear();
    expect(log.files, isEmpty);
    expect(log.read(), isEmpty);
  });

  test('support diagnostics carry it at the end of the log field', () {
    expect(SupportDiagnostics.withCrashLog('player', null), 'player');
    expect(SupportDiagnostics.withCrashLog(null, ''), isNull);
    final both = SupportDiagnostics.withCrashLog('player', 'crash')!;
    expect(both, startsWith('player'));
    expect(both, endsWith('${SupportDiagnostics.crashHeader}\ncrash'));
  });
}
