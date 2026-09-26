import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/detail/domain/entities/detail_args.dart';
import 'package:soplay/features/notifications/presentation/notification_routing.dart';

void main() {
  test('a new release opens the title on the new episode', () {
    final route = resolveNotificationRoute({
      'type': 'new_release',
      'provider': 'cs:x',
      'contentUrl': 'https://site/show',
      'episodeNumber': '12',
      'mode': 'video',
    });
    expect(route.action, NotificationAction.push);
    expect(route.location, '/detail');
    final args = route.extra as DetailArgs;
    expect(args.contentUrl, 'https://site/show');
    expect(args.provider, 'cs:x');
    expect(args.focusEpisode, 12);
  });

  test('library_update from older builds lands the same way', () {
    final route = resolveNotificationRoute({
      'type': 'library_update',
      'contentUrl': 'u',
      'provider': 'p',
    });
    expect(route.location, '/detail');
    expect((route.extra as DetailArgs).focusEpisode, isNull);
  });

  test('a release without a title opens the feed', () {
    expect(resolveNotificationRoute({'type': 'new_release'}).location, '/releases');
    expect(
      resolveNotificationRoute({'type': 'new_release'}, fromList: true).action,
      NotificationAction.none,
    );
    expect(resolveNotificationRoute({'type': 'releases_feed'}).location, '/releases');
  });

  test('an airing reminder opens the AniList title, else the calendar', () {
    final route = resolveNotificationRoute({
      'type': 'airing_reminder',
      'contentUrl': 'https://anilist.co/anime/5',
      'episodeNumber': 3,
    });
    final args = route.extra as DetailArgs;
    expect(args.provider, 'cat:anilist');
    expect(args.focusEpisode, 3);
    expect(
      resolveNotificationRoute({'type': 'airing_reminder'}).location,
      '/anilist/calendar',
    );
  });

  test('watch-party invites still win over the type', () {
    expect(
      resolveNotificationRoute({'type': 'system_other', 'roomCode': 'AB'}).location,
      '/watch-party?code=AB',
    );
  });

  test('a cold-start tap waits out the routes the launch replaces', () {
    expect(isLaunchRoute('/splash'), isTrue);
    expect(isLaunchRoute('/profiles'), isTrue);
    expect(isLaunchRoute('/main'), isFalse);
    expect(isLaunchRoute('/detail'), isFalse);
  });

  test('an answer from support opens its conversation', () {
    final route = resolveNotificationRoute({
      'type': 'support_reply',
      'ticketId': '6ab7895d342db7ef3ac3bbe4',
    });
    expect(route.action, NotificationAction.push);
    expect(route.location, '/support/6ab7895d342db7ef3ac3bbe4');
    expect(
      resolveNotificationRoute({'type': 'support_reply'}).location,
      '/support',
    );
  });
}
