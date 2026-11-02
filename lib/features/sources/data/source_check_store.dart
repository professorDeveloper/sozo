import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:soplay/core/constants/app_constants.dart';

/// What a source's last check said about it.
enum SourceVerdict {
  /// Never checked, or the check is too old to mean anything.
  unknown,

  /// Answered with titles.
  alive,

  /// Answered, with nothing to show. Not dead — some sources open onto an
  /// empty home — but not proof of life either.
  empty,

  /// A bot wall (Cloudflare, a captcha, a region lock) or a rate limit
  /// answered instead. The site is alive; opening it once in the WebView
  /// usually lets the app through.
  blocked,

  /// The source's code no longer fits its site or this app: it needs an
  /// update from its repository, not a better connection.
  outdated,

  /// Failed, once or in quick succession. Could be a bad minute.
  failing,

  /// Failed repeatedly, over time, or answered "gone" (404/410) twice.
  dead,
}

/// One source's last check.
@immutable
class SourceCheck {
  const SourceCheck({
    required this.verdict,
    required this.at,
    this.detail,
    this.fails = 0,
    this.firstFailAt,
    this.ms,
  });

  final SourceVerdict verdict;

  /// When it was checked, epoch ms.
  final int at;

  /// The failure as the source reported it, trimmed; null on success.
  final String? detail;

  /// Consecutive failed checks, and when the run of them began.
  final int fails;
  final int? firstFailAt;

  /// How long the answer took.
  final int? ms;

  /// Whether this is a verdict somebody has to do something about.
  ///
  /// [SourceVerdict.empty] is one of them. A catalogue that answered with
  /// nothing is not a working source: a 200 carrying an empty list is the
  /// commonest shape of a site that has shut the backend out — kisskh answers
  /// `/contents/home` exactly that way today — and leaving it out of the list
  /// a check run hands back meant the run counted it and then never named it.
  bool get isBad =>
      verdict == SourceVerdict.dead ||
      verdict == SourceVerdict.outdated ||
      verdict == SourceVerdict.empty;

  Map<String, dynamic> toJson() => {
    'v': verdict.name,
    'at': at,
    'd': ?detail,
    if (fails > 0) 'f': fails,
    'ff': ?firstFailAt,
    'ms': ?ms,
  };

  static SourceCheck? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final at = raw['at'];
    if (at is! int) return null;
    final verdict = SourceVerdict.values
        .where((v) => v.name == raw['v'])
        .firstOrNull;
    if (verdict == null) return null;
    return SourceCheck(
      verdict: verdict,
      at: at,
      detail: raw['d'] as String?,
      fails: (raw['f'] as num?)?.toInt() ?? 0,
      firstFailAt: (raw['ff'] as num?)?.toInt(),
      ms: (raw['ms'] as num?)?.toInt(),
    );
  }
}

/// Every source's last check on this device.
///
/// Read on every row of a list of hundreds, so it is served from memory: the
/// box is read once, and every write updates the copy it came from. [revision]
/// moves on every change, for the widgets that draw a verdict.
class SourceCheckStore {
  SourceCheckStore({Box? box, int Function()? now})
    : _override = box,
      _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final Box? _override;

  /// The clock a verdict's age is measured against. Injectable for the same
  /// reason as `SourceCheckService`'s: every rule here is about elapsed time,
  /// and a test that cannot move the clock can only assert what happens within
  /// one millisecond of now.
  final int Function() _now;

  Box? get _box {
    if (_override != null) return _override;
    try {
      return Hive.box(AppConstants.settingsBox);
    } catch (_) {
      return null;
    }
  }

  static const String _checksKey = 'source_checks';
  static const String _autoKey = 'source_check_auto';

  /// Whether a few stale sources are checked quietly after launch, on Wi-Fi.
  /// On by default: with hundreds of sources, a verdict nobody refreshes is
  /// soon a verdict nobody can trust.
  bool get autoSweep {
    try {
      return _box?.get(_autoKey, defaultValue: true) != false;
    } catch (_) {
      return true;
    }
  }

