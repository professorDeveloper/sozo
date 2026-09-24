import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/diagnostics/player_log.dart';

void main() {
  test('Jellyfin keys and tokens never reach the shareable log', () {
    final line = PlayerLog.redact(
      'loading url: http://nas:8096/Videos/x/master.m3u8?ApiKey=abc123&'
      'PlaySessionId=ps {Authorization: MediaBrowser Client="Sozo", '
      'Token="abc123"} http://old/Videos/x/stream?api_key=abc123',
    );
    expect(line, isNot(contains('abc123')));
    expect(line, contains('PlaySessionId=ps'));
    expect(line, contains('Token="<redacted>'));
  });
}
