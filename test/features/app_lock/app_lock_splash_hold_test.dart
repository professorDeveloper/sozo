// The splash played behind the PIN pad, so on a locked device nobody ever saw
// it. The lock exists to cover content, and the splash has none — it is the
// app's own mark on a black field, which is what the launcher icon already
// shows to anybody holding the phone.
//
// Holding a lock open is not a thing to be casual about, so what is asserted
// here is mostly the ways the hold ENDS.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/app_lock/domain/repositories/app_lock_repository.dart';
import 'package:soplay/features/app_lock/presentation/app_lock_gate.dart';

class _Repo implements AppLockRepository {
  _Repo({this.enabled = true});

  bool enabled;

  @override
  bool get isEnabled => enabled;

  // The gate reads exactly one thing off the repository. Everything else on
  // the interface belongs to the PIN screen, which is not what is under test.
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a device with a PIN starts locked', () {
    final gate = AppLockGate(_Repo());
    addTearDown(gate.dispose);
    expect(gate.isLocked, isTrue);
  });

  test('and the splash may hold that off', () {
    final gate = AppLockGate(_Repo());
    addTearDown(gate.dispose);
    gate.holdForSplash();
    expect(gate.isLocked, isFalse);
    gate.releaseSplashHold();
    expect(gate.isLocked, isTrue, reason: 'the hold must not outlive release');
  });

  testWidgets('the hold expires on its own', (tester) async {
    // The important one. If the splash crashes mid-animation the app must end
    // up locked, not open — so the hold cannot depend on anybody calling back.
    final gate = AppLockGate(_Repo());
    addTearDown(gate.dispose);
    gate.holdForSplash();
    expect(gate.isLocked, isFalse);

    await tester.pump(const Duration(seconds: 3));
    expect(gate.isLocked, isFalse, reason: 'it expired before the splash ends');

    await tester.pump(const Duration(seconds: 2));
    expect(gate.isLocked, isTrue);
  });

  testWidgets('and backgrounding the app drops it at once', (tester) async {
    final gate = AppLockGate(_Repo());
    addTearDown(gate.dispose);
    gate.holdForSplash();

    gate.didChangeAppLifecycleState(AppLifecycleState.paused);

    expect(
      gate.isLocked,
      isTrue,
      reason: 'whatever the splash was doing, it is not on screen now',
    );
  });

  test('and it changes nothing on a device with no PIN', () {
    final gate = AppLockGate(_Repo(enabled: false));
    addTearDown(gate.dispose);
    expect(gate.isLocked, isFalse);
    gate.holdForSplash();
    expect(gate.isLocked, isFalse);
    gate.releaseSplashHold();
    expect(gate.isLocked, isFalse);
  });

  test('releasing without holding is not an error', () {
    final gate = AppLockGate(_Repo());
    addTearDown(gate.dispose);
    gate.releaseSplashHold();
    expect(gate.isLocked, isTrue);
  });
}