  Future<void> setAutoSweep(bool value) async {
    try {
      await _box?.put(_autoKey, value);
    } catch (_) {}
  }

  /// A check older than this is not shown as a verdict: a site that was down
  /// last month says nothing about today.
  static const Duration staleAfter = Duration(days: 7);

  Map<String, SourceCheck>? _checks;

  /// Moves on every change, so a verdict on screen can follow it.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  Map<String, SourceCheck> get _all {
    final cached = _checks;
    if (cached != null) return cached;
    final raw = _box?.get(_checksKey);
    final out = <String, SourceCheck>{};
    if (raw is Map) {
      raw.forEach((k, v) {
        final c = SourceCheck.fromJson(v);
        if (c != null) out['$k'] = c;
      });
    }
    return _checks = out;
  }

  /// The last check of [id], or null when there is none worth showing.
  SourceCheck? of(String id) {
    final c = _all[id];
    if (c == null) return null;
    return _expired(_now(), c) ? null : c;
  }

  /// Whether [check] has stopped meaning anything by [nowMs].
  ///
  /// Older than [staleAfter], or stamped after [nowMs]. A verdict dated in the
  /// future came from a clock that has since been corrected — a phone set
  /// forward for an app, or a device that booted before it found the time — and
  /// its age is then not just wrong but negative, which read as "checked
  /// moments ago" and would have kept a stale "Not working" on the row for as
  /// long as the clock was out by.
  static bool _expired(int nowMs, SourceCheck check) {
    final age = nowMs - check.at;
    return age < 0 || age > staleAfter.inMilliseconds;
  }

  SourceVerdict verdictOf(String id) =>
      of(id)?.verdict ?? SourceVerdict.unknown;

  /// Records [check]. With [defer], the write to disk waits a moment so a run
  /// over a thousand sources rewrites the table a few times, not a thousand.
  Future<void> put(String id, SourceCheck check, {bool defer = false}) async {
    _all[id] = check;
    revision.value++;
    defer ? _flushSoon() : await flush();
  }

  Future<void> putAll(Map<String, SourceCheck> checks) async {
    if (checks.isEmpty) return;
    _all.addAll(checks);
    revision.value++;
    await flush();
  }

  Timer? _flushTimer;

  void _flushSoon() {
    _flushTimer ??= Timer(const Duration(seconds: 3), () {
      _flushTimer = null;
      unawaited(_flush());
    });
  }

  /// Writes what is in memory now, and any deferred write with it.
  Future<void> flush() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    await _flush();
  }

  /// When [id] should next be looked at: never checked or gone stale first,
  /// then the ones in trouble (to confirm or clear them), then the working
  /// ones, oldest first. Lower comes first.
  (int, int) urgencyOf(String id) {
    final c = of(id);
    if (c == null) return (0, 0);
    final rank = switch (c.verdict) {
      SourceVerdict.unknown => 0,
      SourceVerdict.failing => 1,
      SourceVerdict.dead || SourceVerdict.outdated => 2,
      SourceVerdict.blocked => 3,
      SourceVerdict.empty => 4,
      SourceVerdict.alive => 5,
    };
    return (rank, c.at);
  }

  Future<void> _flush() async {
    // A verdict nobody can be shown is a verdict nobody should carry: every
    // read already hides the expired ones, so dropping them on the way out
    // keeps the table the size of what was checked this week rather than of
    // every source ever checked on this phone, and stops a seven-month-old row
    // being re-serialised on every run.
    _all.removeWhere((_, c) => _expired(_now(), c));
    try {
      await _box?.put(_checksKey, {
        for (final e in _all.entries) e.key: e.value.toJson(),
      });
    } catch (_) {}
  }

  /// The process-wide store, for code that has no DI to hand — the health
  /// store's badge, read on every row of every source list.
  static SourceCheckStore shared = SourceCheckStore();
}
