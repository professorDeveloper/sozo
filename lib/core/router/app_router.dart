import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/features/link_tv/presentation/pages/link_tv_page.dart';
import 'package:soplay/features/app_lock/presentation/pages/app_lock_settings_page.dart';
import 'package:soplay/features/app_lock/presentation/pages/pin_setup_page.dart';
import 'package:soplay/features/app_lock/presentation/pages/pin_verify_page.dart';
import 'package:soplay/features/desktop_share/presentation/pages/desktop_share_page.dart';
import 'package:soplay/features/auth/presentation/pages/forgot_password_page.dart';
import 'package:soplay/features/auth/presentation/pages/login_page.dart';
import 'package:soplay/features/onboarding/presentation/pages/onboarding_page.dart';
import 'package:soplay/features/auth/presentation/pages/otp_verify_page.dart';
import 'package:soplay/features/auth/presentation/pages/register_page.dart';
import 'package:soplay/features/detail/domain/entities/detail_args.dart';
import 'package:soplay/features/detail/domain/entities/episodes_args.dart';
import 'package:soplay/features/detail/domain/entities/player_args.dart';
import 'package:soplay/features/detail/presentation/pages/actor_page.dart';
import 'package:soplay/features/detail/presentation/pages/detail_page.dart';
import 'package:soplay/features/detail/presentation/pages/episodes_page.dart';
import 'package:soplay/features/detail/presentation/pages/player_page.dart';
import 'package:soplay/features/download/presentation/pages/downloads_page.dart';
import 'package:soplay/features/history/presentation/pages/history_page.dart';
import 'package:soplay/features/home/domain/entities/view_all.dart';
import 'package:soplay/features/manga/domain/entities/reader_args.dart';
import 'package:soplay/features/manga/presentation/pages/reader_page.dart';
import 'package:soplay/features/main/presentation/pages/main_page.dart';
import 'package:soplay/features/network/presentation/pages/no_internet_page.dart';
import 'package:soplay/features/search/presentation/pages/cross_search_page.dart';
import 'package:soplay/features/anilist/presentation/pages/anilist_browse_page.dart';
import 'package:soplay/features/anilist/presentation/pages/airing_calendar_page.dart';
import 'package:soplay/features/anilist/presentation/pages/anilist_library_page.dart';
import 'package:soplay/features/anilist/presentation/pages/anilist_links_page.dart';
import 'package:soplay/features/mal/presentation/pages/mal_library_page.dart';
import 'package:soplay/features/mal/presentation/pages/mal_links_page.dart';
import 'package:soplay/features/anilist/presentation/pages/connections_page.dart';
import 'package:soplay/features/anilist/presentation/pages/upcoming_page.dart';
import 'package:soplay/features/tracker/presentation/pages/following_page.dart';
import 'package:soplay/features/trivia/domain/entities/cast_person_entity.dart';
import 'package:soplay/features/trivia/domain/entities/trivia_result_entity.dart';
import 'package:soplay/features/trivia/presentation/pages/actor_hero_page.dart';
import 'package:soplay/features/trivia/presentation/pages/cast_picker_page.dart';
import 'package:soplay/features/trivia/presentation/pages/challenge_landing_page.dart';
import 'package:soplay/features/trivia/presentation/pages/game_page.dart';
import 'package:soplay/features/trivia/presentation/pages/leaderboard_page.dart';
import 'package:soplay/features/trivia/presentation/pages/result_page.dart';
import 'package:soplay/features/trivia/presentation/pages/top_fans_page.dart';
import 'package:soplay/features/trivia/presentation/trivia_args.dart';
import 'package:soplay/features/user_lists/domain/entities/user_list_kind.dart';
import 'package:soplay/features/user_lists/presentation/pages/user_lists_page.dart';
import 'package:soplay/features/profile/presentation/pages/appearance_page.dart';
import 'package:soplay/features/profile/presentation/pages/player_settings_page.dart';
import 'package:soplay/features/profile/presentation/pages/providers_page.dart';
import 'package:soplay/features/live_tv/presentation/pages/live_tv_page.dart';
import 'package:soplay/features/remote/presentation/pages/tv_remote_page.dart';
import 'package:soplay/features/profile/presentation/pages/profile_page.dart';
import 'package:soplay/features/auth/domain/entities/user_entity.dart';
import 'package:soplay/features/profile/presentation/pages/profile_edit_page.dart';
import 'package:soplay/features/notifications/presentation/pages/notifications_page.dart';
import 'package:soplay/features/private_list/presentation/pages/private_list_page.dart';
import 'package:soplay/features/splash/presentation/pages/splash_page.dart';
import 'package:soplay/features/streak/presentation/pages/streak_page.dart';
import 'package:soplay/features/watch_party/presentation/party_entry.dart';
import 'package:soplay/features/watch_party/presentation/pages/watch_party_page.dart';

