/// When a viewing counts as watched, and how much of it counts as time spent.
///
/// Three rules, each of which had a comment explaining it and nothing
/// enforcing it, spread between a 429-line history extension and a branch
/// inside `_onMajorChange`:
///
///   * a title is "watched" at 85% of its duration, not at the end;
///   * a tracker hears about an episode ONCE, however many times that 85% mark
///     is crossed;
///   * time spent is banked from a wall clock, never from stream position.
///
/// Every one of them is the kind of rule that breaks quietly — a double report
/// to AniList, an hour added to a total by a scrub, a finished episode that
/// never registered — and none of them could be exercised without a live
/// controller and a widget tree.
///
/// Pure: numbers in, answers out. No Flutter, no I/O, no clock of its own.
library;

/// The rules, and the once-per-episode ledger that goes with them.
class WatchProgress {
  WatchProgress();

  /// Fraction of the duration at which a title counts as watched.
  ///
  /// Not the very end: a viewer who stops during the credits has watched the
  /// episode, and a tracker that only fires at 100% never fires for them. Not
  /// much lower either — an abandoned episode should not be marked finished.
  static const double watchedThreshold = 0.85;

  /// Episodes already reported this session, so a tracker hears once.
  final Set<int> _reported = <int>{};

  /// Wall-clock seconds already credited, so a tick only ever banks the
  /// stretch since the last one.
  int _bankedSeconds = 0;

  int get bankedSeconds => _bankedSeconds;

  /// Whether [position] of [duration] means the title has been watched.
  ///
  /// False for a zero or unknown duration — a live stream reports one, and
  /// "85% of nothing" would mark a channel watched the instant it opened.
  static bool isWatched(Duration position, Duration duration) {
    final total = duration.inMilliseconds;
    if (total <= 0) return false;
    return position.inMilliseconds >= total * watchedThreshold;
  }

  /// The episode number a tracker should be told about, or null when it should
  /// not be told anything.
  ///
  /// A movie is episode 1 as far as a tracker is concerned. Null covers the
  /// cases that must not report: an episode already reported, an index outside
  /// the loaded window, and an episode the provider numbered 0 or less — which
  /// several anime sources do for specials, and which would otherwise write
  /// "episode 0 watched" onto somebody's list.
  int? episodeToReport({
    required bool isSerial,
    required int? episodeNumber,
  }) {
    final number = isSerial ? episodeNumber : 1;
    if (number == null || number <= 0) return null;
    if (!_reported.add(number)) return null;
    return number;
  }

  /// Whether [number] has already been reported this session.
  bool hasReported(int number) => _reported.contains(number);

  /// Seconds to credit given a wall clock reading [elapsed] in total.
  ///
  /// Wall clock rather than stream position, deliberately: a seek is not
  /// watching, and position deltas would count a scrub to the end as an hour.
  /// Returns 0 when the clock has not moved, which is what a tick during a
  /// pause looks like.
  int bank(Duration elapsed) {
    final total = elapsed.inSeconds;
    final delta = total - _bankedSeconds;
    if (delta <= 0) return 0;
    _bankedSeconds = total;
    return delta;
  }

  /// Starts over for a new episode: nothing banked, nothing reported.
  ///
  /// Both halves matter. Carrying the banked seconds would credit the next
  /// episode with the previous one's time; carrying the reported set would
  /// stop episode 2 ever reaching a tracker when it shares a number with a
  /// special from episode 1's season.
  void reset() {
    _bankedSeconds = 0;
    _reported.clear();
  }
}
