/// The unlock pill on a locked screen: shown on lock and on every tap, gone
/// [visibleFor] later. Unlocking takes a tap on the pill while it is showing,
/// so a stray touch in a pocket only brings it back.
library;

class LockPill {
  LockPill({this.visibleFor = const Duration(seconds: 3)});

  final Duration visibleFor;
  Duration? _shownAt;

  void show(Duration now) => _shownAt = now;

  void hide() => _shownAt = null;

  bool isVisible(Duration now) {
    final at = _shownAt;
    return at != null && now - at < visibleFor;
  }

  /// When the pill should next be repainted as gone, or null if hidden.
  Duration? hidesAt() {
    final at = _shownAt;
    return at == null ? null : at + visibleFor;
  }

  /// A tap on the pill: unlocks only if it was visible. Otherwise it is shown.
  bool tapPill(Duration now) {
    if (isVisible(now)) {
      hide();
      return true;
    }
    show(now);
    return false;
  }
}