import '../../features/home/presentation/pages/home_view_all_page.dart';

class AppRouter {
  AppRouter._();

  static bool dismissTopmost() {
    final nav = router.routerDelegate.navigatorKey.currentState;
    if (nav != null && nav.canPop()) {
      nav.maybePop();
      return true;
    }
    return false;
  }

  static final router = GoRouter(
    initialLocation: '/splash',
    // Android hands every ACTION_VIEW intent's URL to the router as route
    // information, including ones the app claims for reasons that have nothing
    // to do with navigation — the extension-index intent filters
    // (`…/index.pb`, `…/index.min.json`) are exactly that. Those have no route
    // and used to land the user on a bare "Page Not Found" behind the install
    // sheet. Anything unroutable now falls back to the app itself; the sheet or
    // DeeplinkService has already taken whatever meaning the URL carried.
    onException: (_, state, router) {
      debugPrint('[Router] no route for ${state.uri} — falling back to /main');
      router.go('/main');
    },
    observers: Platform.isAndroid
        ? [FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance)]
        : [],
    routes: [
      GoRoute(
        path: '/view-all',
        builder: (context, state) {
          final args = state.extra as ViewAllEntity;
          final slug = args.slug;
          final title = args.name.isNotEmpty
              ? args.name
              : (slug.isEmpty ? args.type : slug);
          return HomeViewAllPage(
            keyCat: args.type,
            slug: args.slug,
            title: title,
          );
        },
      ),
      GoRoute(
        path: '/detail',
        builder: (context, state) {
          final extra = state.extra;
          if (extra is DetailArgs) return DetailPage(args: extra);
          final q = state.uri.queryParameters;
          final url = q['url'] ?? '';
          final provider = q['provider']?.trim();
          return DetailPage(
            args: DetailArgs(
              contentUrl: url,
              provider: provider != null && provider.isNotEmpty
                  ? provider
                  : null,
            ),
          );
        },
      ),
      GoRoute(
        path: '/episodes',
        builder: (context, state) {
          final args = state.extra as EpisodesArgs;
          return EpisodesPage(args: args);
        },
      ),
      // Watch Later / Watched. `extra` optionally carries the tab to open on,
      // so a shortcut can deep-link straight to one list.
      GoRoute(
        path: '/my-lists',
        builder: (context, state) =>
            UserListsPage(initialKind: state.extra as UserListKind?),
      ),
      GoRoute(
        path: '/actor',
        builder: (context, state) {
          final args = state.extra as ActorArgs;
          return ActorPage(args: args);
        },
      ),
      GoRoute(
        path: '/player',
        builder: (context, state) {
          final args = state.extra as PlayerArgs;
          return PlayerPage(args: args);
        },
      ),
      GoRoute(
        path: '/reader',
        builder: (context, state) {
          final args = state.extra as ReaderArgs;
          return ReaderPage(args: args);
        },
      ),
      GoRoute(
        path: '/history',
        builder: (context, state) => const HistoryPage(),
      ),
      GoRoute(
        path: '/downloads',
        builder: (context, state) => const DownloadsPage(),
      ),
      GoRoute(
        path: '/desktop-share',
        builder: (context, state) => const DesktopSharePage(),
      ),
      GoRoute(
        path: '/no-internet',
        builder: (context, state) => const NoInternetPage(),
      ),
      GoRoute(
        path: '/cross-search',
        builder: (context, state) {
          // Either a bare query, or a query with the sources to search.
          final extra = state.extra;
          if (extra is CrossSearchRequest) {
            return CrossSearchPage(
              initialQuery: extra.query,
              initialProviderIds: extra.providerIds,
            );
          }
          return CrossSearchPage(initialQuery: extra as String?);
        },
      ),
      GoRoute(
        path: '/following',
        builder: (context, state) => const FollowingPage(),
      ),
      GoRoute(
        path: '/live-tv',
        builder: (context, state) => const LiveTvPage(),
      ),
      GoRoute(
        path: '/tv-remote',
        builder: (context, state) => const TvRemotePage(),
      ),
      GoRoute(
        path: '/connections',
        builder: (context, state) => const ConnectionsPage(),
      ),
      GoRoute(
        path: '/upcoming',
        builder: (context, state) => const UpcomingPage(),
      ),
      // Declared before '/anilist' would matter only for a prefix router; go_router
      // matches full paths, so the order here is just readability.
      GoRoute(
        path: '/anilist',
        builder: (context, state) => const AnilistLibraryPage(),
      ),
      GoRoute(
        path: '/anilist/browse',
        builder: (context, state) => const AnilistBrowsePage(),
      ),
      GoRoute(
        path: '/anilist/calendar',
        builder: (context, state) => const AiringCalendarPage(),
      ),
      GoRoute(
        path: '/anilist/links',
        builder: (context, state) => const AnilistLinksPage(),
      ),
      GoRoute(
        path: '/mal',
        builder: (context, state) => const MalLibraryPage(),
      ),
      GoRoute(
        path: '/mal/links',
        builder: (context, state) => const MalLinksPage(),
      ),
      GoRoute(
        path: '/appearance',
        builder: (context, state) => const AppearancePage(),
      ),
      GoRoute(
        path: '/navbar',
        builder: (context, state) => const NavbarPage(),
      ),
      GoRoute(
        path: '/player-settings',
        builder: (context, state) => const PlayerSettingsPage(),
      ),
      GoRoute(
        path: '/providers',
        builder: (context, state) => const ProvidersPage(),
      ),
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const NotificationsPage(),
      ),
      GoRoute(
        path: '/streak',
        builder: (context, state) => const StreakPage(),
      ),
      GoRoute(
        path: '/watch-party',
        builder: (context, state) {
          final extra = state.extra;
          return WatchPartyPage(
            code: extra is WatchPartyArgs
                ? extra.code
                : state.uri.queryParameters['code'],
          );
        },
      ),
      GoRoute(
        path: '/link-tv',
        builder: (context, state) =>
            LinkTvPage(initialCode: state.uri.queryParameters['code']),
      ),
      GoRoute(path: '/splash', builder: (context, state) => const SplashPage()),
      GoRoute(path: '/main', builder: (context, state) => const MainPage()),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingPage(),
      ),
      GoRoute(
        path: '/profile/edit',
        builder: (context, state) {
          final user = state.extra as UserEntity?;
          // Reached only from a signed-in profile, but a cold deep link would
          // arrive with nothing to edit.
          if (user == null) return const ProfilePage();
          return ProfileEditPage(user: user);
        },
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) =>
            ForgotPasswordPage(initialEmail: state.extra as String?),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterPage(),
      ),
      GoRoute(
        path: '/otp',
        builder: (context, state) {
          final email = state.extra as String? ?? '';
          return OtpVerifyPage(email: email);
        },
      ),
      GoRoute(
        path: '/pin-verify',
        builder: (context, state) {
          final redirect = state.uri.queryParameters['redirect'] ?? '/main';
          return PinVerifyPage(redirectTo: redirect);
        },
      ),
      GoRoute(
        path: '/pin-setup',
        builder: (context, state) {
          final change = state.extra == true;
          return PinSetupPage(changeMode: change);
        },
      ),
      GoRoute(
        path: '/app-lock-settings',
        builder: (context, state) => const AppLockSettingsPage(),
      ),
      GoRoute(
        path: '/private-list',
        builder: (context, state) => const PrivateListPage(),
      ),
      GoRoute(
        path: '/trivia/cast',
        builder: (context, state) => const CastPickerPage(),
      ),
      GoRoute(
        path: '/trivia/actor',
        builder: (context, state) =>
            ActorHeroPage(person: state.extra as CastPersonEntity),
      ),
      GoRoute(
        path: '/trivia/game',
        builder: (context, state) => GamePage(args: state.extra as GameArgs),
      ),
      GoRoute(
        path: '/trivia/result',
        builder: (context, state) {
          // `extra` carries the actor alongside the result; a bare result is
          // still accepted (legacy pushes) and degrades to a brand-only share
          // card with an actor-less replay.
          final extra = state.extra;
          if (extra is ResultArgs) {
            return ResultPage(result: extra.result, actor: extra.actor);
          }
          return ResultPage(result: extra as TriviaResultEntity);
        },
      ),
      GoRoute(
        path: '/trivia/leaderboard',
        builder: (context, state) => const LeaderboardPage(),
      ),
      GoRoute(
        path: '/trivia/top-fans',
        builder: (context, state) {
          // `extra` carries the kind alongside the id; a bare int is still
          // accepted (legacy pushes) and falls back to the live-actor kind.
          final extra = state.extra;
          if (extra is TopFansArgs) {
            return TopFansPage(actorId: extra.actorId, kind: extra.kind);
          }
          return TopFansPage(actorId: extra is int ? extra : 0);
        },
      ),
      GoRoute(
        path: '/trivia/challenge/:code',
        builder: (context, state) =>
            ChallengeLandingPage(code: state.pathParameters['code']!),
      ),
    ],
  );
}
