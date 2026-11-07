import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/watch_party/domain/pending_party_code.dart';

void main() {
  late String? stored;
  late DateTime now;
  late PendingPartyCode pending;

  setUp(() {
    stored = null;
    now = DateTime(2026, 11, 7, 12);
    pending = PendingPartyCode(
      read: () => stored,
      write: (v) async => stored = v,
      clock: () => now,
    );
  });

  test('normalizes codes and rejects what cannot be one', () {
    expect(PendingPartyCode.normalize(' ab2c9z '), 'AB2C9Z');
    expect(PendingPartyCode.normalize('abc'), isNull);
    expect(PendingPartyCode.normalize('ab-12'), isNull);
    expect(PendingPartyCode.normalize(null), isNull);
  });

  test('a code kept through sign-in opens exactly once', () async {
    await pending.remember('k7m2qp');
    expect(pending.peek(), 'K7M2QP');
    // Sign-in took a while.
    now = now.add(const Duration(minutes: 20));
    expect(await pending.take(), 'K7M2QP');
    expect(await pending.take(), isNull);
    expect(stored, isNull);
  });

  test('an invite left too long is dropped', () async {
    await pending.remember('K7M2QP');
    now = now.add(PendingPartyCode.ttl + const Duration(minutes: 1));
    expect(await pending.take(), isNull);
    expect(stored, isNull);
  });

  test('a bad code is never stored, and a newer invite replaces an older', () async {
    await pending.remember('x');
    expect(stored, isNull);
    await pending.remember('AAAA22');
    await pending.remember('BBBB33');
    expect(await pending.take(), 'BBBB33');
  });

  test('garbage in storage reads as nothing', () async {
    stored = 'not a code|abc';
    expect(pending.peek(), isNull);
    expect(await pending.take(), isNull);
    expect(stored, isNull);
  });

  test('cancelling sign-in clears it', () async {
    await pending.remember('K7M2QP');
    await pending.clear();
    expect(pending.peek(), isNull);
  });
}
