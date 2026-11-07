/// When each friend can be invited again. The server keeps the real cooldown
/// and reports it in seconds; this turns that into deadlines on this device's
/// clock so a picker can count down without asking again.
class InviteCooldowns {
  InviteCooldowns({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final Map<String, DateTime> _until = <String, DateTime>{};

  void set(String userId, int retryAfterSec) {
    if (retryAfterSec <= 0) {
      _until.remove(userId);
      return;
    }
    _until[userId] = _clock().add(Duration(seconds: retryAfterSec));
  }

  /// From `GET /watch-party/:code/invites` → `items: [{userId, retryAfterSec}]`.
  void applyServer(dynamic items) {
    if (items is! List) return;
    for (final raw in items.whereType<Map>()) {
      final id = raw['userId'];
      final sec = raw['retryAfterSec'];
      if (id is String && sec is num) set(id, sec.ceil());
    }
  }

  Duration remaining(String userId) {
    final until = _until[userId];
    if (until == null) return Duration.zero;
    final left = until.difference(_clock());
    if (left <= Duration.zero) {
      _until.remove(userId);
      return Duration.zero;
    }
    return left;
  }

  bool coolingDown(String userId) => remaining(userId) > Duration.zero;

  bool get any => _until.keys.toList().any(coolingDown);

  /// `9:05`, rounded up so it never reads `0:00` while still blocked.
  static String format(Duration d) {
    final total = (d.inMilliseconds / 1000).ceil();
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
