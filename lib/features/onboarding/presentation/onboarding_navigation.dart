import 'dart:async';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/content/content_mode.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/home/domain/home_rail.dart';
import 'package:soplay/features/onboarding/data/taste_sources.dart';
import 'package:soplay/features/onboarding/domain/onboarding_flow.dart';
import 'package:soplay/features/onboarding/domain/taste_profile.dart';
import 'package:soplay/features/onboarding/presentation/controllers/onboarding_controller.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_bloc.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_event.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_state.dart';
import 'package:soplay/features/profiles/data/profile_session.dart';
import 'package:soplay/features/profiles/domain/household_profile.dart';

OnboardingController get _controller => getIt<OnboardingController>();

/// The page every setup route is built with: a shared-axis move in the
/// reading direction, and a plain fade when animations are turned off.
Page<void> onboardingPage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    name: state.uri.path,
    child: child,
    transitionDuration: const Duration(milliseconds: 520),
    reverseTransitionDuration: const Duration(milliseconds: 420),
    transitionsBuilder: (context, animation, secondary, child) =>
        OnboardingSharedAxis(
          animation: animation,
          secondaryAnimation: secondary,
          child: child,
        ),
  );
}

class OnboardingSharedAxis extends StatelessWidget {
  const OnboardingSharedAxis({
    super.key,
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
  });

  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Widget child;

