import 'package:flutter/foundation.dart';
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

/// What the server's sweep said about a source. Only the bad news is sent;
/// a source with no verdict is fine as far as anyone knows.
enum RemoteHealth {
  /// Unreachable on two nightly sweeps in a row, parked, or flagged down by
  /// its maintainer.
  dead,

  /// The site answered the sweep with a Cloudflare challenge. Not dead: a
  /// phone often gets through where a datacenter address does not.
  cloudflare,

  /// Answered, but slowly.
  slow,
}

class RemoteVerdict {
  const RemoteVerdict({required this.state, this.reason, this.checkedAt});

  final RemoteHealth state;

  /// The sweep's reason code (`dns`, `parked`, `timeout`, …), or null when the
  /// server gave none.
  final String? reason;

  final DateTime? checkedAt;
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

  /// The server's verdicts: `{checkedAt, sources: {id: {ok}}, extCheckedAt,
  /// extensions: {id: {state, cf, reason}}}`. Null where there is no server
  /// to ask, which is every test.
  final Future<Map<String, dynamic>> Function()? remote;

  static const String _key = 'search_source_health';
  static const String _remoteKey = 'search_source_health_remote';
  static const String _playsKey = 'search_source_plays';
  static const String _hideDownKey = 'search_source_health_hide_down';

  /// Ticks whenever the server's verdicts or the hide preference change, so a
  /// list showing badges can rebuild. Static for the same reason as [_cache].
  static final ValueNotifier<int> _changes = ValueNotifier(0);
  ValueListenable<int> get changes => _changes;

  /// How many plays it takes before a source counts as proven, and the point
  /// past which more of them mean nothing.
  ///
  /// The tally would otherwise only ever go up, and two sources that have both
  /// clearly worked would be ordered by a margin nobody can see or change —
  /// fifty plays sitting above forty-nine forever, even when the forty-nine
  /// answers in a fraction of the time. Past this, proven is proven and the
  /// measured answer decides; below it, a source that has served something is
  /// ahead of one that never has.
  ///
  /// Three rather than a larger number because the difference between one play
  /// and five is mostly how much of a series somebody happened to watch, not
  /// how good the source is.
  static const int provenAt = 3;

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

  /// The health map, re-keyed once and then kept.
  ///
  /// `raw.map(...)` builds a brand-new Map of every record. That ran on EVERY
  /// [statusOf] — and `order()` calls statusOf once per source while
  /// `budgetFor` calls it again per leg, so ordering a thousand sources
  /// allocated a thousand copies of a map with a thousand entries in it, on the
  /// UI isolate, inside a build. O(n) work per item is O(n²) per frame.
  ///
  /// Static, because the store is constructed in more than one place — the DI
  /// singleton and `CrossSearchEngine`'s own default — and every instance
  /// reads the SAME Hive key. A per-instance cache would let one instance
  /// serve a record another had already overwritten. It is invalidated by the
  /// writes below rather than by a listener: this class is the only thing that
  /// writes this key, so it always knows.
  static Map<String, dynamic>? _cache;

  /// The play tally, cached for the same reason as [_cache]: `order()` asks
  /// for it once per source, and rebuilding the map per item is O(n) work
  /// inside an O(n log n) sort.
  static Map<String, int>? _playCache;

  Map<String, dynamic> _load() {
    final cached = _cache;
    if (cached != null) return cached;
    final raw = _box?.get(_key);
    if (raw is! Map) return _cache = const {};
    return _cache = raw.map((k, v) => MapEntry(k.toString(), v));
  }

  /// When this source's record was written, in epoch milliseconds, or null if
  /// there is none.
  ///
  /// Exposed for the one rule that is about the record's AGE rather than its
  /// value: a failure under a penalty budget must not renew the mark, because
  /// renewing it is what stopped the TTL ever expiring. Nothing else needs it.
  int? rawRecordedAt(String id) {
    final entry = _load()[id];
    if (entry is! Map) return null;
    final at = entry['at'];
    return at is int ? at : null;
  }

  /// How many times this source has actually served something that played,
  /// capped at [provenAt].
  ///
  /// Searching well and playing are different skills. A source that answers a
  /// search in 200ms and then cannot produce a stream outranked one that takes
  /// a second and always plays, because until now the only evidence the order
  /// was built on came from the search itself.
  int playsOf(String id) {
    final cached = _playCache ??= _loadPlays();
    final n = cached[id] ?? 0;
    return n > provenAt ? provenAt : n;
  }

  Map<String, int> _loadPlays() {
    final raw = _box?.get(_playsKey);
    if (raw is! Map) return const {};
    return {
      for (final e in raw.entries)
        if (e.value is int) e.key.toString(): e.value as int,
    };
  }

