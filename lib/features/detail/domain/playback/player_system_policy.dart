import 'dart:ui' show AppLifecycleState, Rect, Size;

/// Whether the app leaving the foreground pauses the player.
///
/// `inactive` is not leaving: on a phone it is the notification shade, a
/// permission dialog, split-screen focus or Control Center. The desktop keeps
/// playing and floats instead.
bool pausesOnLifecycle(
  AppLifecycleState state, {
  required bool desktop,
  required bool inPip,
}) {
  if (desktop || inPip) return false;
  return state == AppLifecycleState.paused || state == AppLifecycleState.hidden;
}

enum PipChange { none, entered, restored, dismissed }

/// Android picture-in-picture, as the player sees it.
///
/// [active] goes true before the system is asked, so the lifecycle callbacks
/// fired while the window shrinks never mistake it for leaving the app.
class AndroidPipTracker {
  bool _active = false;

  bool get active => _active;

  void beginEnter() => _active = true;

  void enterFailed() => _active = false;

  /// The activity's PiP mode changed. [dismissed] is the window closed with
  /// its X or swiped away, rather than expanded back into the app.
  PipChange onModeChanged({required bool inPip, required bool dismissed}) {
    if (inPip) {
      _active = true;
      return PipChange.entered;
    }
    final was = _active;
    _active = false;
    if (dismissed) return PipChange.dismissed;
    return was ? PipChange.restored : PipChange.none;
  }

  PipChange onResumed() {
    if (!_active) return PipChange.none;
    _active = false;
    return PipChange.restored;
  }
}

enum AudioFocusEvent { gain, loss, lossTransient, duck, noisy }

AudioFocusEvent? audioFocusEventFromWire(String? name) => switch (name) {
  'gain' => AudioFocusEvent.gain,
  'loss' => AudioFocusEvent.loss,
  'loss_transient' => AudioFocusEvent.lossTransient,
  'duck' => AudioFocusEvent.duck,
  'noisy' => AudioFocusEvent.noisy,
  _ => null,
};

class AudioFocusResponse {
  const AudioFocusResponse({
    this.pause = false,
    this.resume = false,
    this.volume,
  });

  static const none = AudioFocusResponse();

  final bool pause;
  final bool resume;

  /// The player's own volume to set, null to leave it.
  final double? volume;

  @override
  bool operator ==(Object other) =>
      other is AudioFocusResponse &&
      other.pause == pause &&
      other.resume == resume &&
      other.volume == volume;

  @override
  int get hashCode => Object.hash(pause, resume, volume);

  @override
  String toString() =>
      'AudioFocusResponse(pause: $pause, resume: $resume, volume: $volume)';
}

/// What the player does about audio focus and the headphones coming out.
///
/// A call or an alarm pauses and plays on afterwards; another app taking
/// focus for good, or unplugged headphones, pause and stay paused.
class AudioFocusPolicy {
  static const double duckVolume = 0.3;

  bool _pausedForTransient = false;
  bool _ducked = false;

  AudioFocusResponse on(AudioFocusEvent event, {required bool playing}) {
    switch (event) {
      case AudioFocusEvent.gain:
        final resume = _pausedForTransient && !playing;
        final volume = _ducked ? 1.0 : null;
        _pausedForTransient = false;
        _ducked = false;
        return AudioFocusResponse(resume: resume, volume: volume);
      case AudioFocusEvent.loss:
      case AudioFocusEvent.noisy:
        _pausedForTransient = false;
        return playing
            ? const AudioFocusResponse(pause: true)
            : AudioFocusResponse.none;
      case AudioFocusEvent.lossTransient:
        if (!playing) return AudioFocusResponse.none;
        _pausedForTransient = true;
        return const AudioFocusResponse(pause: true);
      case AudioFocusEvent.duck:
        if (_ducked) return AudioFocusResponse.none;
        _ducked = true;
        return const AudioFocusResponse(volume: duckVolume);
    }
  }

  /// The viewer pressed play themselves while a call had it paused: the
  /// call ending must not toggle it again.
  void onPlayingChanged(bool playing) {
    if (playing) _pausedForTransient = false;
  }
}

/// The viewer's brightness inside the player, kept so it can be handed back
/// to the system on the way out and applied again on the way back in.
class BrightnessKeeper {
  double? _level;

  double? get level => _level;

  void userSet(double value) => _level = value.clamp(0.0, 1.0).toDouble();

  /// Whether going to the background has a level to hand back.
  bool onBackground() => _level != null;

  /// The level to apply again on return, if the viewer set one.
  double? onResume() => _level;

  void onExit() => _level = null;
}

/// The picture's rectangle on a screen of [screen], letterboxed: what Android
/// animates from when it shrinks the activity into the floating window.
Rect? pipSourceRect(Size screen, Size video) {
  if (screen.isEmpty || video.isEmpty) return null;
  final scale = (screen.width / video.width) < (screen.height / video.height)
      ? screen.width / video.width
      : screen.height / video.height;
  final w = video.width * scale;
  final h = video.height * scale;
  return Rect.fromLTWH((screen.width - w) / 2, (screen.height - h) / 2, w, h);
}

/// Android refuses an aspect ratio outside 1:2.39 to 2.39:1.
(int, int) pipAspect(Size video) {
  final w = video.width.round();
  final h = video.height.round();
  if (w <= 0 || h <= 0) return (16, 9);
  final aspect = w / h;
  if (aspect < 1 / 2.39 || aspect > 2.39) return (16, 9);
  return (w, h);
}

/// Throttles playback-state updates to the media session: the system
/// extrapolates the position itself, so only a change of state, speed or a
/// jump needs sending.
class MediaSessionGate {
  static const int driftMs = 1500;

  bool? _playing;
  double? _speed;
  int _positionMs = 0;
  int _sentAtMs = 0;

  bool shouldSend({
    required bool playing,
    required int positionMs,
    required double speed,
    required int nowMs,
  }) {
    var send = playing != _playing || speed != _speed;
    if (!send) {
      final elapsed = playing ? ((nowMs - _sentAtMs) * speed).round() : 0;
      send = (positionMs - (_positionMs + elapsed)).abs() > driftMs;
    }
    if (send) {
      _playing = playing;
      _speed = speed;
      _positionMs = positionMs;
      _sentAtMs = nowMs;
    }
    return send;
  }

  void reset() {
    _playing = null;
    _speed = null;
  }
}
