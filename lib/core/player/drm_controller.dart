import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart' as vp;

import 'package:soplay/core/player/drm_config.dart';
import 'package:soplay/core/player/media_controller.dart';

/// Playback for encrypted streams, wearing the same face as every other engine.
///
/// This is a [PlayerController] like the other two, and that is the entire
/// point: the player page builds one, lays its own controls over
/// [buildView], and never learns that this stream needed decrypting. Gestures,
/// subtitle styling, the sleep timer, the episode panel, the source switcher,
/// speed and aspect all keep working because none of them was ever talking to
/// the backend directly.
///
/// The native side ([DrmPlayerHost]) draws into a `SurfaceTexture`, so
/// [buildView] returns a plain [Texture] — no platform view, nothing
/// composited over the Flutter layer, no z-order surprises with the overlay.
///
/// State is mirrored into [vp.VideoPlayerValue] because that is the currency
/// the rest of the app already speaks. Nothing above needs a second shape for
/// "is it playing".
class DrmController extends PlayerController {
  DrmController({
    required this.url,
    required this.drm,
    this.headers = const {},
  });

  static const MethodChannel _channel = MethodChannel('soplay/drm_player');
  static const EventChannel _events = EventChannel('soplay/drm_player/events');

  /// How long to wait for the first state the native side reports.
  ///
  /// A licence request is a network round trip on top of the manifest, so this
  /// is longer than a plain stream would need. It still has to end: a DRM
  /// stream that never answers must fall back to a mirror rather than spin.
  static const Duration _readyTimeout = Duration(seconds: 20);

  final String url;
  final DrmConfig drm;
  final Map<String, String> headers;

  int? _sessionId;
  int? _textureId;
  StreamSubscription<dynamic>? _sub;
  Completer<void>? _ready;
  bool _disposed = false;

  /// Whether this backend could be used for this stream on this device at all.
  static bool canPlay(DrmConfig? drm) =>
      drm != null && drm.isUsable && DrmConfig.isSupported;

  @override
  Future<void> initialize() async {
    final ready = _ready = Completer<void>();
    _sub = _events.receiveBroadcastStream().listen(
          _onEvent,
          onError: (Object e) => _fail(e.toString()),
        );

    final created = await _channel.invokeMapMethod<String, dynamic>('create', {
      'url': url,
      'headers': headers,
      'drm': drm.toMap(),
    });
    if (_disposed) return;
    _sessionId = created?['id'] as int?;
    _textureId = created?['textureId'] as int?;
    if (_textureId == null) {
      throw PlatformException(code: 'drm', message: 'no texture');
    }

    // Waited on rather than returned immediately, because everything above
    // treats a completed initialize() as "there is a duration and a size now".
    // Returning early would show controls over a surface with nothing on it.
    await ready.future.timeout(
      _readyTimeout,
      onTimeout: () {
        if (!ready.isCompleted) _fail('drm: timed out waiting for first frame');
      },
    );
  }

  void _onEvent(dynamic raw) {
    if (_disposed || raw is! Map) return;
    // Sessions are multiplexed onto one event channel; a stale player being
    // torn down must not repaint the one that replaced it.
    if (raw['id'] != _sessionId) return;

    if (raw['event'] == 'error') {
      _fail(raw['message']?.toString() ?? 'drm: playback failed');
      return;
    }

    final width = (raw['width'] as num?)?.toDouble() ?? 0;
    final height = (raw['height'] as num?)?.toDouble() ?? 0;
    final position = Duration(milliseconds: (raw['position'] as num?)?.toInt() ?? 0);
    final buffered = Duration(milliseconds: (raw['buffered'] as num?)?.toInt() ?? 0);

    value = value.copyWith(
      isInitialized: raw['ready'] == true && width > 0,
      isPlaying: raw['playing'] == true,
      isBuffering: raw['buffering'] == true,
      isCompleted: raw['ended'] == true,
      duration: Duration(milliseconds: (raw['duration'] as num?)?.toInt() ?? 0),
      position: position,
      size: Size(width, height),
      buffered: [vp.DurationRange(Duration.zero, buffered)],
    );

    if (value.isInitialized && !(_ready?.isCompleted ?? true)) {
      _ready?.complete();
    }
  }

  void _fail(String message) {
    debugPrint('[drm] $message');
    value = value.copyWith(errorDescription: message);
    // Completed, not completed-with-error: initialize() is awaited by code that
    // reads errorDescription afterwards, and throwing here would bypass the
    // fallback that reads it.
    if (!(_ready?.isCompleted ?? true)) _ready?.complete();
  }

  Future<T?> _send<T>(String method, [Map<String, dynamic> args = const {}]) {
    final id = _sessionId;
    if (id == null || _disposed) return Future<T?>.value();
    return _channel
        .invokeMethod<T>(method, {'id': id, ...args})
        // Every one of these is a button under a thumb. The failure shape is
        // always the same — the session went away — and a tap handler must not
        // become a crash report.
        .catchError((Object e) {
      debugPrint('[drm] $method failed: $e');
      return null;
    });
  }

  @override
  Future<void> play() => _send<void>('play');

  @override
  Future<void> pause() => _send<void>('pause');

  @override
  Future<void> seekTo(Duration position) =>
      _send<void>('seekTo', {'position': position.inMilliseconds});

  @override
  Future<void> setPlaybackSpeed(double speed) =>
      _send<void>('setSpeed', {'speed': speed});

  @override
  Future<void> setVolume(double volume) =>
      _send<void>('setVolume', {'volume': volume});

  @override
  Future<void> setLooping(bool looping) =>
      _send<void>('setLooping', {'looping': looping});

  /// False: the texture carries the raw video, so the app's own fit and aspect
  /// controls do the letterboxing, exactly as they do for `video_player`.
  @override
  bool get letterboxesInternally => false;

  /// Not exposed by this backend yet.
  ///
  /// ExoPlayer does have track selection, and a DRM stream is precisely the
  /// kind that ships several audio languages — so this is a gap worth closing,
  /// not a property of the format. Reported honestly so the UI hides the
  /// control rather than offering one that silently does nothing.
  @override
  bool get supportsAudioTracks => false;

  @override
  Widget buildView({BoxFit fit = BoxFit.contain}) {
    final id = _textureId;
    if (id == null) return const SizedBox.shrink();
    return Texture(textureId: id);
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _sub?.cancel();
    _sub = null;
    await _send<void>('dispose');
    _sessionId = null;
    _textureId = null;
    super.dispose();
  }
}
