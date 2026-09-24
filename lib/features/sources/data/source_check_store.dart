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

  bool get isBad =>
      verdict == SourceVerdict.dead || verdict == SourceVerdict.outdated;

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
  SourceCheckStore({Box? box}) : _override = box;

  final Box? _override;

  Box? get _box {
    if (_override != null) return _override;
    try {
      return Hive.box(AppConstants.settingsBox);
    } catch (_) {
      return null;
    }
  }

  static const String _checksKey = 'source_checks';

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
    final age = DateTime.now().millisecondsSinceEpoch - c.at;
    return age > staleAfter.inMilliseconds ? null : c;
  }

  SourceVerdict verdictOf(String id) =>
      of(id)?.verdict ?? SourceVerdict.unknown;

  Future<void> put(String id, SourceCheck check) async {
    _all[id] = check;
    revision.value++;
    await _flush();
  }

  Future<void> putAll(Map<String, SourceCheck> checks) async {
    if (checks.isEmpty) return;
    _all.addAll(checks);
    revision.value++;
    await _flush();
  }

  Future<void> _flush() async {
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