  /// Records that [id] served something that actually started playing.
  ///
  /// Called once per stream that reaches the first frame, not once per attempt
  /// — an attempt is what the health record above already measures, and
  /// counting those here would make a source that fails quickly look busy.
  ///
  /// Stops writing at [provenAt]: past that the number changes nothing, and a
  /// long session would otherwise put a Hive write behind every episode.
  Future<void> recordPlay(String id) async {
    if (id.isEmpty) return;
    final box = _box;
    if (box == null) return;
    final plays = Map<String, int>.of(_playCache ??= _loadPlays());
    final current = plays[id] ?? 0;
    if (current >= provenAt) return;
    plays[id] = current + 1;
    _playCache = plays;
    try {
      await box.put(_playsKey, plays);
    } catch (_) {}
  }

  /// The remembered health of one source, or [SourceHealth.ok] when there is
  /// nothing to remember.
  ///
  /// [key] is the id the server knows the source by, when it differs from the
  /// app's — see `ProviderEntity.healthKey`. Local marks stay keyed by [id].
  SourceHealth statusOf(String id, {String? key}) =>
      _local(id) ?? _remote(key ?? id);

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

  /// What the server last said, as an ordering band. A Cloudflare wall is
  /// ranked with slow sources rather than broken ones: it costs the phone a
  /// challenge, not a timeout, so it keeps its full budget.
  SourceHealth _remote(String key) => switch (remoteVerdictOf(key)?.state) {
    RemoteHealth.dead => SourceHealth.broken,
    RemoteHealth.cloudflare || RemoteHealth.slow => SourceHealth.slow,
    null => SourceHealth.ok,
  };

  static bool _fresh(Object? at) =>
      at is int &&
      DateTime.now().millisecondsSinceEpoch - at <= remoteTtl.inMilliseconds;

  /// The server's verdict on [key], or null when it has nothing to say or
  /// said it too long ago.
  RemoteVerdict? remoteVerdictOf(String key) {
    final raw = _box?.get(_remoteKey);
    if (raw is! Map) return null;
    final checkedAt = raw['checkedAt'];
    final down = raw['down'];
    if (_fresh(checkedAt) && down is List && down.contains(key)) {
      return RemoteVerdict(
        state: RemoteHealth.dead,
        checkedAt: DateTime.fromMillisecondsSinceEpoch(checkedAt as int),
      );
    }
    final extAt = raw['extCheckedAt'];
    final ext = raw['ext'];
    if (!_fresh(extAt) || ext is! Map) return null;
    final row = ext[key];
    if (row is! Map) return null;
    final state = _parseState(row['s']);
    if (state == null) return null;
    final reason = row['r'];
    return RemoteVerdict(
      state: state,
      reason: reason is String ? reason : null,
      checkedAt: DateTime.fromMillisecondsSinceEpoch(extAt as int),
    );
  }

  static RemoteHealth? _parseState(Object? s) => switch (s) {
    'dead' => RemoteHealth.dead,
    'cloudflare' => RemoteHealth.cloudflare,
    'slow' => RemoteHealth.slow,
    _ => null,
  };

  /// The verdict worth putting on a row: dead or Cloudflare, never slow.
  ///
  /// A dead verdict is dropped once this device has had a fresh answer from
  /// the source, for the reason [statusOf] prefers the device: the badge
  /// would otherwise call a source down that just worked.
  RemoteVerdict? badgeOf(String id, {String? key}) {
    final v = remoteVerdictOf(key ?? id);
    if (v == null || v.state == RemoteHealth.slow) return null;
    if (v.state == RemoteHealth.dead) {
      final local = _local(id);
      if (local != null && local != SourceHealth.broken) return null;
    }
    return v;
  }

  bool isDown(String id, {String? key}) =>
      badgeOf(id, key: key)?.state == RemoteHealth.dead;

  /// Down sources moved to the end, or left out when [hide] is set. Stable,
  /// so the order the list arrived in survives within each half. [keep] names
  /// rows that are never hidden — the source in use has to stay findable.
  List<T> sinkDown<T>(
    List<T> rows,
    String Function(T) idOf, {
    String Function(T)? keyOf,
    bool hide = false,
    bool Function(T)? keep,
  }) {
    final up = <T>[];
    final down = <T>[];
    for (final r in rows) {
      (isDown(idOf(r), key: keyOf?.call(r)) ? down : up).add(r);
    }
    if (down.isEmpty) return rows;
    return [
      ...up,
      for (final r in down)
        if (!hide || (keep?.call(r) ?? false)) r,
    ];
  }

