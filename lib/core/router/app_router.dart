import 'dart:io';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:soplay/features/notifications/presentation/pages/notification_settings_page.dart';
import 'package:soplay/features/tracker/presentation/pages/release_feed_page.dart';
import 'package:soplay/features/trakt/presentation/trakt_hub_page.dart';
import 'package:soplay/features/watch_services/presentation/pages/watch_service_browse_page.dart';
import 'package:soplay/features/watch_services/presentation/pages/watch_services_page.dart';
import 'package:soplay/features/profile/presentation/pages/discord_settings_page.dart';
import 'package:soplay/features/profile/presentation/pages/discord_web_login_page.dart';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/widgets/bloom_page_transition.dart';
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
import 'package:soplay/features/torrent/presentation/pages/torrent_search_page.dart';
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
import 'package:soplay/features/profiles/domain/household_profile.dart';
import 'package:soplay/features/profiles/presentation/pages/manage_profiles_page.dart';
import 'package:soplay/features/profiles/presentation/pages/household_profile_edit_page.dart';
import 'package:soplay/features/profiles/presentation/pages/profile_picker_page.dart';
import 'package:soplay/features/profile/presentation/pages/player_settings_page.dart';
import 'package:soplay/features/profile/presentation/pages/providers_page.dart';
import 'package:soplay/features/profile/presentation/pages/about_page.dart';
import 'package:soplay/features/profile/presentation/pages/activity_page.dart';
import 'package:soplay/features/profile/presentation/pages/backup_page.dart';
import 'package:soplay/features/profile/presentation/pages/library_page.dart';
import 'package:soplay/features/profile/presentation/pages/profile_connections_page.dart';
import 'package:soplay/features/profile/presentation/pages/settings_page.dart';
import 'package:soplay/features/sources/presentation/pages/sources_hub_page.dart';
import 'package:soplay/features/live_tv/presentation/pages/live_tv_page.dart';
import 'package:soplay/features/remote/presentation/pages/tv_remote_page.dart';
import 'package:soplay/features/profile/presentation/pages/profile_page.dart';
import 'package:soplay/features/auth/domain/entities/user_entity.dart';
import 'package:soplay/features/profile/presentation/pages/profile_edit_page.dart';
import 'package:soplay/features/notifications/presentation/pages/notifications_page.dart';
import 'package:soplay/features/private_list/presentation/pages/private_list_page.dart';
import 'package:soplay/features/social/presentation/pages/friends_page.dart';
import 'package:soplay/features/social/presentation/pages/social_privacy_page.dart';
import 'package:soplay/features/social/presentation/pages/user_profile_page.dart';
import 'package:soplay/features/social/presentation/pages/user_search_page.dart';
import 'package:soplay/features/splash/presentation/pages/splash_page.dart';
import 'package:soplay/features/streak/presentation/pages/streak_page.dart';
import 'package:soplay/features/automation/presentation/pages/automation_settings_page.dart';
import 'package:soplay/features/watch_party/presentation/party_entry.dart';
import 'package:soplay/features/watch_party/presentation/pages/watch_party_page.dart';

import '../../features/home/presentation/pages/home_view_all_page.dart';
import '../../features/home/presentation/pages/genres_page.dart';
import '../../features/search/domain/entities/genre_entity.dart';

