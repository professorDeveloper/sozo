import 'package:soplay/features/detail/data/aniskip_service.dart';

/// Which "Skip opening" offer belongs on screen at a given moment.
///
/// Four rules decided this, and all four lived inside a loop on a widget State
/// where none of them could be exercised:
///
///   * the position has to be inside the interval;
///   * an interval already taken never comes back;
///   * an offer expires ten seconds in — watching past it IS declining it, and
///     a Skip button that reappears for the whole opening is worse than none;
///   * a two-second interval is a bad crowd-sourced submission, not an opening.
///
/// The last two are the ones that make this feel finished rather than
/// annoying, and they are exactly the kind of rule that silently inverts.
///
/// Pure: intervals and a position in, an offer out. No Flutter, no I/O.
class SkipOffers {
  SkipOffers();

  /// How long an offer stays on screen after its interval begins.
  ///
  /// Watching ten seconds into an opening is a decision not to skip it.
  static const Duration offerWindow = Duration(seconds: 10);

  List<SkipInterval> _intervals = const [];

  /// Interval types already skipped this episode, by `op` / `ed`.
  final Set<String> _taken = <String>{};

  List<SkipInterval> get intervals => _intervals;

  /// Replaces the intervals for a new episode and forgets what was taken.
  ///
  /// Unusable intervals are dropped here rather than skipped over later, so
  /// nothing downstream has to remember the rule.
  void load(List<SkipInterval> intervals) {
    _intervals = [for (final i in intervals) if (i.isUsable) i];
    _taken.clear();
  }

  /// Back to nothing — a new episode with no skip data.
  void clear() {
    _intervals = const [];
    _taken.clear();
  }

  /// Records that an interval was skipped, so it is never offered again.
  void take(SkipInterval interval) => _taken.add(interval.type);

  bool wasTaken(SkipInterval interval) => _taken.contains(interval.type);

  /// The offer for [position], or null when there should not be one.
  SkipInterval? offerAt(Duration position) {
    for (final s in _intervals) {
      if (!s.contains(position)) continue;
      if (_taken.contains(s.type)) return null;
      // Past the window: the viewer chose to watch it.
      if (position - s.start > offerWindow) return null;
      return s;
    }
    return null;
  }

  /// Where playback should land after taking [interval].
  ///
  /// The end of the interval, never a fixed jump: openings differ in length and
  /// a hard-coded ninety seconds either lands mid-opening or into the episode.
  Duration targetFor(SkipInterval interval) => interval.end;
}
