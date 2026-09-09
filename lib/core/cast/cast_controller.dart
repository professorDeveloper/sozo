import 'dart:async';

import 'package:dart_cast/dart_cast.dart';
import 'package:flutter/foundation.dart';

/// Sending what is playing to a television.
///
/// ## Why a pure-Dart protocol and not the Cast SDK
///
/// Most of what this app plays is bound to headers. A stream arrives with a
/// `Referer` its CDN insists on, a `User-Agent` a challenge was solved under,
/// sometimes a cookie — and a Chromecast fetches media itself, with no way to
/// carry any of that. Handing the receiver a URL would 403 on most of the
/// catalogue, which is the worst possible shape for this feature: a cast button
/// that works on some titles and not others, with no way for anyone to tell
/// which in advance.
///
/// `dart_cast` runs the CASTV2 protocol from Dart and puts a small HTTP server
/// on the phone's Wi-Fi address in front of the media. The receiver fetches
/// from the phone, the phone fetches upstream with the headers, and m3u8
/// playlists get their segment URLs rewritten to come back the same way. That
/// is the same trick the app's own local HLS proxy already plays for on-device
/// playback, and it is the reason casting can work here at all.
///
/// ## Chromecast only, deliberately
///
/// The package also speaks AirPlay and DLNA. AirPlay video is documented as
/// failing on every receiver its author has tested, and DLNA pipes remote HLS
/// as MPEG-TS — which is nearly everything this app streams. Listing a device
/// the app cannot actually play to is worse than not listing it: the viewer
/// blames the app, not the protocol. Adding either later is one more discovery
/// provider plus its session type.
class CastController extends ChangeNotifier {
  CastController({CastService? service})
      : _service = service ??
            CastService(
              discoveryProviders: [ChromecastDiscoveryProvider()],
              sessionFactory: (device) => ChromecastSession(device: device),
            );

  static const String _tag = '[cast]';

  /// Long enough for a TV that is asleep on the network to answer, short enough
  /// that an empty list means something.
  static const Duration discoveryTimeout = Duration(seconds: 8);

  final CastService _service;

  StreamSubscription<List<CastDevice>>? _discovery;
  StreamSubscription<SessionState>? _states;

  List<CastDevice> _devices = const [];
  CastDevice? _device;
  CastSession? _session;
  SessionState _state = SessionState.disconnected;
  bool _scanning = false;
  String? _error;

  List<CastDevice> get devices => _devices;
  CastDevice? get device => _device;
  SessionState get state => _state;
  bool get scanning => _scanning;
  String? get error => _error;

  /// Whether playback is currently somewhere other than this phone.
  ///
  /// The player asks this to decide whether its own surface is the thing
  /// showing the video. Anything short of a live session is not casting, so a
  /// connection that dropped reads as false and the local player takes over.
  bool get isCasting =>
      _session != null &&
      _state != SessionState.disconnected &&
      _state != SessionState.idle;

  // --- discovery ---------------------------------------------------------

  void startDiscovery() {
    if (_scanning) return;
    _scanning = true;
    _error = null;
    _devices = const [];
    notifyListeners();

    _discovery?.cancel();
    _discovery = _service
        .startDiscovery(
          protocols: {CastProtocol.chromecast},
          timeout: discoveryTimeout,
        )
        .listen(
          (found) {
            _devices = found;
            notifyListeners();
          },
          onError: (Object e) {
            debugPrint('$_tag discovery failed: $e');
            _error = e.toString();
            _scanning = false;
            notifyListeners();
          },
          onDone: () {
            _scanning = false;
            notifyListeners();
          },
        );
  }

  void stopDiscovery() {
    _discovery?.cancel();
    _discovery = null;
    if (_scanning) {
      _scanning = false;
      notifyListeners();
    }
    _service.stopDiscovery();
  }

  // --- session -----------------------------------------------------------

  /// Connect and start playing in one step.
  ///
  /// One step because there is no useful state in between: a viewer who picked
  /// a TV wants the episode on it, and a connected-but-empty session is a state
  /// they would have to be shown and given a second button for.
  Future<bool> castTo(CastDevice device, CastMedia media) async {
    try {
      stopDiscovery();
      _error = null;
      _device = device;
      _state = SessionState.connecting;
      notifyListeners();

      final session = await _service.connect(device);
      _session = session;
      _watch(session);

      await session.loadMedia(media);
      return true;
    } catch (e) {
      debugPrint('$_tag could not cast to ${device.name}: $e');
      _error = e.toString();
      await _teardown();
      notifyListeners();
      return false;
    }
  }

  void _watch(CastSession session) {
    _states?.cancel();
    _states = session.stateStream.listen((s) {
      _state = s;
      // A receiver that goes idle has ended the session on its side — someone
      // picked up the remote, or another app took the TV. Holding a dead
      // session would leave the phone showing cast controls for a screen that
      // is no longer ours.
      if (s == SessionState.disconnected) {
        _session = null;
        _device = null;
      }
      notifyListeners();
    });
  }

  Stream<Duration>? get positionStream => _session?.positionStream;
  Stream<Duration>? get durationStream => _session?.durationStream;

  Future<void> play() => _guard(() => _session?.play());
  Future<void> pause() => _guard(() => _session?.pause());
  Future<void> seek(Duration to) => _guard(() => _session?.seek(to));
  Future<void> setVolume(double v) => _guard(() => _session?.setVolume(v));

  /// End the session and bring playback back to the phone.
  Future<void> stopCasting() async {
    await _guard(() => _session?.stop());
    await _teardown();
    notifyListeners();
  }

  Future<void> _teardown() async {
    await _states?.cancel();
    _states = null;
    try {
      await _session?.disconnect();
    } catch (e) {
      debugPrint('$_tag disconnect threw: $e');
    }
    _session = null;
    _device = null;
    _state = SessionState.disconnected;
  }

  /// Controls never throw at the caller.
  ///
  /// Every one of these is a button under someone's thumb, and the failure is
  /// always the same shape — the TV went away. Surfacing that as an exception
  /// from a tap handler turns a lost connection into a crash report.
  Future<void> _guard(Future<void>? Function() action) async {
    try {
      await action();
    } catch (e) {
      debugPrint('$_tag control failed: $e');
    }
  }

  @override
  void dispose() {
    _discovery?.cancel();
    _states?.cancel();
    unawaited(_service.dispose());
    super.dispose();
  }
}

/// Which cast media type a URL is, or null when it is not castable.
///
/// Null is a real answer and the caller is expected to use it. A torrent handle
/// or a `content://` path has nothing a receiver on the network could fetch,
/// and offering the button anyway produces a spinner that never resolves.
CastMediaType? castTypeFor(String url, {String? hint}) {
  final lower = url.toLowerCase();
  // Reachability first, container second. A receiver fetches the media itself,
  // so a path on this phone's disk or a content:// handle is out regardless of
  // what it ends in — and a downloaded episode ends in .mp4 like any other,
  // which is exactly how "castable" would otherwise be answered wrongly.
  if (!lower.startsWith('http://') && !lower.startsWith('https://')) return null;
  if (hint == 'hls' || lower.contains('.m3u8')) return CastMediaType.hls;
  if (lower.contains('.mpd')) return null; // DASH: no receiver support here.
  if (lower.contains('.mkv')) return CastMediaType.mkv;
  if (lower.contains('.ts')) return CastMediaType.mpegTs;
  if (lower.contains('.mp4') || lower.contains('.m4v')) return CastMediaType.mp4;
  // Unknown extension over http(s) is usually an mp4 behind a redirect, which
  // is the one guess a receiver recovers from on its own.
  return CastMediaType.mp4;
}
