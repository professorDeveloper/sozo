// The offline check of a profile PIN: what is kept, when it is dropped, and
// that guessing on the device is slowed down the way the app lock is.
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/app_lock/data/pin_secrets.dart';
import 'package:soplay/features/app_lock/domain/entities/pin_check.dart';
import 'package:soplay/features/profiles/data/profile_pin_store.dart';

class _FakeBiometrics extends DeviceBiometrics {
  bool available = true;
  bool accept = true;
  int asked = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate(String reason) async {
    asked++;
    return accept;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime now;
  late _FakeBiometrics bio;
  late FlutterSecureStorage secure;
  late ProfilePinStore store;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    secure = const FlutterSecureStorage();
    now = DateTime(2026, 11, 7, 12);
    bio = _FakeBiometrics();
    store = ProfilePinStore(
      secureStorage: secure,
      biometrics: bio,
      clock: () => now,
      iterations: 10,
    );
  });

  test('nothing is known before a PIN was accepted here', () async {
    expect(await store.has('acc', 'p1'), isFalse);
    expect(
      (await store.check('acc', 'p1', '1234')).outcome,
      PinCheck.unavailable,
    );
  });

  test('keeps a salted hash, never the PIN', () async {
    await store.remember('acc', 'p1', '4821');
    final raw = await secure.read(key: ProfilePinStore.storageKey);
    expect(raw, isNotNull);
    expect(raw, isNot(contains('4821')));
    expect(raw, contains('pbkdf2'));
    expect(await store.has('acc', 'p1'), isTrue);
  });

  test('checks the PIN it was given', () async {
    await store.remember('acc', 'p1', '4821');
    expect((await store.check('acc', 'p1', '4821')).isOk, isTrue);
    expect((await store.check('acc', 'p1', '1111')).outcome, PinCheck.wrong);
  });

  test('is per account and per profile', () async {
    await store.remember('acc', 'p1', '4821');
    expect(
      (await store.check('other', 'p1', '4821')).outcome,
      PinCheck.unavailable,
    );
    expect(
      (await store.check('acc', 'p2', '4821')).outcome,
      PinCheck.unavailable,
    );
  });

  test('a new PIN replaces the old one', () async {
    await store.remember('acc', 'p1', '4821');
    await store.remember('acc', 'p1', '9090');
    expect((await store.check('acc', 'p1', '4821')).outcome, PinCheck.wrong);
    expect((await store.check('acc', 'p1', '9090')).isOk, isTrue);
  });

  test('forget, retain and clear drop verifiers', () async {
    await store.remember('acc', 'p1', '1111');
    await store.remember('acc', 'p2', '2222');
    await store.remember('acc', 'p3', '3333');
    await store.remember('other', 'p1', '4444');

    await store.forget('acc', 'p1');
    expect(await store.has('acc', 'p1'), isFalse);
    expect(await store.has('acc', 'p2'), isTrue);

    await store.retain('acc', {'p3'});
    expect(await store.has('acc', 'p2'), isFalse);
    expect(await store.has('acc', 'p3'), isTrue);
    expect(await store.has('other', 'p1'), isTrue);

    await store.clear();
    expect(await store.has('acc', 'p3'), isFalse);
    expect(await store.has('other', 'p1'), isFalse);
    expect(await secure.read(key: ProfilePinStore.storageKey), isNull);
  });

  test('wrong guesses lock it out, as the app lock does', () async {
    await store.remember('acc', 'p1', '4821');
    for (var i = 1; i < PinBackoff.freeAttempts; i++) {
      final r = await store.check('acc', 'p1', '0000');
      expect(r.outcome, PinCheck.wrong);
      expect(r.attemptsLeft, PinBackoff.freeAttempts - i);
    }
    final locked = await store.check('acc', 'p1', '0000');
    expect(locked.outcome, PinCheck.lockedOut);
    expect(locked.retryAt, now.add(PinBackoff.firstWait));

    // Even the right PIN waits.
    expect(
      (await store.check('acc', 'p1', '4821')).outcome,
      PinCheck.lockedOut,
    );

    now = now.add(PinBackoff.firstWait + const Duration(seconds: 1));
    expect((await store.check('acc', 'p1', '4821')).isOk, isTrue);

    // A right PIN starts the count again.
    expect((await store.check('acc', 'p1', '0000')).attemptsLeft, 4);
  });

  test('the wait doubles and is capped', () {
    expect(PinBackoff.waitAfter(4), isNull);
    expect(PinBackoff.waitAfter(5), const Duration(seconds: 30));
    expect(PinBackoff.waitAfter(6), const Duration(seconds: 60));
    expect(PinBackoff.waitAfter(40), PinBackoff.maxWait);
  });

  group('biometrics', () {
    test('offered once, only with a verifier and a sensor', () async {
      expect(await store.shouldOfferBiometric('acc', 'p1'), isFalse);
      await store.remember('acc', 'p1', '4821');
      bio.available = false;
      expect(await store.shouldOfferBiometric('acc', 'p1'), isFalse);
      bio.available = true;
      expect(await store.shouldOfferBiometric('acc', 'p1'), isTrue);
      await store.markBiometricOffered('acc', 'p1');
      expect(await store.shouldOfferBiometric('acc', 'p1'), isFalse);
    });

    test('unlocks only when turned on for that profile', () async {
      await store.remember('acc', 'p1', '4821');
      expect(await store.unlockWithBiometric('acc', 'p1', 'r'), isFalse);
      expect(bio.asked, 0);

      await store.setBiometric('acc', 'p1', true);
      expect(await store.canUnlockWithBiometric('acc', 'p1'), isTrue);
      expect(await store.unlockWithBiometric('acc', 'p1', 'r'), isTrue);

      bio.accept = false;
      expect(await store.unlockWithBiometric('acc', 'p1', 'r'), isFalse);
    });

    test('survives a PIN change, not a forget', () async {
      await store.remember('acc', 'p1', '4821');
      await store.setBiometric('acc', 'p1', true);
      await store.remember('acc', 'p1', '9090');
      expect(await store.biometricEnabled('acc', 'p1'), isTrue);
      await store.forget('acc', 'p1');
      expect(await store.biometricEnabled('acc', 'p1'), isFalse);
    });
  });
}
