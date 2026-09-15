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
/// ## Two witnesses
///
/// This device is one. The server is the other: the provider harness runs
/// against every server provider three times a week and the API keeps its
/// verdicts, which [refreshRemote] pulls at most once every
/// [remoteRefreshEvery]. A source the harness found dead starts at the back
/// with the short budget before this device has ever tried it — the case the
/// local record can never cover, because a mark is only made after a wait.
///
/// The device's own fresh observation wins over the server's. "It worked from
/// here, ten minutes ago" is better evidence about the next ten minutes than
/// a run from another network two days ago, and it is the only way a source
/// that recovered gets its place back before the next scheduled run.
///
/// Every operation is best-effort. Search has to keep working when the box is
/// unavailable, which is every widget test and the first run before Hive opens.
class SourceHealthStore {
  SourceHealthStore({this.remote});

  /// The server's verdicts: `{checkedAt, sources: {id: {ok}}}`. Null where
  /// there is no server to ask, which is every test.
  final Future<Map<String, dynamic>> Function()? remote;

  static const String _key = 'search_source_health';
  static const String _remoteKey = 'search_source_health_remote';

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

  /// How often the server is asked again. The report behind it is made three
  /// times a week, so anything tighter is requests for the same answer.
  static const Duration remoteRefreshEvery = Duration(hours: 6);

  /// A server verdict older than this is forgotten. Runs are two or three
  /// days apart; four covers one that was missed without letting a stalled
  /// workflow keep sources at the back for good.
  static const Duration remoteTtl = Duration(days: 4);

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
  SourceHealth statusOf(String id) => _local(id) ?? _remote(id);

  /// This device's own fresh mark, or null when there is none.
  SourceHealth? _local(String id) {
    final row = _load()[id];
    if (row is! Map) return null;
    final at = row['at'];
    if (at is! int ||
        DateTime.now().millisecondsSinceEpoch - at > ttl.inMilliseconds) {
      return null;
    }
    return switch (row['state']) {
      'slow' => SourceHealth.slow,
      'broken' => SourceHealth.broken,
      _ => SourceHealth.ok,
    };
  }

  /// What the server last said, or [SourceHealth.ok] when it said nothing
  /// about this source or said it too long ago.
  SourceHealth _remote(String id) {
    final raw = _box?.get(_remoteKey);
    if (raw is! Map) return SourceHealth.ok;
    final checkedAt = raw['checkedAt'];
    if (checkedAt is! int ||
        DateTime.now().millisecondsSinceEpoch - checkedAt >
            remoteTtl.inMilliseconds) {
      return SourceHealth.ok;
    }
    final down = raw['down'];
    return down is List && down.contains(id)
        ? SourceHealth.broken
        : SourceHealth.ok;
  }

  /// Pulls the server's verdicts if it has been [remoteRefreshEvery] since
  /// the last pull. Never throws, never blocks a search: the run that
  /// triggers it orders by what was known, and the next run knows more.
  Future<void> refreshRemote() async {
    final fetch = remote;
    final box = _box;
    if (fetch == null || box == null) return;
    final raw = box.get(_remoteKey);
    final fetchedAt = raw is Map ? raw['fetchedAt'] : null;
    if (fetchedAt is int &&
        DateTime.now().millisecondsSinceEpoch - fetchedAt <
            remoteRefreshEvery.inMilliseconds) {
      return;
    }
    try {
      final report = await fetch();
      final sources = report['sources'];
      final checkedAt = DateTime.tryParse('${report['checkedAt']}');
      await box.put(_remoteKey, {
        'fetchedAt': DateTime.now().millisecondsSinceEpoch,
        // The report's own date, not the fetch's: a fetch that brings back
        // last month's report should not make it look fresh.
        'checkedAt': checkedAt?.millisecondsSinceEpoch,
        'down': [
          if (sources is Map)
            for (final e in sources.entries)
              if (e.value is Map && e.value['ok'] == false) e.key.toString(),
        ],
      });
    } catch (_) {
      // Whatever the server said last time stands until it answers again.
    }
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
      await _box?.delete(_remoteKey);
    } catch (_) {}
  }
}
