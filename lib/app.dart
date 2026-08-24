import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:soplay/core/navigation/app_tab.dart';
import 'package:soplay/core/navigation/nav_controller.dart';
import 'package:soplay/core/system/platform_utils.dart';
import 'package:soplay/core/tv/tv.dart';
import 'package:soplay/features/auth/presentation/bloc/auth_event.dart';
import 'package:soplay/features/detail/domain/entities/detail_args.dart';
import 'package:soplay/features/home/presentation/bloc/view_all/view_all_bloc.dart';
import 'package:soplay/features/notifications/data/services/notification_service.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_bloc.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_event.dart';
import 'package:soplay/features/search/presentation/blocs/search_bloc.dart';

import 'core/di/injection.dart';
import 'core/router/app_router.dart';
import 'core/system/desktop_window.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';
import 'features/home/presentation/bloc/home/home_bloc.dart';

/// Desktop scroll behaviour: adds mouse + trackpad + stylus as drag devices so
/// touch-oriented scrollables (PageView, horizontal ListViews) can be dragged
/// with a pointer, and keeps a visible scrollbar.
class _DesktopScrollBehavior extends MaterialScrollBehavior {
  const _DesktopScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => <PointerDeviceKind>{
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final ThemeController _theme = getIt<ThemeController>();

  @override
  void initState() {
    super.initState();
    _theme.addListener(_onThemeChanged);
    getIt<NotificationService>().onTap = _handlePushTap;
    // Desktop: hide the custom title-bar strip on the immersive full-bleed
    // routes (player / reader) by watching the router itself — reliable
    // regardless of a page's initState timing.
    if (isDesktopPlatform) {
      AppRouter.router.routerDelegate.addListener(_syncImmersive);
      _syncImmersive();
    }
  }

  /// Set [DesktopWindow.immersive] from the current top-of-stack route.
  void _syncImmersive() {
    try {
      final path =
          AppRouter.router.routerDelegate.currentConfiguration.uri.path;
      DesktopWindow.immersive.value = path == '/player' || path == '/reader';
    } catch (_) {}
  }

  @override
  void dispose() {
    _theme.removeListener(_onThemeChanged);
    if (isDesktopPlatform) {
      AppRouter.router.routerDelegate.removeListener(_syncImmersive);
    }
    getIt<NotificationService>().onTap = null;
    super.dispose();
  }

  /// Repaint the entire app in the newly chosen colours, without a restart and
  /// without losing a single route, scroll offset or piece of widget state.
  ///
  /// Two things have to happen, and neither one covers the other:
  ///
  ///   * `setState` re-reads [AppTheme.dark], so every Material component
  ///     default (buttons, inputs, tab indicators, dialogs) picks up the new
  ///     palette through `Theme.of`,
  ///   * [_rebuildEverything] marks the rest of the tree dirty, because the
  ///     ~1900 direct `AppColors.*` reads are plain static getters — they have
  ///     no `InheritedWidget` to notify them, so nothing else would ever tell
  ///     those widgets that their colours moved.
  void _onThemeChanged() {
    if (!mounted) return;
    setState(() {});
    _rebuildEverything();
  }

  /// Mark every element below this one for rebuild.
  ///
  /// `markNeedsBuild` works on the *element*, so it reaches widgets a normal
  /// parent rebuild would skip — including `const` ones, which is most of this
  /// app's leaf UI.
  ///
  /// Guarded on the scheduler phase: a notification that arrives mid-build
  /// (a theme set from inside a `build`, which nothing does today but is cheap
  /// to be safe about) would otherwise assert. In that case it is deferred by
  /// one frame instead.
  void _rebuildEverything() {
    void markDirty(Element element) {
      element.markNeedsBuild();
      element.visitChildren(markDirty);
    }

    void run() {
      if (!mounted) return;
      (context as Element).visitChildren(markDirty);
    }

    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => run());
    } else {
      run();
    }
  }

  void _handlePushTap(Map<String, dynamic> data) {
    final router = AppRouter.router;

    // Watch-party invites arrive as type:'system_other' + data.roomCode, so a
    // type-based branch would never fire — key off roomCode before the switch.
    final roomCode = data['roomCode'];
    if (roomCode is String && roomCode.isNotEmpty) {
      router.push('/watch-party?code=$roomCode');
      return;
    }

    final type = data['type']?.toString() ?? '';
    final contentUrl = data['contentUrl']?.toString();
    final provider = data['provider']?.toString();

    switch (type) {
      case 'system_comment_reply':
      case 'system_comment_like':
        if (contentUrl != null && contentUrl.isNotEmpty) {
          router.push(
            '/detail',
            extra: DetailArgs(contentUrl: contentUrl, provider: provider),
          );
        } else {
          router.push('/notifications');
        }
      case 'system_ban':
        getIt<AuthBloc>().add(AuthSessionExpired());
        router.go('/login');
      case 'system_unban':
      case 'admin_broadcast':
      case 'admin_direct':
        router.push('/notifications');
      case 'streak_risk':
        getIt<NavController>().goToId(TabId.profile);
      default:
        router.push('/notifications');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<AuthBloc>.value(value: getIt<AuthBloc>()),
        BlocProvider<ViewAllBloc>(create: (_) => getIt<ViewAllBloc>()),
        BlocProvider<HomeBloc>(create: (_) => getIt<HomeBloc>()),
        BlocProvider<SearchBloc>(create: (_) => getIt<SearchBloc>()),
        BlocProvider<ProviderBloc>(
          create: (_) => getIt<ProviderBloc>()..add(const ProviderLoad()),
        ),
      ],
      child: MaterialApp.router(
        title: 'app_name'.tr(),
        debugShowCheckedModeBanner: false,
        // The colour the OS paints behind the app — the task-switcher card and
        // the gap before the first frame. Left at its default it is the theme's
        // primary, so an accent change would otherwise leave a red card behind
        // a blue app.
        color: AppColors.background,
        theme: AppTheme.dark,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.dark,
        // Desktop: let horizontal rows / carousels / the Shorts feed be dragged
        // with a mouse & trackpad. Mobile keeps Flutter's default behaviour.
        scrollBehavior: isDesktopPlatform ? const _DesktopScrollBehavior() : null,
        routerConfig: AppRouter.router,
        // Desktop: a custom frameless title bar + Esc-to-dismiss (closes the
        // topmost dialog/sheet, else pops the page). Mobile returns the child
        // unchanged.
        builder: (context, child) {
          final app = child ?? const SizedBox.shrink();
          // Android TV: Flutter's default shortcut map activates the focused
          // widget on enter/space, but a remote's OK button arrives as
          // DPAD_CENTER (LogicalKeyboardKey.select) and a game controller's as
          // gameButtonA. Without these two bindings the D-pad can move focus
          // but can never press anything. Additive + TV-gated: phone and
          // desktop fall through to the paths below unchanged.
          if (isTvPlatform) return TvShortcuts(child: app);
          if (!isDesktopPlatform) return app;
          final shell = Column(
            children: [
              const WindowTitleBar(),
              Expanded(child: app),
            ],
          );
          return CallbackShortcuts(
            bindings: {
              // Dismiss the topmost route on the real Navigator — a dialog/sheet
              // if one is open, otherwise the page. (GoRouter.pop() ignores
              // imperative overlays and would pop the page under a dialog.)
              const SingleActivator(LogicalKeyboardKey.escape):
                  AppRouter.dismissTopmost,
            },
            child: Focus(autofocus: true, child: shell),
          );
        },
        localizationsDelegates: context.localizationDelegates,
        supportedLocales: context.supportedLocales,
        locale: context.locale,
      ),
    );
  }
}