  /// Whether lists should leave down sources out. Search still asks them.
  bool get hideDown {
    try {
      return _box?.get(_hideDownKey) == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> setHideDown(bool value) async {
    try {
      await _box?.put(_hideDownKey, value);
    } catch (_) {}
    _changes.value++;
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
    // A record from before extension verdicts existed is refetched at once
    // rather than waiting out the window with nothing to show.
    final hasExt = raw is Map && raw.containsKey('extCheckedAt');
    if (hasExt &&
        fetchedAt is int &&
        DateTime.now().millisecondsSinceEpoch - fetchedAt <
            remoteRefreshEvery.inMilliseconds) {
      return;
    }
    try {
      final report = await fetch();
      final sources = report['sources'];
      final checkedAt = DateTime.tryParse('${report['checkedAt']}');
      final extCheckedAt = DateTime.tryParse('${report['extCheckedAt']}');
      final extensions = report['extensions'];
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
        'extCheckedAt': extCheckedAt?.millisecondsSinceEpoch,
        'ext': {
          if (extensions is Map)
            for (final e in extensions.entries)
              if (e.value is Map && _parseState(e.value['state']) != null)
                e.key.toString(): {
                  's': e.value['state'],
                  if (e.value['reason'] is String) 'r': e.value['reason'],
                },
        },
      });
      _changes.value++;
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
    Duration? honestBudget,
  }) async {
    final map = Map<String, dynamic>.of(_load());

    // A failure under a SHORTENED budget teaches nothing, and writing it down
    // was how a mark became permanent. The sequence: an extension source's
    // first search legitimately takes most of its 45 seconds, because it has
    // to download and dex-load an APK before it can issue one request. It
    // exceeds the batch budget, so it is marked broken. Every later attempt is
    // then clamped to [brokenBudget] — four seconds, less than the download it
    // is being punished for never finishing — so it times out again, and that
    // timeout refreshed `at` and pushed the six-hour TTL forward. Search often
    // enough and the mark never expires: the source is dead forever, on a
    // device where it would work.
    //
    // So a penalised failure leaves the existing record exactly as it is. It
    // still counts as broken; it simply does not get to renew its own
    // sentence, and the TTL can run out and give the source a real chance.
    final penalised = honestBudget != null && budget < honestBudget;
    if (!succeeded && penalised && map[id] is Map) return;

    final state = !succeeded
        ? 'broken'
        : (budget.inMilliseconds > 0 &&
              elapsed.inMilliseconds > budget.inMilliseconds * slowFraction)
        ? 'slow'
        : 'ok';
    map[id] = {'state': state, 'at': DateTime.now().millisecondsSinceEpoch};
    _cache = map;
    try {
      await _box?.put(_key, map);
    } catch (_) {}
  }

  /// The budget one source gets on this run.
  ///
  /// [deliberate] turns the penalty off. It is for the retry the USER pressed
  /// and is watching, and for the "Test this source" diagnostic — both of
  /// which name one source, have no batch to hold up, and were the two places
  /// the four-second leash did the most harm. Retry only ever appears beside a
  /// source that just failed, so before this every single retry ran on the
  /// penalty budget and confirmed the failure it inherited; the diagnostic
  /// then reported a source as dead because it had been given four seconds to
  /// do forty-five seconds of work.
  Duration budgetFor(
    String id,
    Duration base, {
    bool deliberate = false,
    String? key,
  }) =>
      !deliberate &&
          statusOf(id, key: key) == SourceHealth.broken &&
          base > brokenBudget
      ? brokenBudget
      : base;

  /// Reorders a source set healthiest-first, stably.
  ///
  /// Stable because the order the user arranged their sources in is meaningful
  /// to them, and within one health band there is no reason to disturb it.
  List<T> order<T>(
    List<T> refs,
    String Function(T) idOf, {
    String Function(T)? keyOf,
  }) {
    if (refs.length < 2) return refs;
    int rank(SourceHealth h) => switch (h) {
      SourceHealth.ok => 0,
      SourceHealth.slow => 1,
      SourceHealth.broken => 2,
    };
    final indexed = [
      for (var i = 0; i < refs.length; i++)
        (
          index: i,
          ref: refs[i],
          rank: rank(statusOf(idOf(refs[i]), key: keyOf?.call(refs[i]))),
          plays: playsOf(idOf(refs[i])),
        ),
    ];
    // Nothing has been marked and nothing has played — the common case, and
    // not worth a new list.
    if (indexed.every((e) => e.rank == 0 && e.plays == 0)) return refs;
    indexed.sort((a, b) {
      // Health first. A source that timed out last time has not earned a place
      // at the front by having played a week ago, and the shorter budget it is
      // on makes it cheap to ask late anyway.
      final byRank = a.rank.compareTo(b.rank);
      if (byRank != 0) return byRank;
      // Then what has actually played. Within one health band this is the only
      // evidence about the thing the user is really asking for, and it is
      // saturated so it can order two sources without freezing them — see
      // [provenAt].
      final byPlays = b.plays.compareTo(a.plays);
      if (byPlays != 0) return byPlays;
      // And otherwise the order it arrived in, which is the one the user
      // arranged.
      return a.index.compareTo(b.index);
    });
    return [for (final e in indexed) e.ref];
  }

  Future<void> clear() async {
    _cache = null;
    _playCache = null;
    try {
      await _box?.delete(_key);
      await _box?.delete(_remoteKey);
      await _box?.delete(_playsKey);
    } catch (_) {}
    _changes.value++;
  }
}
