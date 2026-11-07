import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/features/app_lock/domain/repositories/app_lock_repository.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/onboarding/domain/onboarding_flow.dart';
import 'package:soplay/features/onboarding/presentation/controllers/onboarding_controller.dart';
import 'package:soplay/features/profiles/data/profile_session.dart';
import 'package:soplay/features/splash/presentation/widgets/sozo_splash.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  /// Where to go, decided while the animation plays.
  ///
  /// Started with the splash: once it is known, the splash hurries to its
  /// fade instead of playing the full three seconds over an app that is
  /// already waiting.
  late final Future<String> _target = _resolveRoute();

  Future<void> _onDone() async {
    final target = await _target;
    if (!mounted) return;
    context.go(target);
  }

  Future<String> _resolveRoute() async {
    final lock = getIt<AppLockRepository>();
    await lock.ensureConsistent();
    // The PIN itself is asked for by the lock overlay, which has covered the
    // app since the first frame (see AppLockGate) — so a deep link that lands
    // before this runs is behind it too.
    if (lock.isEnabled) return await _profilesDue() ? '/profiles' : '/main';
    // Once, on a device nobody has signed in on. A PIN means the device has
    // been used before, so the question only arises on the branch with no lock
    // to unlock.
    final hive = getIt<HiveService>();
    final onboarding = getIt<OnboardingController>();
    final route = firstRunRoute(
      seen: hive.hasOnboardingSeen,
      signedIn: (hive.getToken() ?? '').isNotEmpty,
      inProgress:
          onboarding.active && onboarding.flow == OnboardingFlow.firstRun,
      resumePath: onboarding.resumePath,
    );
    if (route != null) return route;
    return await _profilesDue() ? '/profiles' : '/main';
  }

  /// The cached list decides when there is one; otherwise the account is
  /// asked, but only briefly — a slow network must not hold the splash, and
  /// no network is not waited for at all.
  Future<bool> _profilesDue() async {
    final session = getIt<ProfileSession>();
    if (!getIt<HiveService>().isLoggedIn) return false;
    final refreshed = session.refresh();
    if (session.profiles.isEmpty && !await _offline()) {
      await refreshed.timeout(
        const Duration(milliseconds: 1500),
        onTimeout: () => false,
      );
    }
    return session.shouldPick;
  }

  Future<bool> _offline() async {
    try {
      final kinds = await Connectivity().checkConnectivity().timeout(
        const Duration(milliseconds: 300),
      );
      return isOffline(kinds);
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SozoSplash(onDone: _onDone, ready: _target);
  }
}

/// No connection of any kind. An empty answer is not taken as offline.
bool isOffline(List<ConnectivityResult> kinds) =>
    kinds.isNotEmpty && kinds.every((k) => k == ConnectivityResult.none);

/// The setup a launch should open, or null for the app itself.
///
/// Once per install, on a device nobody has signed in on. A setup already
/// under way resumes at its step even after the sign-in inside it; someone
/// who was signed in before it ever started is never sent through it.
String? firstRunRoute({
  required bool seen,
  required bool signedIn,
  required bool inProgress,
  required String Function() resumePath,
}) {
  if (seen) return null;
  if (inProgress) return resumePath();
  return signedIn ? null : '/onboarding';
}
