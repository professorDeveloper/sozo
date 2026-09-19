/// What an automatic title lookup found — and whether it got to look at all.
///
/// Both trackers searched a catalogue for a local title and returned `null` for
/// two situations that could not be less alike:
///
///   * the catalogue answered, and nothing in it matched — a real answer, and
///     one worth remembering so that every subsequent episode of the same show
///     does not pay for the same hopeless search;
///   * the request never completed — offline, rate-limited, a 502 — so nothing
///     was learned at all.
///
/// Because both came back as `null`, the caller recorded both in its
/// `_autoMatchFailed` set, which is checked before any lookup is attempted.
/// One failed request while watching on a train therefore stopped that title
/// ever auto-linking again for the life of the process, long after the
/// connection came back. The doc on the matcher says being unlinked is
/// "recoverable" — this was the code that made it not.
///
/// Three states rather than a nullable value and a bool, so the caller has to
/// name which one it is handling.
class TrackerLookup<T> {
  /// The catalogue answered and this is the entry.
  const TrackerLookup.found(T this.value) : answered = true;

  /// The catalogue answered and has nothing matching. Worth remembering.
  const TrackerLookup.noMatch() : value = null, answered = true;

  /// The catalogue was not reached. Nothing was learned, so nothing should be
  /// remembered — the next episode tries again.
  const TrackerLookup.unreachable() : value = null, answered = false;

  final T? value;

  /// Whether the catalogue gave an answer, of either kind.
  final bool answered;

  /// Whether a null result is worth writing down as hopeless.
  ///
  /// Reads at the call site as the question actually being asked: only an
  /// answer of "no" is a fact about the title rather than about the network.
  bool get isSettledMiss => answered && value == null;

  /// Re-wraps the result of mapping [value], keeping the reason a miss was a
  /// miss. A lookup that never reached the server must not become a settled
  /// miss just because the thing it was mapped to is also absent.
  TrackerLookup<R> map<R>(R? Function(T value) f) {
    if (!answered) return TrackerLookup<R>.unreachable();
    final v = value;
    if (v == null) return TrackerLookup<R>.noMatch();
    final mapped = f(v);
    return mapped == null
        ? TrackerLookup<R>.noMatch()
        : TrackerLookup<R>.found(mapped);
  }
}
