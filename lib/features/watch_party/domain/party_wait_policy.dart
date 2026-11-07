/// "Wait for everyone": the host's player holds for a guest who is buffering.
///
/// A short stall is not worth a room-wide pause, so a guest has to buffer for
/// [threshold] first. The hold is also capped at [maxHold]: a guest on a link
/// that never recovers must not freeze the room for good.
///
/// After giving up on a guest it ignores that same stall, otherwise the room
/// would pause again on the next tick and every [maxHold] after that.
enum PartyWaitAction { none, pause, resume }

class PartyWaitPolicy {
  PartyWaitPolicy({
    this.threshold = const Duration(seconds: 3),
    this.maxHold = const Duration(seconds: 15),
  });

  final Duration threshold;
  final Duration maxHold;

  DateTime? _heldSince;
  DateTime? _ignoreBefore;

  bool get holding => _heldSince != null;

  /// [bufferingSince] is when each other member was first seen buffering.
  PartyWaitAction tick({
    required bool enabled,
    required bool isHost,
    required bool localPlaying,
    required Iterable<DateTime> bufferingSince,
    required DateTime now,
  }) {
    final held = _heldSince;
    if (!enabled || !isHost) {
      _heldSince = null;
      return held != null && !localPlaying
          ? PartyWaitAction.resume
          : PartyWaitAction.none;
    }

    if (held != null) {
      if (localPlaying) {
        // Someone pressed play while we held; the hold is over.
        _heldSince = null;
        return PartyWaitAction.none;
      }
      final stillWaiting = bufferingSince.isNotEmpty;
      if (!stillWaiting || now.difference(held) >= maxHold) {
        _heldSince = null;
        if (stillWaiting) _ignoreBefore = now;
        return PartyWaitAction.resume;
      }
      return PartyWaitAction.none;
    }

    if (!localPlaying) return PartyWaitAction.none;
    final ignore = _ignoreBefore;
    final stalled = bufferingSince.any(
      (t) =>
          (ignore == null || t.isAfter(ignore)) &&
          now.difference(t) >= threshold,
    );
    if (!stalled) return PartyWaitAction.none;
    _heldSince = now;
    return PartyWaitAction.pause;
  }

  /// The host took over playback themselves; the hold is theirs now.
  void release() => _heldSince = null;
}
