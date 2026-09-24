import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/notifications/data/notification_payload.dart';
import 'package:soplay/features/notifications/data/release_notifier.dart';

void main() {
  test('round-trips, keeping numbers as numbers', () {
    final data = {
      'type': 'new_release',
      'contentUrl': 'https://a/b?c=d&e=f',
      'episodeNumber': 12,
    };
    final back = decodeNotificationPayload(encodeNotificationPayload(data));
    expect(back, data);
  });

  test('what scheduleAt writes, a tap can read', () {
    // The bug: reminders were JSON-encoded and read back as k=v&k=v, which
    // decoded to nothing, so a tapped reminder went nowhere.
    final payload = encodeNotificationPayload({
      'type': 'airing_reminder',
      'contentUrl': 'https://anilist.co/anime/1',
    });
    expect(decodeNotificationPayload(payload)?['type'], 'airing_reminder');
  });

  test('a notification from the previous build still decodes', () {
    const legacy = 'type=library_update&contentUrl=https%3A%2F%2Fx%2Fy%3Fa%3Db';
    expect(decodeNotificationPayload(legacy), {
      'type': 'library_update',
      'contentUrl': 'https://x/y?a=b',
    });
  });

  test('nothing in, nothing out', () {
    expect(encodeNotificationPayload(const {}), isNull);
    expect(encodeNotificationPayload(null), isNull);
    expect(decodeNotificationPayload(''), isNull);
    expect(decodeNotificationPayload('garbage'), isNull);
  });

  test('a release push drawn by the app keeps the profile it was sent to', () {
    // Pushes are data-only, so every tap comes back through this payload;
    // without the profile the tap opened the title in whoever was active.
    final alert = ReleaseAlert.fromData({
      'type': 'new_release',
      'provider': 'hdrezka',
      'contentUrl': 'https://x/y',
      'episodeNumber': '7',
      'count': '2',
      'profileId': 'p2',
    })!;
    final tap = decodeNotificationPayload(
      encodeNotificationPayload(alert.toPayload()),
    )!;
    expect(tap['profileId'], 'p2');
    expect(tap['episodeNumber'], 6);

    final own = ReleaseAlert.fromData({'contentUrl': 'u', 'episodeNumber': 1})!;
    expect(own.toPayload().containsKey('profileId'), isFalse);
  });

  test("a push's own wording wins over the app's running number", () {
    const labels = NotificationLabels();
    final server = ReleaseAlert.fromData({
      'contentUrl': 'https://www.themoviedb.org/tv/9',
      'episodeNumber': '17',
      'episodeLabel': 'S2 E5',
      'body': 'Season 2, episode 5 is out',
    })!;
    expect(labels.bodyFor(server), 'Season 2, episode 5 is out');
    final local = ReleaseAlert.fromData({
      'contentUrl': 'https://a/b',
      'episodeNumber': '3',
    })!;
    expect(local.body, isNull);
    expect(labels.bodyFor(local), isNotEmpty);
  });
}
