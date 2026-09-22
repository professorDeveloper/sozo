// The splash played behind the PIN pad on every locked device, so the people
// who use the lock — the ones most likely to open this app every day — never
// saw it. The fix exempts exactly one route from being covered, and the whole
// risk of that is in the word "exactly".
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/app_lock/presentation/widgets/app_lock_overlay.dart';

void main() {
  test('unlocked covers nothing', () {
    expect(lockCovers(locked: false, path: '/main'), isFalse);
    expect(lockCovers(locked: false, path: '/splash'), isFalse);
  });

  test('locked covers every route', () {
    for (final path in [
      '/main',
      '/detail',
      '/player',
      '/watch-services',
      '/onboarding',
      '/',
    ]) {
      expect(lockCovers(locked: true, path: path), isTrue, reason: path);
    }
  });

  test('except the splash, which has nothing to cover', () {
    expect(lockCovers(locked: true, path: '/splash'), isFalse);
  });

  test('and exactly the splash — not anything that merely starts like it', () {
    // A prefix match would uncover a route somebody adds later without ever
    // meaning to. The exemption is one path, compared whole.
    expect(lockCovers(locked: true, path: '/splash/debug'), isTrue);
    expect(lockCovers(locked: true, path: '/splashes'), isTrue);
    expect(lockCovers(locked: true, path: '/Splash'), isTrue);
  });
}
