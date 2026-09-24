import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/notifications/data/notification_payload.dart';

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
}