/// The arrival every "opening a thing" route shares.
///
/// [BloomPageTransition] began on /detail and stayed there, which put two
/// arrival languages one tap apart: a title bloomed in, and the cast member,
/// the episode list or the "see all" behind it slid in from the side. The
/// routes listed against this helper are all the same gesture — something on
/// screen was chosen and it opens — so they arrive the same way.
///
/// /player and /reader are deliberately not among them. Those are a change of
/// mode rather than a thing being opened, and they have transitions that say
/// so.
///
/// And iOS is deliberately not among them either — it keeps the platform page,
/// bloom or no bloom. A [CustomTransitionPage] carries its own
/// `transitionsBuilder`, so the route never consults the theme's
/// [PageTransitionsTheme]; on iOS that theme's [CupertinoPageTransitionsBuilder]
/// is the one thing that wraps the page in the back-gesture detector. Bloom an
/// iOS route and the swipe from the left edge — how iOS users leave a screen,
/// on every app, without looking — quietly stops working, and on a phone held
/// one-handed the back button in the corner is not a substitute. A shared
/// arrival is worth having; it is not worth the way out. Everywhere else there
/// is no such gesture to lose, so everywhere else blooms.
Page<void> _bloomPage(GoRouterState state, Widget child) {
  // Named, because a hand-built Page does not get the name go_router puts on
  // the one it builds for a plain `builder:`, and Android's
  // FirebaseAnalyticsObserver reads the screen name straight off
  // RouteSettings.name and logs nothing at all when it is null. Left off, the
  // five routes below are the only screens in the app that stop reporting.
  final name = state.name ?? state.path;
  final restorationId = state.pageKey.value;
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    return MaterialPage<void>(
      key: state.pageKey,
      name: name,
      restorationId: restorationId,
      child: child,
    );
  }
  return CustomTransitionPage<void>(
    key: state.pageKey,
    name: name,
    restorationId: restorationId,
    child: child,
    transitionDuration: BloomPageTransition.duration,
    reverseTransitionDuration: BloomPageTransition.reverseDuration,
    transitionsBuilder: (context, animation, secondary, child) =>
        BloomPageTransition(
          animation: animation,
          secondaryAnimation: secondary,
          child: child,
        ),
  );
}

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
        pageBuilder: (context, state) {
          final args = state.extra as ViewAllEntity;
          final slug = args.slug;
          final title = args.name.isNotEmpty
              ? args.name
              : (slug.isEmpty ? args.type : slug);
          return _bloomPage(
            state,
            HomeViewAllPage(keyCat: args.type, slug: args.slug, title: title),
          );
        },
      ),
      GoRoute(
        path: '/detail',
        pageBuilder: (context, state) {
          final extra = state.extra;
          final args = extra is DetailArgs
              ? extra
              : () {
                  final q = state.uri.queryParameters;
                  final provider = q['provider']?.trim();
                  return DetailArgs(
                    contentUrl: q['url'] ?? '',
                    provider: provider != null && provider.isNotEmpty
                        ? provider
                        : null,
                  );
                }();

          // The page blooms in rather than sliding: no poster flies any more
          // (PosterHero.flightEnabled has been false since the glide arrived
          // as a stall and a jump), so the arrival is the whole page rising
          // and sharpening — see BloomPageTransition and the header's bloom.
          // Off iOS, where [_bloomPage] hands back the platform page so the
          // edge swipe survives.
          return _bloomPage(state, DetailPage(args: args));
        },
      ),
      GoRoute(
        path: '/episodes',
        pageBuilder: (context, state) {
          final args = state.extra as EpisodesArgs;
          return _bloomPage(state, EpisodesPage(args: args));
        },
      ),
      // Watch Later / Watched. `extra` optionally carries the tab to open on,
      // so a shortcut can deep-link straight to one list.
      GoRoute(
        path: '/my-lists',
        pageBuilder: (context, state) => _bloomPage(
          state,
          UserListsPage(initialKind: state.extra as UserListKind?),
        ),
      ),
      GoRoute(
        path: '/actor',
        pageBuilder: (context, state) {
          final args = state.extra as ActorArgs;
          return _bloomPage(state, ActorPage(args: args));
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
        // Pops a `TorrentStreamHandle` when the user picks a torrent, so the
        // caller decides what to do with the stream. `extra` pre-fills the
        // search box — set when arriving from a title's detail page.
        path: '/torrents',
        builder: (context, state) =>
            TorrentSearchPage(initialQuery: state.extra as String?),
      ),
      GoRoute(
        path: '/following',
        builder: (context, state) => const FollowingPage(),
      ),
      GoRoute(
        path: '/releases',
        pageBuilder: (context, state) =>
            _bloomPage(state, const ReleaseFeedPage()),
      ),
      GoRoute(
        path: '/notification-settings',
        builder: (context, state) => const NotificationSettingsPage(),
      ),
      GoRoute(
        path: '/live-tv',
        builder: (context, state) => const LiveTvPage(),
      ),
      GoRoute(
        path: '/genres',
        // A url with no list is a link from nowhere: Home is where the genres
        // are, so that is where it goes.
        redirect: (context, state) =>
            state.extra is List<GenreEntity> ? null : '/main',
        builder: (context, state) =>
            GenresPage(genres: state.extra! as List<GenreEntity>),
      ),
      GoRoute(
        path: '/watch-services',
        builder: (context, state) => const WatchServicesPage(),
      ),
      GoRoute(
        path: '/watch-service',
        builder: (context, state) {
          final extra = state.extra;
          if (extra is! WatchServiceArgs) return const WatchServicesPage();
          return WatchServiceBrowsePage(args: extra);
        },
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
      GoRoute(path: '/trakt', builder: (context, state) => const TraktHubPage()),
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
      GoRoute(path: '/navbar', builder: (context, state) => const NavbarPage()),
      GoRoute(
        path: '/player-settings',
        builder: (context, state) => const PlayerSettingsPage(),
      ),
      GoRoute(
        path: '/automation',
        builder: (context, state) => const AutomationSettingsPage(),
      ),
      GoRoute(
        path: '/discord',
        builder: (context, state) => const DiscordSettingsPage(),
      ),
      GoRoute(
        path: '/discord/login',
        builder: (context, state) => const DiscordWebLoginPage(),
      ),
      GoRoute(
        path: '/providers',
        builder: (context, state) => const ProvidersPage(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsPage(),
      ),
      GoRoute(
        path: '/library',
        builder: (context, state) => const LibraryPage(),
      ),
      GoRoute(
        path: '/activity',
        builder: (context, state) => const ActivityPage(),
      ),
      GoRoute(path: '/backup', builder: (context, state) => const BackupPage()),
      GoRoute(
        path: '/sources',
        builder: (context, state) => const SourcesHubPage(),
      ),
      GoRoute(
        path: '/profile/connections',
        builder: (context, state) => const ProfileConnectionsPage(),
      ),
      GoRoute(path: '/about', builder: (context, state) => const AboutPage()),
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const NotificationsPage(),
      ),
      GoRoute(path: '/streak', builder: (context, state) => const StreakPage()),
      GoRoute(
        path: '/friends',
        builder: (context, state) => FriendsPage(
          initialTab: FriendsPage.tabFrom(state.uri.queryParameters['tab']),
        ),
      ),
      GoRoute(
        path: '/friends/search',
        builder: (context, state) => const UserSearchPage(),
      ),
      GoRoute(
        path: '/friends/privacy',
        builder: (context, state) => const SocialPrivacyPage(),
      ),
      GoRoute(
        path: '/friends/blocked',
        builder: (context, state) => const BlockedUsersPage(),
      ),
      GoRoute(
        path: '/u/:username',
        builder: (context, state) =>
            UserProfilePage(username: state.pathParameters['username']!),
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
        path: '/profiles',
        builder: (context, state) => const ProfilePickerPage(),
      ),
      GoRoute(
        path: '/profiles/manage',
        builder: (context, state) => const ManageProfilesPage(),
      ),
      GoRoute(
        path: '/profiles/edit',
        builder: (context, state) =>
            HouseholdProfileEditPage(profile: state.extra as HouseholdProfile?),
      ),
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
