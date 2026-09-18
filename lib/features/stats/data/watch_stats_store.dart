import 'package:hive_flutter/hive_flutter.dart';

import 'package:soplay/core/constants/app_constants.dart';

/// How much has been watched, and when.
///
/// ## Why this is not computed from history
///
/// History is a rolling window of the last fifty titles holding the position
/// somebody stopped at. It answers "where was I" and cannot answer "how long
/// have I watched": the fifty-first title is gone, and a position is not a sum
/// — rewatching an episode three times leaves one position, not three hours.
///
/// So time is accumulated as it passes, from the player's own periodic tick.
///
/// ## It starts from zero
///
/// There is no way to reconstruct what somebody watched before this existed,
/// and a screen claiming to know their all-time hours while having counted
/// since Tuesday would be a lie told confidently. [since] is stamped the first
/// time anything is recorded so the screen can say what it is the total of.
///
/// ## Incognito counts for nothing
///
/// The app promises that in incognito nothing is saved to history. A statistics
/// page quietly totalling those hours would make that promise false in the one
/// mode where somebody explicitly asked not to be recorded. The caller checks,
/// for the same reason the analytics layer does.
///
/// ## Bounded
///
/// Days are kept for [maxDays] so the map cannot grow without limit in a box
/// read at startup. Two years is far longer than any streak anybody will show
/// off, and the running totals are unaffected by the trim.
class WatchStatsStore {
  /// Roughly two years of daily buckets.
  static const int maxDays = 730;

  Box? get _box {
    try {
      return Hive.box(AppConstants.settingsBox);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _load() {
    final raw = _box?.get(AppConstants.watchStatsKey);
    if (raw is! Map) return {};
    return raw.map((k, v) => MapEntry(k.toString(), v));
  }

  Future<void> _write(Map<String, dynamic> data) async {
    try {
      await _box?.put(AppConstants.watchStatsKey, data);
    } catch (_) {}
  }

  /// Seconds watched in total.
  int get totalSeconds => _int(_load()['totalSeconds']);

  /// Titles and episodes finished — [_kTrackerThreshold] of the way through.
  int get completed => _int(_load()['completed']);

  /// When counting began, or null before anything was recorded.
  DateTime? get since {
    final ms = _int(_load()['since']);
    return ms == 0 ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Seconds per day, keyed `yyyy-mm-dd`.
  Map<String, int> get byDay {
    final raw = _load()['byDay'];
    if (raw is! Map) return const {};
    return {
      for (final e in raw.entries) e.key.toString(): _int(e.value),
    };
  }

  /// Seconds per provider, so the screen can say where the time went.
  Map<String, int> get byProvider {
    final raw = _load()['byProvider'];
    if (raw is! Map) return const {};
    return {
      for (final e in raw.entries) e.key.toString(): _int(e.value),
    };
  }

  /// Adds [seconds] of watching against [provider].
  ///
  /// A stretch longer than [_maxPlausibleTick] is CLAMPED rather than dropped.
  /// It used to be dropped, on the reasoning that "a jump of hours is a clock
  /// change or a resumed process" — but the only caller measures with a
  /// `Stopwatch`, which is monotonic, so neither of those can reach here. What
  /// the rule actually did was throw away the longest viewings in their
  /// entirety: the player's save tick was a one-shot that never re-armed, so a
  /// film watched straight through arrived as a single delta of two hours,
  /// failed the ten-minute test, and counted for nothing. The statistics page
  /// read zero for exactly the sessions it was there to show.
  ///
  /// The tick repeats now, so deltas are seconds apart in the ordinary case.
  /// A long one still happens when the platform suspends timers — background
  /// playback, picture-in-picture with the screen off — and that is real
  /// watching. Clamping keeps the guard's purpose, which is that no single
  /// call can put an unexplainable number on the screen, while crediting a
  /// real stretch as far as it is plausible.
  Future<void> record({
    required int seconds,
    required String provider,
  }) async {
    if (seconds <= 0) return;
    if (seconds > _maxPlausibleTick) seconds = _maxPlausibleTick;
    final data = Map<String, dynamic>.of(_load());
    final now = DateTime.now();

    data['totalSeconds'] = _int(data['totalSeconds']) + seconds;
    data['since'] = _int(data['since']) == 0
        ? now.millisecondsSinceEpoch
        : data['since'];

    final day = _dayKey(now);
    final days = Map<String, dynamic>.of(
      data['byDay'] is Map ? (data['byDay'] as Map).cast<String, dynamic>() : {},
    );
    days[day] = _int(days[day]) + seconds;
    if (days.length > maxDays) {
      // Lexicographic order is chronological for yyyy-mm-dd, which is the
      // whole reason the key is shaped that way.
      final ordered = days.keys.toList()..sort();
      for (final k in ordered.take(days.length - maxDays)) {
        days.remove(k);
      }
    }
    data['byDay'] = days;

    if (provider.isNotEmpty) {
      final providers = Map<String, dynamic>.of(
        data['byProvider'] is Map
            ? (data['byProvider'] as Map).cast<String, dynamic>()
            : {},
      );
      providers[provider] = _int(providers[provider]) + seconds;
      data['byProvider'] = providers;
    }

    await _write(data);
  }

  /// Records one finished episode or film.
  Future<void> recordCompleted() async {
    final data = Map<String, dynamic>.of(_load());
    data['completed'] = _int(data['completed']) + 1;
    await _write(data);
  }

  /// Consecutive days ending today (or yesterday) with anything watched.
  ///
  /// Yesterday counts as still alive, because a streak that breaks the moment
  /// midnight passes punishes somebody who watches in the evening for the fact
  /// that they have not watched yet *today*.
  int get streakDays {
    final days = byDay;
    if (days.isEmpty) return 0;
    var cursor = DateTime.now();
    if (!days.containsKey(_dayKey(cursor))) {
      cursor = cursor.subtract(const Duration(days: 1));
      if (!days.containsKey(_dayKey(cursor))) return 0;
    }
    var n = 0;
    while (days.containsKey(_dayKey(cursor))) {
      n++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return n;
  }

  Future<void> clear() async {
    try {
      await _box?.delete(AppConstants.watchStatsKey);
    } catch (_) {}
  }

  /// The most one call may credit — see [record].
  ///
  /// Four hours: longer than any single film, so nothing genuine is cut short,
  /// and short enough that a caller passing nonsense cannot add a week.
  static const int _maxPlausibleTick = 4 * 60 * 60;

  static String _dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static int _int(Object? v) => v is int ? v : (v is num ? v.toInt() : 0);
}
