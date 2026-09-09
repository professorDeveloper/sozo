import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/detail/domain/playback/party_rules.dart';

void main() {
  group('the feedback-loop guard', () {
    test('a guest applying the host\'s pause is not refused', () {
      // Without the applyingRemote clause here, a guest would be told "only the
      // host can control this" by its OWN sync code, and its player would
      // never follow the host at all.
      expect(
        PartyRules.blocksLocalControl(
          inParty: true,
          canControl: false,
          applyingRemote: true,
        ),
        isFalse,
      );
    });

    test('but the same guest is refused when the finger is theirs', () {
      expect(
        PartyRules.blocksLocalControl(
          inParty: true,
          canControl: false,
          applyingRemote: false,
        ),
        isTrue,
      );
    });

    test('applying a remote sync never echoes it back', () {
      // Applying a remote pause calls the same local pause path a finger does.
      // Emitting from there is the loop: peer applies, peer emits, forever.
      expect(
        PartyRules.emitsControl(
          inParty: true,
          canControl: true,
          applyingRemote: true,
        ),
        isFalse,
      );
    });
  });

  group('refusing and emitting are not opposites', () {
    test('outside a party nothing is refused and nothing is sent', () {
      // Written as `!blocksLocalControl`, emit would fire into an empty room on
      // every ordinary tap of play.
      const args = (inParty: false, canControl: false, applyingRemote: false);
      expect(
        PartyRules.blocksLocalControl(
          inParty: args.inParty,
          canControl: args.canControl,
          applyingRemote: args.applyingRemote,
        ),
        isFalse,
      );
      expect(
        PartyRules.emitsControl(
          inParty: args.inParty,
          canControl: args.canControl,
          applyingRemote: args.applyingRemote,
        ),
        isFalse,
      );
    });

    test('a host both acts and broadcasts', () {
      expect(
        PartyRules.blocksLocalControl(
          inParty: true,
          canControl: true,
          applyingRemote: false,
        ),
        isFalse,
      );
      expect(
        PartyRules.emitsControl(
          inParty: true,
          canControl: true,
          applyingRemote: false,
        ),
        isTrue,
      );
    });
  });

  group('episode navigation is stricter than playback', () {
    test('a guest WITH playback control still cannot change episode', () {
      // It changes what is being watched, not how it is playing.
      expect(
        PartyRules.blocksLocalControl(
          inParty: true,
          canControl: true,
          applyingRemote: false,
        ),
        isFalse,
        reason: 'may pause',
      );
      expect(
        PartyRules.blocksEpisodeNav(
          inParty: true,
          isHost: false,
          applyingRemote: false,
        ),
        isTrue,
        reason: 'may not change episode',
      );
    });

    test('the host may', () {
      expect(
        PartyRules.blocksEpisodeNav(
          inParty: true,
          isHost: true,
          applyingRemote: false,
        ),
        isFalse,
      );
    });

    test('and a remote content change is not blocked as if it were local', () {
      expect(
        PartyRules.blocksEpisodeNav(
          inParty: true,
          isHost: false,
          applyingRemote: true,
        ),
        isFalse,
      );
    });
  });

  group('who talks and who listens', () {
    test('only the host announces, and never on a live channel', () {
      // A channel has no seekable position to agree on, so the number would
      // only be one every guest then failed to seek to.
      expect(
        PartyRules.sendsHeartbeat(inParty: true, isHost: true, isLive: false),
        isTrue,
      );
      expect(
        PartyRules.sendsHeartbeat(inParty: true, isHost: true, isLive: true),
        isFalse,
      );
      expect(
        PartyRules.sendsHeartbeat(inParty: true, isHost: false, isLive: false),
        isFalse,
      );
    });

    test('only a guest follows', () {
      expect(PartyRules.followsRemote(inParty: true, isHost: false), isTrue);
      expect(PartyRules.followsRemote(inParty: true, isHost: true), isFalse);
      expect(PartyRules.followsRemote(inParty: false, isHost: false), isFalse);
    });

    test('the guest checks itself more often than the host speaks', () {
      // It re-applies the LAST sync against a moving clock, so it corrects
      // between announcements instead of waiting for the next one.
      expect(
        PartyRules.driftPeriod,
        lessThan(PartyRules.heartbeatPeriod),
      );
    });
  });

  group('drift', () {
    test('ordinary jitter does not cause a seek', () {
      // A seek is visible. A party that twitches every two seconds is worse
      // than one a second out of step.
      expect(PartyRules.needsSeek(100.0, 100.9), isFalse);
      expect(PartyRules.needsSeek(100.0, 101.4), isFalse);
    });

    test('a real gap does, in both directions', () {
      expect(PartyRules.needsSeek(100.0, 103.0), isTrue);
      expect(PartyRules.needsSeek(103.0, 100.0), isTrue);
    });

    test('the boundary is not a seek', () {
      expect(PartyRules.needsSeek(100.0, 101.5), isFalse);
    });

    test('a rate that came through JSON is still the same rate', () {
      expect(PartyRules.needsRateChange(1.0, 1.0000001), isFalse);
      expect(PartyRules.needsRateChange(1.0, 2.0), isTrue);
    });
  });

  group('transport', () {
    test('agreement is left alone', () {
      // The drift timer re-applies the last sync every 2s. Calling play() or
      // pause() unconditionally each tick thrashes the native player and reads
      // as a bad stream rather than as the party code.
      expect(
        PartyRules.transportFor(remoteIsPlaying: true, localIsPlaying: true),
        PartyTransport.leave,
      );
      expect(
        PartyRules.transportFor(remoteIsPlaying: false, localIsPlaying: false),
        PartyTransport.leave,
      );
    });

    test('a mismatch is corrected the way the host has it', () {
      expect(
        PartyRules.transportFor(remoteIsPlaying: true, localIsPlaying: false),
        PartyTransport.play,
      );
      expect(
        PartyRules.transportFor(remoteIsPlaying: false, localIsPlaying: true),
        PartyTransport.pause,
      );
    });
  });

  group('when the player repaints', () {
    test('not for the playback syncs, which fire several times a second', () {
      expect(
        PartyRules.needsRepaint(
          wasBound: true,
          isBound: true,
          hadControl: true,
          hasControl: true,
        ),
        isFalse,
      );
    });

    test('for joining and leaving', () {
      expect(
        PartyRules.needsRepaint(
          wasBound: false,
          isBound: true,
          hadControl: false,
          hasControl: false,
        ),
        isTrue,
      );
    });

    test('and for host migration, which is control changing hands', () {
      expect(
        PartyRules.needsRepaint(
          wasBound: true,
          isBound: true,
          hadControl: false,
          hasControl: true,
        ),
        isTrue,
      );
    });
  });

  test('the domain layer stays free of Flutter', () {
    final source = File(
      'lib/features/detail/domain/playback/party_rules.dart',
    ).readAsStringSync();
    expect(source.contains('package:flutter/'), isFalse);
    expect(source.contains('get_it'), isFalse);
  });
}
