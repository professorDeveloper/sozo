/// Decides when an episode has ended, once.
///
/// The player used to trust only "two seconds left". Streams whose playlist
/// overstates the duration never get there: the engine reports completion, or
/// the playhead freezes a few seconds short and buffers forever, and the
/// episode neither advanced nor counted as finished.
library;

class EndOfStreamDetector {
  /// Inside this much of the end, the last moments are being played.
  static const Duration nearEnd = Duration(seconds: 2);

  /// Inside this much of the end, a playhead that stops moving is the end.
  static const Duration stallZone = Duration(seconds: 5);

  /// How long the playhead must stay put in [stallZone].
  static const Duration stallFor = Duration(seconds: 3);

  Duration? _lastPosition;
  Duration? _movedAt;
  bool _fired = false;

  bool get fired => _fired;

  /// True exactly once per ending. Moving back out of the last stretch (a seek
  /// back) re-arms it.
  bool observe({
    required Duration position,
    required Duration duration,
    required bool isCompleted,
    required bool isPlaying,
    required bool isBuffering,
    required Duration now,
  }) {
    if (duration <= Duration.zero) return false;
    final remaining = duration - position;

    if (_lastPosition != position) {
      _lastPosition = position;
      _movedAt = now;
    }

    if (remaining > stallZone + const Duration(seconds: 1) && !isCompleted) {
      _fired = false;
      return false;
    }
    if (_fired) return false;

    final movedAt = _movedAt ?? now;
    final stalled =
        remaining <= stallZone &&
        (isPlaying || isBuffering) &&
        now - movedAt >= stallFor;
    if (isCompleted || remaining <= nearEnd || stalled) {
      _fired = true;
      return true;
    }
    return false;
  }

  void reset() {
    _lastPosition = null;
    _movedAt = null;
    _fired = false;
  }
}
