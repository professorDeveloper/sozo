import 'dart:async';
import 'dart:math' as math;

/// Paces requests to a host that has said "too many requests".
///
/// Sites like NovelFire serve a long chapter list as dozens of pages and rate
/// limit anyone who walks them quickly: page 25 of Shadow Slave came back 429,
/// and the chapter the reader then asked for got 429 too, because the site was
/// still cooling down and the Retry button asked again at once. Nothing is
/// paced until a host objects; once it has, every later request to it waits
/// its turn, with the gap widening each time it objects again.
class HostRateLimiter {
  HostRateLimiter({
    Future<void> Function(Duration)? sleep,
    DateTime Function()? now,
  }) : _sleep = sleep ?? Future<void>.delayed,
       _now = now ?? DateTime.now;

  final Future<void> Function(Duration) _sleep;
  final DateTime Function() _now;

  final Map<String, Duration> _spacing = {};
  final Map<String, DateTime> _nextSlot = {};

  static const Duration _firstSpacing = Duration(milliseconds: 400);
  static const Duration _maxSpacing = Duration(seconds: 3);
  static const Duration _maxBackoff = Duration(seconds: 15);

  /// Waits until [host] may be asked again, and books the slot after this
  /// one, so concurrent callers queue instead of all going at once.
  Future<void> acquire(String host) async {
    final spacing = _spacing[host];
    final due = _nextSlot[host];
    if (spacing == null && due == null) return;
    final now = _now();
    final start = due != null && due.isAfter(now) ? due : now;
    _nextSlot[host] = start.add(spacing ?? Duration.zero);
    final wait = start.difference(now);
    if (wait > Duration.zero) await _sleep(wait);
  }

  /// Records a 429 and returns how long to wait before trying again: what the
  /// host asked for in Retry-After, else 2s, 4s, 8s by [attempt]; never more
  /// than 15s.
  Duration throttled(String host, {Duration? retryAfter, int attempt = 0}) {
    final backoff =
        retryAfter ??
        Duration(seconds: 2 * math.pow(2, attempt.clamp(0, 3)).toInt());
    final wait = backoff > _maxBackoff ? _maxBackoff : backoff;
    final previous = _spacing[host];
    final widened = previous == null ? _firstSpacing : previous * 2;
    _spacing[host] = widened > _maxSpacing ? _maxSpacing : widened;
    _nextSlot[host] = _now().add(wait);
    return wait;
  }

  bool isPaced(String host) => _spacing.containsKey(host);

  /// Retry-After as seconds or an HTTP date; null when absent or unreadable.
  static Duration? parseRetryAfter(String? value, {DateTime? now}) {
    if (value == null) return null;
    final v = value.trim();
    if (v.isEmpty) return null;
    final seconds = int.tryParse(v);
    if (seconds != null) return Duration(seconds: math.max(0, seconds));
    final date = _parseHttpDate(v);
    if (date == null) return null;
    final diff = date.difference((now ?? DateTime.now()).toUtc());
    return diff.isNegative ? Duration.zero : diff;
  }

  static DateTime? _parseHttpDate(String v) {
    const months = {
      'jan': 1,
      'feb': 2,
      'mar': 3,
      'apr': 4,
      'may': 5,
      'jun': 6,
      'jul': 7,
      'aug': 8,
      'sep': 9,
      'oct': 10,
      'nov': 11,
      'dec': 12,
    };
    final m = RegExp(
      r'(\d{1,2}) (\w{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2})',
    ).firstMatch(v);
    if (m == null) return null;
    final month = months[m.group(2)!.toLowerCase()];
    if (month == null) return null;
    return DateTime.utc(
      int.parse(m.group(3)!),
      month,
      int.parse(m.group(1)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
      int.parse(m.group(6)!),
    );
  }
}
