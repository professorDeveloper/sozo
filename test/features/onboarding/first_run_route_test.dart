import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/splash/presentation/pages/splash_page.dart';

void main() {
  String? route({
    bool seen = false,
    bool signedIn = false,
    bool inProgress = false,
    String resume = '/onboarding/genres',
  }) => firstRunRoute(
    seen: seen,
    signedIn: signedIn,
    inProgress: inProgress,
    resumePath: () => resume,
  );

  test('a new install opens the setup', () {
    expect(route(), '/onboarding');
  });

  test('a setup under way resumes at its step', () {
    expect(route(inProgress: true), '/onboarding/genres');
  });

  test('a sign-in inside the setup does not end it', () {
    expect(route(signedIn: true, inProgress: true), '/onboarding/genres');
  });

  test('someone already signed in is never sent through it', () {
    expect(route(signedIn: true), isNull);
  });

  test('once seen, never again', () {
    expect(route(seen: true), isNull);
    expect(route(seen: true, inProgress: true), isNull);
    expect(route(seen: true, signedIn: true), isNull);
  });
}
