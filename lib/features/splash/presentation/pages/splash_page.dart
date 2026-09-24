import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/features/app_lock/domain/repositories/app_lock_repository.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/profiles/data/profile_session.dart';
import 'package:soplay/features/splash/presentation/widgets/sozo_splash.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  /// Where to go, decided while the animation is still finishing.
  ///
  /// The lock check reads a file and the onboarding check reads Hive. Starting
  /// both when the letter lands rather than when the animation ends overlaps
  /// them with the last 800ms, so the handover is a fade into a screen that is
  /// already resolved instead of a fade into a wait.
  Future<String>? _target;

  void _onSettled() => _target ??= _resolveRoute();

  Future<void> _onDone() async {
    final target = await (_target ??= _resolveRoute());
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
    if (!hive.hasOnboardingSeen && (hive.getToken() ?? '').isEmpty) {
      return '/onboarding';
    }
    return await _profilesDue() ? '/profiles' : '/main';
  }

  /// The cached list decides when there is one; otherwise the account is
  /// asked, but only briefly — a slow network must not hold the splash.
  Future<bool> _profilesDue() async {
    final session = getIt<ProfileSession>();
    if (!getIt<HiveService>().isLoggedIn) return false;
    final refreshed = session.refresh();
    if (session.profiles.isEmpty) {
      await refreshed.timeout(
        const Duration(milliseconds: 1500),
        onTimeout: () => false,
      );
    }
    return session.shouldPick;
  }

  @override
  Widget build(BuildContext context) {
    return SozoSplash(onSettled: _onSettled, onDone: _onDone);
  }
}
