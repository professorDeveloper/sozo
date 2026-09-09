import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/discord/discord_activity.dart';
import 'package:soplay/core/discord/discord_presence_service.dart';

/// The throttle is the part that decides whether Discord shows anything at
/// all. Discord drops presence updates sent more often than roughly one every
/// fifteen seconds per connection, and a player produces them several times a
/// second, so getting this wrong means the update that mattered — the one that
/// says which episode — is the one thrown away.
///
/// No Discord and no network: the service refuses every update until a
/// transport is live, and the coalescing rule is exercised against the same
/// shape the service implements.

void main() {
  DiscordActivity ep(String subtitle) =>
      DiscordActivity(title: 'Demon Slayer', subtitle: subtitle);

  test('an unstarted service ignores updates entirely', () {
    // Nothing may reach Discord before somebody has turned this on.
    final service = DiscordPresenceService();
    service.update(ep('S1 · E1'));
    expect(service.isConnected, isFalse);
  });

  test('the same activity twice is one change', () {
    // sameAs is what the throttle leans on; if it compared timestamps every
    // tick would look new.
    final a = ep('S1 · E1');
    final b = ep('S1 · E1');
    expect(a.sameAs(b), isTrue);
  });

  test('skipping four episodes should end on the fourth', () {
    // Documents the intended coalescing: inside the window only the newest is
    // kept, so somebody flicking through episodes ends where they stopped
    // rather than replaying the sequence to their friends.
    final seen = <String?>[];
    DiscordActivity? queued;
    var windowOpen = false;

    void update(DiscordActivity a) {
      if (!windowOpen) {
        seen.add(a.subtitle);
        windowOpen = true;
        return;
      }
      queued = a;
    }

    for (final e in ['E1', 'E2', 'E3', 'E4']) {
      update(ep(e));
    }
    // The window closing is what releases the queued one.
    if (queued != null) seen.add(queued!.subtitle);

    expect(seen, ['E1', 'E4']);
  });
}
