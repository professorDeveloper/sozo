import 'package:hive_flutter/hive_flutter.dart';

import 'package:soplay/core/constants/app_constants.dart';

/// How long "Not now" on the notification priming sheet is respected.
///
/// Each refusal waits longer than the last — three days, two weeks, then a
/// month — so someone who keeps saying no is asked less and less, and never
/// more than once a month.
class PrimingCooldown {
  PrimingCooldown({Box? box, DateTime Function()? now})
    : _override = box,
      _now = now ?? DateTime.now;

  final Box? _override;
  final DateTime Function() _now;
  Box get _box => _override ?? Hive.box(AppConstants.settingsBox);

  static const String _atKey = 'notif_priming_declined_at';
  static const String _countKey = 'notif_priming_declined';
  static const String _askedKey = 'notif_permission_asked';

  static const List<Duration> steps = [
    Duration(days: 3),
    Duration(days: 14),
    Duration(days: 30),
  ];

  int get declines => (_box.get(_countKey) as num?)?.toInt() ?? 0;

  DateTime? get declinedAt {
    final v = _box.get(_atKey);
    return v is int ? DateTime.fromMillisecondsSinceEpoch(v) : null;
  }

  Duration get currentWait =>
      declines <= 0 ? Duration.zero : steps[(declines - 1).clamp(0, steps.length - 1)];

  /// Whether the sheet may be shown now.
  bool get canAsk {
    final at = declinedAt;
    if (at == null) return true;
    return _now().difference(at) >= currentWait;
  }

  Future<void> declined() async {
    await _box.put(_countKey, declines + 1);
    await _box.put(_atKey, _now().millisecondsSinceEpoch);
  }

  /// Permission was granted: the history of refusals no longer matters.
  Future<void> accepted() async {
    await _box.delete(_countKey);
    await _box.delete(_atKey);
  }

  /// Whether the system prompt has ever been raised on this install — the
  /// half of "permanently denied" Android does not report on its own.
  bool get systemPromptShown => _box.get(_askedKey) == true;

  Future<void> markSystemPromptShown() => _box.put(_askedKey, true);
}
