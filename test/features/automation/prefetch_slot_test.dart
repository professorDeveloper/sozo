import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/automation/domain/prefetch_slot.dart';

void main() {
  var now = DateTime(2026, 9, 24, 12);
  PrefetchSlot<String> make() => PrefetchSlot<String>(now: () => now);

  setUp(() => now = DateTime(2026, 9, 24, 12));

  test('a filled key is taken once', () async {
    final slot = make();
    await slot.fill('ep2', () async => 'media');
    expect(slot.covers('ep2'), isTrue);
    expect(await slot.take('ep3'), isNull, reason: 'another key');
    expect(await slot.take('ep2'), 'media');
    expect(await slot.take('ep2'), isNull);
  });

  test('a stale value is not handed over', () async {
    final slot = make();
    await slot.fill('ep2', () async => 'media');
    now = now.add(const Duration(minutes: 11));
    expect(slot.covers('ep2'), isFalse);
    expect(await slot.take('ep2'), isNull);
  });

  test('a load in flight is joined, not repeated', () async {
    final slot = make();
    final gate = Completer<String>();
    var loads = 0;
    unawaited(
      slot.fill('ep2', () {
        loads++;
        return gate.future;
      }),
    );
    await slot.fill('ep2', () async {
      loads++;
      return 'again';
    });
    final taken = slot.take('ep2');
    gate.complete('media');
    expect(await taken, 'media');
    expect(loads, 1);
  });

  test('a failing load leaves nothing behind', () async {
    final slot = make();
    await slot.fill('ep2', () async => throw Exception('x'));
    expect(slot.covers('ep2'), isFalse);
    expect(await slot.take('ep2'), isNull);
  });

  test('prefetch starts at 80%', () {
    const d = Duration(minutes: 20);
    expect(NextUp.shouldPrefetch(const Duration(minutes: 15), d), isFalse);
    expect(NextUp.shouldPrefetch(const Duration(minutes: 16), d), isTrue);
    expect(NextUp.shouldPrefetch(Duration.zero, Duration.zero), isFalse);
  });

  test('the prompt counts down to the auto-advance', () {
    const d = Duration(minutes: 24);
    int? left(Duration remaining, {int countdown = 10}) =>
        NextUp.promptSecondsLeft(
          position: d - remaining,
          duration: d,
          countdownSeconds: countdown,
        );
    expect(left(const Duration(seconds: 13)), isNull);
    expect(left(const Duration(seconds: 12)), 10);
    expect(left(const Duration(milliseconds: 6500)), 5);
    expect(left(const Duration(seconds: 1)), 0);
    expect(left(const Duration(seconds: 5), countdown: 0), isNull);
    expect(
      NextUp.promptSecondsLeft(
        position: const Duration(seconds: 50),
        duration: const Duration(seconds: 55),
        countdownSeconds: 10,
      ),
      isNull,
      reason: 'too short to prompt',
    );
  });
}
