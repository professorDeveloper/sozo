import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/core/constants/app_constants.dart';

/// How a source behaved the last time it was searched.
enum SourceHealth {
  /// Answered, in time. Also the answer for a source never searched: a new
  /// source is given the benefit of the doubt rather than starting last.
  ok,

  /// Answered, but took most of its budget. Still useful, still worth asking —
  /// just not worth making everything else wait behind.
  slow,

  /// Timed out or threw. Asked again, on a shorter leash.
  broken,
}

/// What each source did last time, so the next search does not repeat the wait.
///
/// ## The problem this solves
///
/// A fan-out is only as fast as its slowest leg that the user is still waiting
/// on. With a large source set, two or three dead extensions burn the full
/// per-source budget on *every* search, forever, and the results that were
/// going to arrive in 400ms are queued behind them. Nothing about that improves
/// on its own — the dead source is asked first just as often as the good one,
/// because the order is whatever the provider list happens to be in.
///
/// ## Ordered, not skipped
///
/// A known-broken source is still searched. "Down" here is one observation from
/// one device on one network, and a source that was unreachable on mobile data
/// ten minutes ago is usually fine on wifi now — silently dropping it would
/// make the app quietly worse than it is, in a way nobody could see or report.
/// What it loses is priority and budget: it goes to the back of the queue and
/// gets [brokenBudget] instead of the full one, which is enough for a source
/// that has recovered to prove it, and not enough to hold up the batch.
///
/// Every operation is best-effort. Search has to keep working when the box is
/// unavailable, which is every widget test and the first run before Hive opens.
class SourceHealthStore {
  static const String _key = 'search_source_health';

  /// Below this fraction of its budget, a source is simply fine.
  static const double slowFraction = 0.6;

  /// What a source that failed last time gets to prove it has recovered.
  ///
  /// Long enough for a real HTTP round trip on a bad connection, short enough
  /// that three dead sources cost seconds rather than half a minute.
  static const Duration brokenBudget = Duration(seconds: 4);

  /// After this, a record is not evidence about anything. Sources come back;
  /// networks change; a mark from last week would keep punishing a source that
  /// has been healthy for six days.
  static const Duration ttl = Duration(hours: 6);

  Box? get _box {
    try {
      return Hive.box(AppConstants.settingsBox);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _load() {
    final raw = _box?.get(_key);
    if (raw is! Map) return const {};
    return raw.map((k, v) => MapEntry(k.toString(), v));
  }

  /// The remembered health of one source, or [SourceHealth.ok] when there is
  /// nothing to remember.
  SourceHealth statusOf(String id) {
    final row = _load()[id];
    if (row is! Map) return SourceHealth.ok;
    final at = row['at'];
    if (at is! int ||
        DateTime.now().millisecondsSinceEpoch - at > ttl.inMilliseconds) {
      return SourceHealth.ok;
    }
    return switch (row['state']) {
      'slow' => SourceHealth.slow,
      'broken' => SourceHealth.broken,
      _ => SourceHealth.ok,
    };
  }

  /// Records one leg's outcome.
  ///
  /// [elapsed] is measured, not guessed — a source that answers in 300ms and
  /// one that answers at 9.8s of a 10s budget are both "ok" by status alone,
  /// and only one of them should be at the front of the queue next time.
  Future<void> record(
    String id, {
    required bool succeeded,
    required Duration elapsed,
    required Duration budget,
  }) async {
    final state = !succeeded
        ? 'broken'
        : (budget.inMilliseconds > 0 &&
                elapsed.inMilliseconds > budget.inMilliseconds * slowFraction)
            ? 'slow'
            : 'ok';
    final map = Map<String, dynamic>.of(_load());
    map[id] = {'state': state, 'at': DateTime.now().millisecondsSinceEpoch};
    try {
      await _box?.put(_key, map);
    } catch (_) {}
  }

  /// The budget one source gets on this run.
  Duration budgetFor(String id, Duration base) =>
      statusOf(id) == SourceHealth.broken && base > brokenBudget
          ? brokenBudget
          : base;

  /// Reorders a source set healthiest-first, stably.
  ///
  /// Stable because the order the user arranged their sources in is meaningful
  /// to them, and within one health band there is no reason to disturb it.
  List<T> order<T>(List<T> refs, String Function(T) idOf) {
    if (refs.length < 2) return refs;
    int rank(SourceHealth h) => switch (h) {
      SourceHealth.ok => 0,
      SourceHealth.slow => 1,
      SourceHealth.broken => 2,
    };
    final indexed = [
      for (var i = 0; i < refs.length; i++)
        (index: i, ref: refs[i], rank: rank(statusOf(idOf(refs[i])))),
    ];
    // Nothing has been marked — the common case, and not worth a new list.
    if (indexed.every((e) => e.rank == 0)) return refs;
    indexed.sort((a, b) {
      final byRank = a.rank.compareTo(b.rank);
      return byRank != 0 ? byRank : a.index.compareTo(b.index);
    });
    return [for (final e in indexed) e.ref];
  }

  Future<void> clear() async {
    try {
      await _box?.delete(_key);
    } catch (_) {}
  }
}
