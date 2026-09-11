import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/features/app_lock/domain/repositories/app_lock_repository.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/splash/presentation/widgets/netflix_splash.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  void _onComplete() {
    unawaited(_resolveRoute());
  }

  Future<void> _resolveRoute() async {
    final lock = getIt<AppLockRepository>();
    await lock.ensureConsistent();
    if (!mounted) return;
    // The PIN itself is asked for by the lock overlay, which has covered the
    // app since the first frame (see AppLockGate) — so a deep link that lands
    // before this runs is behind it too.
    if (lock.isEnabled) {
      context.go('/main');
      return;
    }
    // Once, on a device nobody has signed in on. A PIN means the device has
    // been used before, so the question only arises on the branch with no lock
    // to unlock.
    final hive = getIt<HiveService>();
    if (!hive.hasOnboardingSeen && (hive.getToken() ?? '').isEmpty) {
      context.go('/onboarding');
      return;
    }
    context.go('/main');
  }

  @override
  Widget build(BuildContext context) {
    return NetflixSplash(onComplete: _onComplete);
  }
}