  static const Curve _emphasized = Cubic(0.05, 0.7, 0.1, 1.0);

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return FadeTransition(opacity: animation, child: child);
    }
    final dir = Directionality.of(context) == ui.TextDirection.rtl ? -1.0 : 1.0;
    final enter = CurvedAnimation(
      parent: animation,
      curve: _emphasized,
      reverseCurve: _emphasized.flipped,
    );
    final exit = CurvedAnimation(
      parent: secondaryAnimation,
      curve: _emphasized,
    );
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: animation,
        curve: const Interval(0.2, 1, curve: Curves.easeOut),
      ),
      child: SlideTransition(
        position: Tween(
          begin: Offset(0.14 * dir, 0),
          end: Offset.zero,
        ).animate(enter),
        child: FadeTransition(
          opacity: Tween(begin: 1.0, end: 0.0).animate(
            CurvedAnimation(
              parent: secondaryAnimation,
              curve: const Interval(0, 0.6, curve: Curves.easeIn),
            ),
          ),
          child: SlideTransition(
            position: Tween(
              begin: Offset.zero,
              end: Offset(-0.1 * dir, 0),
            ).animate(exit),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// On to the next step, or out of the setup when there is none.
Future<void> onboardingNext(BuildContext context) async {
  final router = GoRouter.of(context);
  final next = await _controller.advance();
  if (next == null) {
    if (context.mounted) await finishOnboarding(context);
    return;
  }
  unawaited(router.push(next.path));
}

/// Back one step. At the start of a Settings run this leaves the setup; at the
/// start of a first run there is nothing to go back to.
Future<void> onboardingBack(BuildContext context) async {
  final router = GoRouter.of(context);
  final c = _controller;
  final previous = await c.retreat();
  if (previous == null) {
    if (c.flow == OnboardingFlow.firstRun) {
      await SystemNavigator.pop();
      return;
    }
    await c.end();
    router.canPop() ? router.pop() : router.go('/main');
    return;
  }
  router.canPop() ? router.pop() : router.go(previous.path);
}

/// Where a sign-in lands: back into the setup when one is running, with the
/// profile picker first if the account has several; otherwise Home.
///
/// Several sign-in pages can hear the same success at once (register under
/// OTP), so concurrent calls share one navigation.
Future<void> goAfterAuth(BuildContext context) =>
    _afterAuth ??= _goAfterAuth(context).whenComplete(() => _afterAuth = null);

Future<void>? _afterAuth;

Future<void> _goAfterAuth(BuildContext context) async {
  final router = GoRouter.of(context);
  final c = _controller;
  if (!c.active || c.flow != OnboardingFlow.firstRun) {
    router.go('/main');
    return;
  }
  const beforeAuth = {OnboardingStep.welcome, OnboardingStep.account};
  final next = beforeAuth.contains(c.step)
      ? await c.advance() ?? OnboardingStep.done
      : c.step;
  var pick = false;
  try {
    final session = getIt<ProfileSession>();
    await session.refresh().timeout(const Duration(seconds: 3));
    pick = session.shouldPick;
  } catch (_) {}
  router.go(
    pick
        ? Uri(
            path: '/profiles',
            queryParameters: {'then': next.path},
          ).toString()
        : next.path,
  );
}

/// Settings → Personalize Sozo.
Future<void> startPersonalize(BuildContext context) async {
  final router = GoRouter.of(context);
  await _controller.begin(
    OnboardingFlow.personalize,
    seed: getIt<HiveService>().getTasteProfile(),
  );
  unawaited(router.push(OnboardingFlow.personalize.steps.first.path));
}

/// The short version, for a household profile that was just created.
Future<void> startProfilePersonalize(
  GoRouter router,
  HouseholdProfile profile,
) async {
  await _controller.begin(
    OnboardingFlow.profile,
    namespace: profile.namespace,
    seed: getIt<HiveService>().getTasteProfileFor(profile.namespace),
  );
  unawaited(router.push(OnboardingFlow.profile.steps.first.path));
}

/// Saves what was picked: the taste for the right profile, and — for the
/// profile using the device now — the mode and sources it implies.
Future<void> commitOnboardingTaste(BuildContext context) async {
  final c = _controller;
  final hive = getIt<HiveService>();
  final taste = c.taste;
  if (c.flow == OnboardingFlow.profile) {
    if (!taste.isEmpty) await hive.saveTasteProfileFor(c.namespace, taste);
    return;
  }
  if (taste.isEmpty) return;
  await hive.saveTasteProfile(taste);
  await _placePickedRail(hive);
  if (context.mounted && taste.kinds.isNotEmpty) {
    await _applySources(context, taste);
  }
}

/// A stored band order from before the band existed would put it last, under
/// the whole catalogue; it belongs under Continue Watching.
Future<void> _placePickedRail(HiveService hive) async {
  final stored = hive.getHomeRailOrder();
  final id = HomeRail.pickedForYou.id;
  if (stored.isEmpty || stored.contains(id)) return;
  final order = placeRailAfter(
    [for (final r in sanitizeRailOrder(stored)) r.id],
    id,
    HomeRail.resume.id,
  );
  await hive.saveHomeRails(order, hive.getHomeRailHidden());
}

Future<void> _applySources(BuildContext context, TasteProfile taste) async {
  final hive = getIt<HiveService>();
  ProviderBloc? bloc;
  try {
    bloc = context.read<ProviderBloc>();
  } catch (_) {}
  final state = bloc?.state;
  final loaded = state is ProviderLoaded ? state : null;
  final current = loaded?.currentProviderId ?? hive.getCurrentProvider();
  final plan = planTasteSources(
    modes: taste.modes,
    remembered: (m) => hive.providerForMode(m.id),
    currentId: current,
    usable: loaded == null
        ? null
        : [
            for (final p in loaded.providers)
              if (loaded.isUsable(p)) p,
          ],
    favorites: hive.getFavoriteProviders().toSet(),
  );
  for (final e in plan.remember.entries) {
    await hive.rememberProviderForMode(e.key.id, e.value);
  }
  final select = plan.select;
  if (select == null) return;
  if (current.isNotEmpty &&
      hive.providerForMode(current.contentMode.id) == null) {
    await hive.rememberProviderForMode(current.contentMode.id, current);
  }
  if (bloc != null) {
    bloc.add(ProviderSelect(select));
  } else {
    await hive.saveCurrentProvider(select);
    await hive.setContentMode(select.contentMode.id);
  }
}

/// Leaves the setup for good. A first run is marked seen here and nowhere
/// else, so one killed halfway resumes instead of being skipped.
Future<void> finishOnboarding(BuildContext context) async {
  final router = GoRouter.of(context);
  final c = _controller;
  final firstRun = c.flow == OnboardingFlow.firstRun;
  if (firstRun) await getIt<HiveService>().markOnboardingSeen();
  await c.end();
  final pick = firstRun && getIt<ProfileSession>().shouldPick;
  router.go(pick ? '/profiles' : '/main');
}

/// Asked right after a household profile is created.
Future<bool> offerProfilePersonalize(
  BuildContext context,
  HouseholdProfile profile,
) async {
  final yes = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      icon: Icon(Icons.auto_awesome_rounded, color: AppColors.primary),
      title: Text(
        'onboarding.profile_offer_title'.tr(args: [profile.name]),
        textAlign: TextAlign.center,
      ),
      content: Text(
        'onboarding.profile_offer_body'.tr(),
        textAlign: TextAlign.center,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('onboarding.not_now'.tr()),
        ),
        FilledButton(
          autofocus: true,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text('onboarding.profile_offer_yes'.tr()),
        ),
      ],
    ),
  );
  return yes ?? false;
}
