/// Taps on the picture: single taps toggle the controls, double taps on a side
/// seek, and while the seek ripple is up every further tap on that side adds
/// another step (YouTube, MX Player). No Flutter import, so it is testable on
/// its own with a fake clock.
library;

enum TapZone { left, centre, right }

enum TapAction {
  /// Wait: this may be the first half of a double tap. Call
  /// [TapSeekTracker.flush] once [TapSeekTracker.doubleTapWindow] has passed.
  pending,
  toggleControls,
  seekBack,
  seekForward,
  togglePlay,
}

class TapSeekTracker {
  TapSeekTracker({
    this.doubleTapWindow = const Duration(milliseconds: 260),
    this.rippleWindow = const Duration(milliseconds: 700),
  });

  final Duration doubleTapWindow;

  /// How long the ripple stays after the last step; the page's ripple timer
  /// must use the same value.
  final Duration rippleWindow;

  TapZone? _pendingZone;
  Duration? _pendingAt;
  TapZone? _seekZone;
  Duration? _lastSeekAt;
  int _steps = 0;

  /// Steps taken in the current run of taps on one side.
  int get steps => _steps;

  bool get hasPending => _pendingZone != null;

  static TapZone zoneOf(double dx, double width) {
    if (width <= 0) return TapZone.centre;
    if (dx < width * 0.3) return TapZone.left;
    if (dx > width * 0.7) return TapZone.right;
    return TapZone.centre;
  }

  bool rippleActive(Duration now) {
    final last = _lastSeekAt;
    return last != null && now - last <= rippleWindow;
  }

  TapAction onTap(
    TapZone zone,
    Duration now, {
    required bool canSeek,
    bool centreTogglesPlay = true,
  }) {
    final side = zone != TapZone.centre;
    if (side && canSeek && _seekZone == zone && rippleActive(now)) {
      _pendingZone = null;
      _pendingAt = null;
      return _seek(zone, now, continuing: true);
    }

    final pendingAt = _pendingAt;
    if (pendingAt != null &&
        _pendingZone == zone &&
        now - pendingAt <= doubleTapWindow) {
      _pendingZone = null;
      _pendingAt = null;
      if (side && canSeek) return _seek(zone, now, continuing: false);
      if (!side && centreTogglesPlay) return TapAction.togglePlay;
      return TapAction.toggleControls;
    }

    final doublePlausible = side ? canSeek : centreTogglesPlay;
    if (!doublePlausible) {
      _pendingZone = null;
      _pendingAt = null;
      return TapAction.toggleControls;
    }
    _pendingZone = zone;
    _pendingAt = now;
    return TapAction.pending;
  }

  /// The pending tap, resolved as a single tap once its window is over, or
  /// null if nothing is pending (a second tap took it, or the window is open).
  TapAction? flush(Duration now) {
    final at = _pendingAt;
    if (at == null || now - at < doubleTapWindow) return null;
    _pendingZone = null;
    _pendingAt = null;
    return TapAction.toggleControls;
  }

  void reset() {
    _pendingZone = null;
    _pendingAt = null;
    _seekZone = null;
    _lastSeekAt = null;
    _steps = 0;
  }

  TapAction _seek(TapZone zone, Duration now, {required bool continuing}) {
    _steps = continuing && _seekZone == zone ? _steps + 1 : 1;
    _seekZone = zone;
    _lastSeekAt = now;
    return zone == TapZone.left ? TapAction.seekBack : TapAction.seekForward;
  }
}
