/// The in-app volume on desktop, where there is no system level to follow.
///
/// Every controller starts at 100%, so the level and mute have to be put back
/// on each new one (a new episode, a retry, a server switch).
library;

class DesktopVolume {
  const DesktopVolume({this.level = 1.0, this.muted = false});

  /// 1.0 is 100%. libmpv accepts up to [boostMax] with `volume-max`.
  static const double boostMax = 1.5;

  final double level;
  final bool muted;

  double get applied => muted ? 0 : level;

  DesktopVolume withLevel(double value, {double max = 1.0}) {
    final v = value.clamp(0.0, max).toDouble();
    return DesktopVolume(level: v <= 0.001 ? level : v, muted: v <= 0.001);
  }

  DesktopVolume toggleMute() =>
      DesktopVolume(level: level <= 0.001 ? 1.0 : level, muted: !muted);

  /// Clamped to what the engine accepts now, without forgetting the stored
  /// level (a 140% set on mpv survives an episode on the platform player).
  Future<void> applyTo(
    Future<void> Function(double) setVolume, {
    double max = 1.0,
  }) => setVolume(applied.clamp(0.0, max).toDouble());

  static DesktopVolume restore(Object? level, Object? muted) {
    final l = level is num ? level.toDouble() : 1.0;
    return DesktopVolume(
      level: l <= 0.001 ? 1.0 : l.clamp(0.0, boostMax).toDouble(),
      muted: muted == true,
    );
  }
}
