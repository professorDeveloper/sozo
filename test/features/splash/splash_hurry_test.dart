// A splash over an app that is already ready should end soon, but end the way
// it always does: the logo finished, then the fade.
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/splash/presentation/pages/splash_page.dart';
import 'package:soplay/features/splash/presentation/widgets/sozo_splash.dart';

void main() {
  test('mid-drawing, it finishes the logo quickly, then fades', () {
    final plan = hurryPlan(800)!;
    expect(plan.catchUp, isNotNull);
    expect(plan.catchUp!.inMilliseconds, lessThanOrEqualTo(hurryCap));
    expect(plan.catchUpTo, greaterThan(800));
  });

  test('with the logo finished and still, it goes straight to the fade', () {
    final plan = hurryPlan(1500)!;
    expect(plan.catchUp, isNull);
  });

  test('a foot already moving finishes its gesture first', () {
    final plan = hurryPlan(1900)!;
    expect(plan.catchUp, isNotNull);
    expect(plan.catchUpTo, greaterThan(1900));
  });

  test('already fading, nothing changes', () {
    expect(hurryPlan(splashTotalMs - 10.0), isNull);
  });

  test('the earliest finish is well under the full performance', () {
    final plan = hurryPlan(SozoSplash.minimum.inMilliseconds.toDouble())!;
    final total =
        SozoSplash.minimum.inMilliseconds +
        plan.catchUp!.inMilliseconds +
        300;
    expect(total, lessThan(splashTotalMs ~/ 2));
  });

  test('offline only when there is no connection of any kind', () {
    expect(isOffline([ConnectivityResult.none]), isTrue);
    expect(isOffline([ConnectivityResult.wifi]), isFalse);
    expect(
      isOffline([ConnectivityResult.none, ConnectivityResult.mobile]),
      isFalse,
    );
    expect(isOffline(const []), isFalse);
  });
}
