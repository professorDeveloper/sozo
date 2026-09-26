import 'dart:math' as math;

/// Where a horizontal swipe on the video lands.
///
/// Fine near the finger's start, coarse far from it, as VLC does: about two
/// seconds per centimetre for the first few, then a cubic that reaches half
/// the video (at least a minute, at most twenty) by eight centimetres. It
/// used to be 90 seconds per screen width, clamped to one width, so a single
/// swipe could never move more than a minute and a half — and from the middle
/// of the screen, about 45 seconds — whatever the length of the video.
///
/// Within [cancelZoneCm] of the start the answer is the start itself: a
/// finger brought back to where it began means "never mind".
class ScrubCurve {
  ScrubCurve._();

  /// Logical pixels in a centimetre, near enough for a phone.
  static const double pxPerCm = 38;
  static const double cancelZoneCm = 0.3;

  static int targetMs({
    required int baselineMs,
    required int durationMs,
    required double deltaPx,
  }) {
    if (durationMs <= 0) return baselineMs;
    final cm = deltaPx / pxPerCm;
    final a = cm.abs();
    if (a < cancelZoneCm) return baselineMs.clamp(0, durationMs);
    final reach = (durationMs / 1000 * 0.5).clamp(60.0, 1200.0);
    final seconds = 2.0 * a + reach * math.pow(a / 8, 3);
    final target = baselineMs + (cm.sign * seconds * 1000).round();
    return target.clamp(0, durationMs);
  }

  /// Whether [deltaPx] is inside the cancel zone.
  static bool cancels(double deltaPx) =>
      (deltaPx / pxPerCm).abs() < cancelZoneCm;
}
