import 'dart:async';
import 'dart:math' as math;

/// Why Auto moved past a source.
enum AutoSkipReason {
  /// The title it found was not close enough to pick for someone.
  noMatch,

  /// It has the show but not this episode.
  noEpisode,

  /// It could not be reached, or had nothing to play.
  error,
}

/// What one try at a candidate produced: something to play, or why not.
class AutoAttempt<R> {
  const AutoAttempt.found(R this.value) : reason = null;
  const AutoAttempt.skipped(AutoSkipReason this.reason) : value = null;

  final R? value;
  final AutoSkipReason? reason;
}

/// A candidate Auto moved past, and why.
class AutoSkip<T> {
  const AutoSkip(this.candidate, this.reason);

  final T candidate;
  final AutoSkipReason reason;
}

enum AutoWalkEnd { found, exhausted, capped, stopped }

class AutoWalkResult<R> {
  const AutoWalkResult(this.end, [this.value]);

  final AutoWalkEnd end;

  /// Set only when [end] is [AutoWalkEnd.found].
  final R? value;
}

/// Goes down a list that may still be growing and returns the first candidate
/// that plays.
///
/// The list is read again on every step because search results keep arriving
/// while the walk runs. While the list has nothing new and [searching] is
/// still true, the walk waits for more.
class AutoResolveWalk<T extends Object, R> {
  AutoResolveWalk({
    required this.candidates,
    required this.searching,
    required this.idOf,
    required this.isEligible,
    required this.attempt,
    this.cap = maxCandidates,
    this.poll = const Duration(milliseconds: 250),
    this.onChange,
  });

  /// More than this and the viewer has waited long enough to pick by hand.
  static const int maxCandidates = 20;

  final List<T> Function() candidates;
  final bool Function() searching;
  final String Function(T) idOf;

  /// Whether a candidate is good enough to try without asking.
  final bool Function(T) isEligible;
  final Future<AutoAttempt<R>> Function(T) attempt;
  final int cap;
  final Duration poll;

  /// Called whenever [current], [index], [total] or [skipped] may have changed.
  final void Function()? onChange;

  final Set<String> _seen = {};
  final List<AutoSkip<T>> _skipped = [];
  final Completer<void> _stop = Completer<void>();
  T? _current;
  int _attempts = 0;
  bool _running = false;

  /// The candidate being tried right now, or null while waiting for more.
  T? get current => _current;

  /// Which try this is, from 1.
  int get index => _attempts;

  /// The tries this walk will make with what is known so far. Grows while
  /// search results arrive, and never passes [cap].
  int get total {
    var waiting = 0;
    for (final c in candidates()) {
      if (isEligible(c) && !_seen.contains(idOf(c))) waiting++;
    }
    return math.min(cap, _attempts + waiting);
  }

  List<AutoSkip<T>> get skipped => List.unmodifiable(_skipped);

  bool get stopped => _stop.isCompleted;

  /// Ends the walk now. A try still in flight is ignored when it lands.
  void stop() {
    if (_stop.isCompleted) return;
    _stop.complete();
    _current = null;
    onChange?.call();
  }

  Future<AutoWalkResult<R>> run() async {
    if (_running) throw StateError('an AutoResolveWalk runs once');
    _running = true;
    while (!stopped) {
      if (_attempts >= cap) return _end(AutoWalkEnd.capped);
      T? next;
      for (final c in candidates()) {
        if (_seen.contains(idOf(c)) || !isEligible(c)) continue;
        next = c;
        break;
      }
      if (next == null) {
        if (!searching()) {
          _skipIneligible();
          return _end(AutoWalkEnd.exhausted);
        }
        await Future.any([Future<void>.delayed(poll), _stop.future]);
        continue;
      }
      final candidate = next;
      _seen.add(idOf(candidate));
      _attempts++;
      _current = candidate;
      onChange?.call();

      AutoAttempt<R>? outcome;
      try {
        outcome = await Future.any<AutoAttempt<R>?>([
          attempt(candidate),
          _stop.future.then((_) => null),
        ]);
      } catch (_) {
        outcome = AutoAttempt<R>.skipped(AutoSkipReason.error);
      }
      if (stopped || outcome == null) break;
      _current = null;
      final reason = outcome.reason;
      if (reason == null) return _end(AutoWalkEnd.found, outcome.value);
      _skipped.add(AutoSkip(candidate, reason));
      onChange?.call();
    }
    return AutoWalkResult<R>(AutoWalkEnd.stopped);
  }

  /// The ones never tried because the match was too weak, so the end state
  /// can still say why they were passed over.
  void _skipIneligible() {
    for (final c in candidates()) {
      final id = idOf(c);
      if (isEligible(c) || _seen.contains(id)) continue;
      _seen.add(id);
      _skipped.add(AutoSkip(c, AutoSkipReason.noMatch));
    }
  }

  AutoWalkResult<R> _end(AutoWalkEnd end, [R? value]) {
    _current = null;
    onChange?.call();
    return AutoWalkResult(end, value);
  }
}
