import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/navigation/app_tab.dart';
import 'package:soplay/core/navigation/nav_controller.dart';
import 'package:soplay/core/router/app_router.dart';
import 'package:soplay/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:soplay/features/auth/presentation/bloc/auth_event.dart';
import 'package:soplay/features/detail/domain/entities/detail_args.dart';

/// Where a notification takes the user — shared by a tapped push and a tapped
/// row in the notifications list, which used to disagree: the list only marked
/// the row read, so the same "someone replied to your comment" that opened the
/// title from the lock screen went nowhere from inside the app.
///
/// [fromList] is set for the in-app list, where "open the notifications page"
/// — the fallback for a push — would mean staying put, so it does nothing.
void openNotification(Map<String, dynamic> data, {bool fromList = false}) {
  final router = AppRouter.router;

  // Watch-party invites arrive as type:'system_other' + data.roomCode, so a
  // type-based branch would never fire — key off roomCode before the switch.
  final roomCode = data['roomCode'];
  if (roomCode is String && roomCode.isNotEmpty) {
    router.push('/watch-party?code=${Uri.encodeComponent(roomCode)}');
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
      } else if (!fromList) {
        router.push('/notifications');
      }
    case 'system_ban':
      if (fromList) return;
      getIt<AuthBloc>().add(AuthSessionExpired());
      router.go('/login');
    // A followed title grew. The chapter list, not the detail page: the new
    // chapters are the whole reason the notification exists, and the detail
    // page is one more tap away from them.
    case 'library_update':
      if (contentUrl != null && contentUrl.isNotEmpty) {
        router.push(
          '/detail',
          extra: DetailArgs(contentUrl: contentUrl, provider: provider),
        );
      } else if (!fromList) {
        router.push('/following');
      }
    case 'auto_download':
      router.push('/downloads');
    case 'friend_request':
      router.push('/friends?tab=requests');
    case 'friend_accept':
      final username = data['username']?.toString() ?? '';
      router.push(
        username.isEmpty
            ? '/friends?tab=friends'
            : '/u/${Uri.encodeComponent(username)}',
      );
    case 'streak_risk':
      // The tab lives on /main; switching it from a pushed page would change
      // a tab nobody can see.
      router.go('/main');
      getIt<NavController>().goToId(TabId.profile);
    case 'system_unban':
    case 'admin_broadcast':
    case 'admin_direct':
    default:
      if (!fromList) router.push('/notifications');
  }
}
