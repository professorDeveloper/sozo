import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/features/notifications/data/priming_cooldown.dart';

void main() {
  late Box box;
  var now = DateTime(2026, 9, 24);

  setUpAll(() async {
    Hive.init('${Directory.systemTemp.path}/sozo_priming');
    box = await Hive.openBox('sozo_priming');
  });
  tearDownAll(() async => Hive.close());
  setUp(() async {
    await box.clear();
    now = DateTime(2026, 9, 24);
  });

  PrimingCooldown make() => PrimingCooldown(box: box, now: () => now);

  test('asks the first time', () {
    expect(make().canAsk, isTrue);
  });

  test('each "Not now" waits longer: 3 days, 14, then 30', () async {
    final c = make();
    await c.declined();
    now = now.add(const Duration(days: 2));
    expect(c.canAsk, isFalse);
    now = now.add(const Duration(days: 1));
    expect(c.canAsk, isTrue);

    await c.declined();
    now = now.add(const Duration(days: 13));
    expect(c.canAsk, isFalse);
    now = now.add(const Duration(days: 1));
    expect(c.canAsk, isTrue);

    await c.declined();
    await c.declined();
    expect(c.currentWait, const Duration(days: 30));
  });

  test('granting clears the history', () async {
    final c = make();
    await c.declined();
    await c.accepted();
    expect(c.canAsk, isTrue);
    expect(c.declines, 0);
  });

  test('remembers that the system prompt was raised', () async {
    final c = make();
    expect(c.systemPromptShown, isFalse);
    await c.markSystemPromptShown();
    expect(make().systemPromptShown, isTrue);
  });
}
