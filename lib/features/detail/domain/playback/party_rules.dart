/// Who may drive playback in a watch party, and what a drift tick should do.
///
/// Nine rules, all of them one-line boolean expressions, and all of them
/// repeated at the call sites that needed them inside a 391-line extension on a
/// widget State. Each is the kind that inverts silently: get one wrong and the
/// symptom is not a crash but a party that drifts apart, or a guest whose
/// player refuses to follow the host, or a host whose every heartbeat is echoed
/// back at them.
///
/// ## The one that is easiest to lose
///
/// `applyingRemote` appears in three separate gates, and it is not a detail —
/// it is what stops the feedback loop. Applying a remote pause calls the same
/// local pause path that a finger does. Without the flag that path emits a
/// `party:control`, which the peer applies, which emits another. And in
/// [blocksLocalControl] specifically it does the opposite job: without it, a
/// guest applying the host's pause would be told "only the host can control
/// this" and refuse — so the guest's player would never follow at all.
///
/// Pure: booleans and numbers in, decisions out. No Flutter, no getIt, no I/O,
/// no clock.
library;

/// What a party sync should do to the local player's transport.
enum PartyTransport { play, pause, leave }

abstract final class PartyRules {
  /// How far the local position may sit from the party's before it is pulled
  /// back.
  ///
  /// Wide enough that ordinary jitter — a decode hiccup, a rebuffer, the round
  /// trip itself — does not cause a seek, because a seek is visible and a party
  /// that twitches every two seconds is worse than one a second out of step.
  static const Duration driftTolerance = Duration(milliseconds: 1500);

  /// Rates within this of each other are the same rate.
  ///
  /// `1.0` arrives off the wire as a double that has been through JSON, and an
  /// exact `!=` would call `setPlaybackSpeed` on every single tick.
  static const double rateTolerance = 0.01;

  /// How often the host announces where it is.
  static const Duration heartbeatPeriod = Duration(seconds: 3);

  /// How often a guest checks itself against the last announcement.
  ///
  /// Faster than the heartbeat on purpose: the guest re-applies the LAST sync
  /// against a moving clock, so it corrects between announcements rather than
  /// waiting for the next one.
  static const Duration driftPeriod = Duration(seconds: 2);

  /// Whether a local play/pause/seek/rate must be refused and explained.
  ///
  /// Never while applying a remote sync — see the note on this library. That
  /// clause is what lets a guest's player follow the host at all.
  static bool blocksLocalControl({
    required bool inParty,
    required bool canControl,
    required bool applyingRemote,
  }) =>
      inParty && !canControl && !applyingRemote;

  /// Whether changing episode must be refused.
  ///
  /// Host-only, and deliberately a stricter test than [blocksLocalControl]:
  /// episode navigation changes WHAT is being watched, not just how it is
  /// playing, so a guest with playback control still may not do it.
  static bool blocksEpisodeNav({
    required bool inParty,
    required bool isHost,
    required bool applyingRemote,
  }) =>
      inParty && !isHost && !applyingRemote;

  /// Whether a local action should be broadcast.
  ///
  /// Not the negation of [blocksLocalControl]: outside a party both are false —
  /// nothing is refused and nothing is sent. Writing this as `!blocksLocal`
  /// would emit into an empty room on every ordinary tap.
  static bool emitsControl({
    required bool inParty,
    required bool canControl,
    required bool applyingRemote,
  }) =>
      inParty && canControl && !applyingRemote;

  /// Whether this device should be announcing its position.
  ///
  /// Live excluded: a channel has no seekable position to agree on, so a
  /// heartbeat would only publish a number every guest would then fail to seek
  /// to.
  static bool sendsHeartbeat({
    required bool inParty,
    required bool isHost,
    required bool isLive,
  }) =>
      inParty && isHost && !isLive;

  /// Whether this device should be following someone else's playback.
  static bool followsRemote({
    required bool inParty,
    required bool isHost,
  }) =>
      inParty && !isHost;

  /// Whether the local position is far enough out to be worth a seek.
  static bool needsSeek(double actualSec, double expectedSec) =>
      (actualSec - expectedSec).abs() >
      driftTolerance.inMilliseconds / 1000.0;

  /// Whether the rate differs enough to be worth setting.
  static bool needsRateChange(double current, double target) =>
      (current - target).abs() > rateTolerance;

  /// What to do about play/pause, or [PartyTransport.leave] when they already
  /// agree.
  ///
  /// Leaving it alone matters more than it looks. The drift timer re-applies
  /// the last sync every two seconds; calling `play()` or `pause()`
  /// unconditionally on each tick thrashes the native player and shows up as
  /// micro-stutter and a jumpy play-pause feel — which reads as a bad stream
  /// rather than as the party code.
  static PartyTransport transportFor({
    required bool remoteIsPlaying,
    required bool localIsPlaying,
  }) {
    if (remoteIsPlaying == localIsPlaying) return PartyTransport.leave;
    return remoteIsPlaying ? PartyTransport.play : PartyTransport.pause;
  }

  /// Whether a party-state change is one the player must repaint for.
  ///
  /// The same notifier fires for every playback sync — several times a second
  /// in a busy room — and rebuilding the player on each would be a frame budget
  /// spent on nothing. Only two transitions actually change what is on screen:
  /// joining or leaving, and gaining or losing control (which is what host
  /// migration looks like from here).
  static bool needsRepaint({
    required bool wasBound,
    required bool isBound,
    required bool hadControl,
    required bool hasControl,
  }) =>
      wasBound != isBound || hadControl != hasControl;
}
