import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/navigation/app_tab.dart';
import 'package:soplay/core/navigation/nav_controller.dart';
import 'package:soplay/core/router/app_router.dart';
import 'package:soplay/core/storage/profile_scope.dart';
import 'package:soplay/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:soplay/features/auth/presentation/bloc/auth_event.dart';
import 'package:soplay/features/detail/domain/entities/detail_args.dart';
import 'package:soplay/features/home/presentation/bloc/home/home_bloc.dart';
import 'package:soplay/features/home/presentation/bloc/home/home_event.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_bloc.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_event.dart';
import 'package:soplay/features/profiles/data/profile_session.dart';
import 'package:soplay/features/profiles/presentation/profile_flows.dart';

/// What a tap asks for, worked out without touching the router so it can be
/// tested on its own.
enum NotificationAction { push, go, signOut, streakTab, none }

typedef NotificationRoute = ({
  NotificationAction action,
  String location,
  Object? extra,
});

const NotificationRoute _nothing = (
  action: NotificationAction.none,
  location: '',
  extra: null,
);

NotificationRoute _push(String location, [Object? extra]) =>
    (action: NotificationAction.push, location: location, extra: extra);

int? _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');

/// Where a notification takes the user — shared by a tapped push and a tapped
/// row in the notifications list, which used to disagree: the list only marked
/// the row read, so the same "someone replied to your comment" that opened the
/// title from the lock screen went nowhere from inside the app.
///
/// [fromList] is set for the in-app list, where "open the notifications page"
/// — the fallback for a push — would mean staying put, so it does nothing.
NotificationRoute resolveNotificationRoute(
  Map<String, dynamic> data, {
  bool fromList = false,
}) {
  // Watch-party invites arrive as type:'system_other' + data.roomCode, so a
  // type-based branch would never fire — key off roomCode before the switch.
  final roomCode = data['roomCode'];
  if (roomCode is String && roomCode.isNotEmpty) {
    return _push('/watch-party?code=${Uri.encodeComponent(roomCode)}');
  }

  final type = data['type']?.toString() ?? '';
  final contentUrl = data['contentUrl']?.toString();
  final provider = data['provider']?.toString();
  final hasTitle = contentUrl != null && contentUrl.isNotEmpty;
  final fallback = fromList ? _nothing : _push('/notifications');

  switch (type) {
    case 'system_comment_reply':
    case 'system_comment_like':
      return hasTitle
          ? _push('/detail', DetailArgs(contentUrl: contentUrl, provider: provider))
          : fallback;
    case 'system_ban':
      if (fromList) return _nothing;
      return (action: NotificationAction.signOut, location: '/login', extra: null);
    // A followed title grew. The detail page, opened on the new episode: it
    // offers "Watch episode N" first, and its list opens scrolled to it.
    case 'new_release':
    case 'library_update':
      if (!hasTitle) return fromList ? _nothing : _push('/releases');
      final episode = _int(data['episodeNumber']);
      return _push(
        '/detail',
        DetailArgs(
          contentUrl: contentUrl,
          provider: provider == null || provider.isEmpty ? null : provider,
          focusEpisode: episode != null && episode > 0 ? episode : null,
        ),
      );
    case 'releases_feed':
      return _push('/releases');
    case 'airing_reminder':
      if (!hasTitle) return _push('/anilist/calendar');
      final episode = _int(data['episodeNumber']);
      return _push(
        '/detail',
        DetailArgs(
          contentUrl: contentUrl,
          provider: provider == null || provider.isEmpty ? 'cat:anilist' : provider,
          focusEpisode: episode != null && episode > 0 ? episode : null,
        ),
      );
    case 'auto_download':
      return _push('/downloads');
    case 'friend_request':
      return _push('/friends?tab=requests');
    case 'friend_accept':
      final username = data['username']?.toString() ?? '';
      return _push(
        username.isEmpty
            ? '/friends?tab=friends'
            : '/u/${Uri.encodeComponent(username)}',
      );
    case 'streak_risk':
      return (action: NotificationAction.streakTab, location: '/main', extra: null);
    case 'system_unban':
    case 'admin_broadcast':
    case 'admin_direct':
    default:
      return fallback;
  }
}

/// Opens what a notification is about.
///
/// A release push addressed to another household profile switches to that
/// profile first — through its PIN, when it has one — because the title is in
/// that profile's follows, not this one's. Backing out of the PIN opens
/// nothing.
Future<void> openNotification(
  Map<String, dynamic> data, {
  bool fromList = false,
}) async {
  await _untilPastLaunch();
  if (!await _enterProfileOf(data)) return;
  final route = resolveNotificationRoute(data, fromList: fromList);
  final router = AppRouter.router;
  switch (route.action) {
    case NotificationAction.push:
      router.push(route.location, extra: route.extra);
    case NotificationAction.go:
      router.go(route.location, extra: route.extra);
    case NotificationAction.signOut:
      getIt<AuthBloc>().add(AuthSessionExpired());
      router.go(route.location);
    case NotificationAction.streakTab:
      // The tab lives on /main; switching it from a pushed page would change
      // a tab nobody can see.
      router.go('/main');
      getIt<NavController>().goToId(TabId.profile);
    case NotificationAction.none:
      break;
  }
}

/// Routes the launch replaces its whole stack from: a title pushed on top of
/// one is thrown away by the `go` that leaves it.
bool isLaunchRoute(String path) => path == '/splash' || path == '/profiles';

/// A tap that opened the app arrives while the splash is still up.
Future<void> _untilPastLaunch() async {
  final delegate = AppRouter.router.routerDelegate;
  bool waiting() {
    try {
      return isLaunchRoute(delegate.currentConfiguration.uri.path);
    } catch (_) {
      return false;
    }
  }

  if (!waiting()) return;
  final done = Completer<void>();
  void check() {
    if (!waiting() && !done.isCompleted) done.complete();
  }

  delegate.addListener(check);
  try {
    await done.future;
  } finally {
    delegate.removeListener(check);
  }
}

Future<bool> _enterProfileOf(Map<String, dynamic> data) async {
  final id = data['profileId']?.toString() ?? '';
  if (id.isEmpty || id == ProfileScope.remoteId) return true;
  if (!getIt.isRegistered<ProfileSession>()) return true;
  final session = getIt<ProfileSession>();
  var target = session.byId(id);
  if (target == null) {
    await session.refresh();
    target = session.byId(id);
  }
  // A profile this device does not know: open the title where we are rather
  // than nothing at all.
  if (target == null || session.active?.id == target.id) return true;
  if (target.hasPin) {
    final context = AppRouter.router.routerDelegate.navigatorKey.currentContext;
    if (context == null || !context.mounted) return true;
    final pin = await askProfilePin(context, session, target);
    if (pin == null) return false;
  }
  await session.activate(target);
  final after = AppRouter.router.routerDelegate.navigatorKey.currentContext;
  if (after != null && after.mounted) {
    try {
      after.read<HomeBloc>().add(HomeLoad(silent: true));
    } catch (_) {}
    try {
      after.read<ProviderBloc>().add(const ProviderLoad());
    } catch (_) {}
  }
  return true;
}
