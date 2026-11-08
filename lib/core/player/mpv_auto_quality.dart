/// libmpv's "Auto" quality, which mpv itself does not have.
///
/// mpv opens one HLS rendition (`hls-bitrate`) and never switches. Auto used to
/// mean "the top one" everywhere, which on mobile data rebuffered every few
/// seconds. Now the start follows the connection, and repeated stalls step
/// down one rung.
library;

import 'package:soplay/core/player/media_controller.dart';

enum NetworkKind { unmetered, cellular, unknown }

abstract final class MpvAutoQuality {
  /// Auto's ceiling on mobile data.
  static const int cellularCap = 720;

  static const List<int> rungs = [2160, 1440, 1080, 720, 480, 360];

  /// The `hls-bitrate` to open with. Only Auto (0) depends on the network.
  static String startBitrate({
    required int preference,
    required NetworkKind network,
  }) {
    if (preference != 0) return PlayerController.hlsBitrateFor(preference);
    return network == NetworkKind.cellular
        ? PlayerController.hlsBitrateFor(cellularCap)
        : 'max';
  }

  /// One rung below [currentHeight], or null at the bottom already.
  static String? stepDown({int? currentHeight, required String current}) {
    final h = currentHeight;
    if (h != null && h > 0) {
      for (final r in rungs) {
        if (r < h - h * 0.08) return PlayerController.hlsBitrateFor(r);
      }
      return current == 'min' ? null : 'min';
    }
    if (current == 'min') return null;
    if (current == 'max') return PlayerController.hlsBitrateFor(1080);
    final bps = int.tryParse(current);
    if (bps == null) return null;
    for (final r in rungs) {
      final b = PlayerController.hlsBitrateFor(r);
      if (int.parse(b) < bps) return b;
    }
    return 'min';
  }
}

/// Counts buffering stalls during playback. [stalls] of them inside [window]
/// trips it; a stall right after a seek is the seek, not the network.
class StallWatchdog {
  StallWatchdog({
    this.stalls = 3,
    this.window = const Duration(seconds: 60),
    this.afterSeek = const Duration(seconds: 3),
  });

  final int stalls;
  final Duration window;
  final Duration afterSeek;

  final List<Duration> _at = <Duration>[];
  Duration? _seekAt;
  bool _disabled = false;

  bool get disabled => _disabled;

  /// After an undo the viewer has said what they want; no more stepping.
  void disable() {
    _disabled = true;
    _at.clear();
  }

  void noteSeek(Duration now) => _seekAt = now;

  /// A stall began at [now]. True when it is the one that trips the watchdog,
  /// which then starts counting afresh.
  bool recordStall(Duration now) {
    if (_disabled) return false;
    final seek = _seekAt;
    if (seek != null && now - seek <= afterSeek) return false;
    _at.removeWhere((t) => now - t > window);
    _at.add(now);
    if (_at.length >= stalls) {
      _at.clear();
      return true;
    }
    return false;
  }

  void reset() {
    _at.clear();
    _seekAt = null;
  }
}
