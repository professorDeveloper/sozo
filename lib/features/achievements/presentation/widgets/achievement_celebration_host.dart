import 'dart:async';

import 'package:flutter/material.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/router/app_router.dart';
import 'package:soplay/features/achievements/data/achievements_service.dart';
import 'package:soplay/features/achievements/presentation/dialogs/achievement_unlocked_dialog.dart';
import 'package:soplay/features/progress/data/progress_service.dart';
import 'package:soplay/features/progress/presentation/dialogs/level_up_dialog.dart';

/// Shows badges as they are earned — but never over something being watched
/// or read.
///
/// A badge is usually earned by the history sync that runs while an episode
/// plays. A dialog over the player would stop the episode to say "you are
/// watching episodes", so it waits: the celebration comes when the viewer
/// leaves the player or the reader, on whatever screen they land on.
class AchievementCelebrationHost extends StatefulWidget {
  const AchievementCelebrationHost({super.key, required this.child});

  final Widget child;

  /// Screens a celebration never interrupts.
  static const Set<String> quietPaths = {
    '/player',
    '/reader',
    '/splash',
    '/onboarding',
    '/profiles',
    '/login',
  };

  @override
  State<AchievementCelebrationHost> createState() =>
      _AchievementCelebrationHostState();
}

class _AchievementCelebrationHostState
    extends State<AchievementCelebrationHost> {
  AchievementsService? _service;
  ProgressService? _progress;
  bool _showing = false;
  Timer? _settle;

  @override
  void initState() {
    super.initState();
    if (getIt.isRegistered<ProgressService>()) {
      _progress = getIt<ProgressService>()
        ..pendingLevelUp.addListener(_schedule);
    }
    if (!getIt.isRegistered<AchievementsService>()) return;
    _service = getIt<AchievementsService>()..pending.addListener(_schedule);
    AppRouter.router.routerDelegate.addListener(_schedule);
  }

  @override
  void dispose() {
    _settle?.cancel();
    _service?.pending.removeListener(_schedule);
    _progress?.pendingLevelUp.removeListener(_schedule);
    AppRouter.router.routerDelegate.removeListener(_schedule);
    super.dispose();
  }

  /// Waits for navigation to settle: a dialog opened mid-transition lands
  /// on the page being left.
  void _schedule() {
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 900), _maybeShow);
  }

  Future<void> _maybeShow() async {
    final service = _service;
    if (service == null || _showing || !mounted) return;
    final levelUp = _progress?.pendingLevelUp.value;
    if (service.pending.value.isEmpty && levelUp == null) return;
    final path = AppRouter.router.routerDelegate.currentConfiguration.uri.path;
    if (AchievementCelebrationHost.quietPaths.contains(path)) return;
    final context = AppRouter.router.routerDelegate.navigatorKey.currentContext;
    if (context == null) return;

    _showing = true;
    try {
      // The numbers the dialog shows next tiers from; a moment's wait is
      // better than a dialog with no "next" line.
      await service.refresh().timeout(
        const Duration(seconds: 3),
        onTimeout: () {},
      );
      if (!context.mounted) return;
      final unlocks = service.takePending();
      if (unlocks.isNotEmpty) {
        await AchievementUnlockedDialog.show(
          context,
          unlocks,
          view: service.state.value,
          onSeeAll: () => AppRouter.router.push('/achievements'),
        );
      }
      // A badge often brings the level with it; one after the other.
      final up = _progress?.takeLevelUp();
      if (up != null && context.mounted) {
        await LevelUpDialog.show(
          context,
          up,
          onOpen: () => AppRouter.router.push('/progress'),
        );
      }
    } finally {
      _showing = false;
    }
    if (mounted &&
        (service.pending.value.isNotEmpty ||
            _progress?.pendingLevelUp.value != null)) {
      _schedule();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
