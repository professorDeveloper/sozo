import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/watch_party/domain/entities/party_chat_message.dart';
import 'package:soplay/features/watch_party/domain/entities/party_playback.dart';
import 'package:soplay/features/watch_party/domain/invite_cooldowns.dart';
import 'package:soplay/features/watch_party/domain/party_clock.dart';
import 'package:soplay/features/watch_party/domain/party_wait_policy.dart';

void main() {
  group('PartyClock', () {
    test('has no offset before a usable sample', () {
      final clock = PartyClock();
      expect(clock.offsetMs, isNull);
      expect(clock.add(sentAt: 100, serverTime: 0, receivedAt: 50), isFalse);
      expect(clock.add(sentAt: 0, serverTime: 0, receivedAt: 9000), isFalse);
      expect(clock.offsetMs, isNull);
    });

    test('offset is server time minus the local midpoint of the trip', () {
      final clock = PartyClock();
      // Sent at 1000, answered at 1200 local: midpoint 1100. The server said
      // 5100, so the server clock runs 4000 ahead.
      clock.add(sentAt: 1000, serverTime: 5100, receivedAt: 1200);
      expect(clock.offsetMs, 4000);
      expect(clock.rttMs, 200);
    });

    test('the fastest round trip wins', () {
      final clock = PartyClock();
      clock.add(sentAt: 0, serverTime: 4400, receivedAt: 800);
      clock.add(sentAt: 2000, serverTime: 6020, receivedAt: 2040);
      clock.add(sentAt: 3000, serverTime: 7300, receivedAt: 3600);
      expect(clock.rttMs, 40);
      expect(clock.offsetMs, 4000);
    });

    test('keeps only the last window of samples', () {
      final clock = PartyClock(window: 2);
      clock.add(sentAt: 0, serverTime: 10, receivedAt: 20);
      clock.add(sentAt: 100, serverTime: 4250, receivedAt: 400);
      clock.add(sentAt: 500, serverTime: 4700, receivedAt: 900);
      expect(clock.rttMs, 300);
    });

    test('align takes the one-way trip out of a sync', () {
      final clock = PartyClock()
        ..add(sentAt: 1000, serverTime: 5100, receivedAt: 1200);
      final arrived = DateTime.fromMillisecondsSinceEpoch(10150);
      final meant = clock.align(serverTime: 14000, receivedAt: arrived);
      expect(meant.millisecondsSinceEpoch, 10000);

      final pb = PartyPlayback(
        positionSec: 60,
        isPlaying: true,
        rate: 1,
        receivedAt: meant,
      );
      // 150 ms of trip plus 850 ms since arrival: a full second ahead.
      expect(
        pb.expectedPositionAt(DateTime.fromMillisecondsSinceEpoch(11000)),
        closeTo(61, 1e-9),
      );
    });

    test('align falls back to the receipt time when it cannot be trusted', () {
      final arrived = DateTime.fromMillisecondsSinceEpoch(10000);
      expect(
        PartyClock().align(serverTime: 9000, receivedAt: arrived),
        arrived,
      );
      final clock = PartyClock()
        ..add(sentAt: 0, serverTime: 100, receivedAt: 200);
      expect(clock.align(serverTime: null, receivedAt: arrived), arrived);
      // In the future of the receipt: noise, not latency.
      expect(clock.align(serverTime: 10500, receivedAt: arrived), arrived);
      // Ten seconds back is a stale offset, not a slow network.
      expect(clock.align(serverTime: 0, receivedAt: arrived), arrived);
    });
  });

  group('PartyWaitPolicy', () {
    final t0 = DateTime(2026, 1, 1, 12);
    DateTime at(int sec) => t0.add(Duration(seconds: sec));

    PartyWaitAction tick(
      PartyWaitPolicy p, {
      required int now,
      List<int> buffering = const [],
      bool playing = true,
      bool enabled = true,
      bool isHost = true,
    }) => p.tick(
      enabled: enabled,
      isHost: isHost,
      localPlaying: playing,
      bufferingSince: buffering.map(at),
      now: at(now),
    );

    test('a short stall does not pause the room', () {
      final p = PartyWaitPolicy();
      expect(tick(p, now: 2, buffering: [0]), PartyWaitAction.none);
    });

    test('pauses after three seconds and resumes when the guest is back', () {
      final p = PartyWaitPolicy();
      expect(tick(p, now: 3, buffering: [0]), PartyWaitAction.pause);
      expect(p.holding, isTrue);
      expect(
        tick(p, now: 5, buffering: [0], playing: false),
        PartyWaitAction.none,
      );
      expect(tick(p, now: 7, playing: false), PartyWaitAction.resume);
      expect(p.holding, isFalse);
    });

    test('gives up after the cap and does not hold for the same stall', () {
      final p = PartyWaitPolicy();
      expect(tick(p, now: 4, buffering: [0]), PartyWaitAction.pause);
      expect(
        tick(p, now: 19, buffering: [0], playing: false),
        PartyWaitAction.resume,
      );
      expect(tick(p, now: 25, buffering: [0]), PartyWaitAction.none);
      expect(tick(p, now: 33, buffering: [0, 30]), PartyWaitAction.pause);
    });

    test('a host who presses play during the hold ends it', () {
      final p = PartyWaitPolicy();
      tick(p, now: 4, buffering: [0]);
      expect(tick(p, now: 6, buffering: [0]), PartyWaitAction.none);
      expect(p.holding, isFalse);
    });

    test('never acts for a guest, or when the setting is off', () {
      expect(
        tick(PartyWaitPolicy(), now: 9, buffering: [0], isHost: false),
        PartyWaitAction.none,
      );
      expect(
        tick(PartyWaitPolicy(), now: 9, buffering: [0], enabled: false),
        PartyWaitAction.none,
      );
    });

    test('turning the setting off mid-hold lets the room go', () {
      final p = PartyWaitPolicy();
      tick(p, now: 4, buffering: [0]);
      expect(
        tick(p, now: 5, buffering: [0], playing: false, enabled: false),
        PartyWaitAction.resume,
      );
    });

    test('a paused host is never paused again', () {
      expect(
        tick(PartyWaitPolicy(), now: 9, buffering: [0], playing: false),
        PartyWaitAction.none,
      );
    });
  });

  group('chat history', () {
    test('parses chat and system lines and drops unknown kinds', () {
      final list = PartyChatMessage.listFrom([
        {
          'type': 'chat',
          'user': {'id': 'a', 'username': 'ann'},
          'text': 'hi',
          'ts': 1,
        },
        {
          'type': 'system',
          'kind': 'host',
          'user': {'id': 'b', 'username': 'bob'},
          'ts': 2,
        },
        {
          'type': 'system',
          'kind': 'dance',
          'user': {'id': 'c'},
          'ts': 3,
        },
        'garbage',
      ]);
      expect(list, hasLength(2));
      expect(list[0].isSystem, isFalse);
      expect(list[0].text, 'hi');
      expect(list[1].system, PartySystemKind.host);
      expect(list[1].username, 'bob');
    });

    test('a line from an older server without a type is chat', () {
      final m = PartyChatMessage.tryParse({
        'user': {'id': 'a'},
        'text': 'x',
        'ts': 1,
      });
      expect(m?.isSystem, isFalse);
    });
  });

  group('InviteCooldowns', () {
    test('counts down from the server seconds and expires', () {
      var now = DateTime(2026, 1, 1);
      final c = InviteCooldowns(clock: () => now);
      c.applyServer([
        {'userId': 'a', 'retryAfterSec': 90},
        {'userId': 'b', 'retryAfterSec': 'nope'},
      ]);
      expect(c.coolingDown('a'), isTrue);
      expect(c.coolingDown('b'), isFalse);
      expect(InviteCooldowns.format(c.remaining('a')), '1:30');
      now = now.add(const Duration(seconds: 89, milliseconds: 500));
      expect(InviteCooldowns.format(c.remaining('a')), '0:01');
      now = now.add(const Duration(seconds: 1));
      expect(c.coolingDown('a'), isFalse);
      expect(c.any, isFalse);
    });
  });
}
