import 'dart:async';

/// One thing fetched ahead of time — the next episode's stream, the next
/// chapter's pages — for the one key it was fetched for.
///
/// Expires after [ttl] because what it holds usually carries signed URLs, and
/// a stream resolved an hour ago is a 403 now.
class PrefetchSlot<T> {
  PrefetchSlot({
    this.ttl = const Duration(minutes: 10),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Duration ttl;
  final DateTime Function() _now;

  String? _key;
  T? _value;
  DateTime? _at;
  String? _loadingKey;
  Future<T?>? _loading;

  bool _fresh() => _at != null && _now().difference(_at!) < ttl;

  /// Whether [key] is held, fresh, or on its way.
  bool covers(String key) =>
      _loadingKey == key || (_key == key && _value != null && _fresh());

  /// Loads [key] unless it is already covered. Failures are swallowed: a
  /// prefetch that fails leaves the normal path to do the work.
  Future<void> fill(String key, Future<T?> Function() load) async {
    if (covers(key)) return;
    _loadingKey = key;
    final future = _guard(load);
    _loading = future;
    final value = await future;
    if (_loadingKey != key) return;
    _loadingKey = null;
    _loading = null;
    if (value == null) return;
    _key = key;
    _value = value;
    _at = _now();
  }

  static Future<T?> _guard<T>(Future<T?> Function() load) async {
    try {
      return await load();
    } catch (_) {
      return null;
    }
  }

  /// Hands over what is held for [key] and forgets it; waits for a load of
  /// [key] still in flight rather than starting a second one.
  Future<T?> take(String key) async {
    if (_loadingKey == key) {
      final value = await _loading;
      if (_loadingKey == key) {
        _loadingKey = null;
        _loading = null;
      }
      return value;
    }
    if (_key != key) return null;
    final value = _fresh() ? _value : null;
    _key = null;
    _value = null;
    _at = null;
    return value;
  }

  void clear() {
    _key = null;
    _value = null;
    _at = null;
    _loadingKey = null;
    _loading = null;
  }
}

/// When to start fetching what comes next, and what the Up next prompt shows.
abstract final class NextUp {
  /// Late enough that most people who get here finish the episode.
  static const double prefetchAt = 0.8;

  /// Auto-advance happens this close to the end.
  static const Duration advanceWindow = Duration(seconds: 2);

  static bool shouldPrefetch(Duration position, Duration duration) {
    final total = duration.inMilliseconds;
    return total > 0 && position.inMilliseconds >= total * prefetchAt;
  }

  /// Seconds until the next episode starts, while the prompt should show;
  /// null otherwise. Never for a clip too short to have credits.
  static int? promptSecondsLeft({
    required Duration position,
    required Duration duration,
    required int countdownSeconds,
  }) {
    if (countdownSeconds <= 0 || duration < const Duration(minutes: 1)) {
      return null;
    }
    final remaining = duration - position;
    if (remaining.isNegative ||
        remaining > Duration(seconds: countdownSeconds) + advanceWindow) {
      return null;
    }
    final left = (remaining - advanceWindow).inMilliseconds / 1000;
    return left.ceil().clamp(0, countdownSeconds);
  }
}
