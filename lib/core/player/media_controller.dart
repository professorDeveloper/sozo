import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;
import 'package:soplay/core/player/color_profile.dart';
import 'package:soplay/core/player/drm_config.dart';
import 'package:soplay/core/player/player_video_track.dart';
import 'package:soplay/core/player/drm_controller.dart';
import 'package:soplay/core/player/player_engine.dart';
import 'package:soplay/core/player/playback_readiness.dart';
import 'package:soplay/core/system/platform_utils.dart';
import 'package:video_player/video_player.dart' as vp;

// Beside the controllers they bound: whoever builds one to play a network
// stream also decides how long it may take to start.
export 'package:soplay/core/player/playback_readiness.dart'
    show startupBudget, withinStartupBudget;
export 'package:video_player/video_player.dart'
    show
        VideoPlayerValue,
        VideoFormat,
        VideoPlayerOptions,
        ClosedCaptionFile,
        Caption,
        WebVTTCaptionFile,
        SubRipCaptionFile;

abstract class PlayerController extends ValueNotifier<vp.VideoPlayerValue> {
  PlayerController() : super(vp.VideoPlayerValue.uninitialized());

  /// mpv's `hls-bitrate` for the next stream opened on libmpv: 'max',
  /// 'min', or a ceiling in bits per second. Set by the player page from the
  /// quality preference; [hlsBitrateFor] maps one to the other.
  static String mpvHlsBitrate = 'max';

  /// The `hls-bitrate` for a preferred height (see QualityPreference): the
  /// top rendition for Auto, the bottom for Data saver, and otherwise a
  /// ceiling a little above what that height usually streams at, so mpv opens
  /// on it or the nearest below rather than on the top one.
  static String hlsBitrateFor(int preferredHeight) {
    if (preferredHeight == 0) return 'max';
    if (preferredHeight < 0) return 'min';
    final ceiling = switch (preferredHeight) {
      <= 360 => 1000000,
      <= 480 => 1800000,
      <= 720 => 3500000,
      <= 1080 => 7000000,
      <= 1440 => 12000000,
      _ => 25000000,
    };
    return '$ceiling';
  }

  factory PlayerController.networkUrl(
    Uri url, {
    Map<String, String> httpHeaders = const <String, String>{},
    vp.VideoFormat? formatHint,
    vp.VideoPlayerOptions? videoPlayerOptions,
    DrmConfig? drm,
    bool preferPlatform = false,
  }) {
    // Encryption decides the backend before anything else does. libmpv cannot
    // decrypt CENC at all and `video_player` exposes no way to configure it, so
    // an encrypted stream on either of them is a black screen — and the user's
    // engine preference is not a preference about that.
    if (DrmController.canPlay(drm)) {
      return DrmController(
        url: url.toString(),
        drm: drm!,
        headers: httpHeaders,
      );
    }

    // DASH goes to the platform player, whatever engine is selected.
    //
    // ExoPlayer has a first-class DASH extractor — media3-exoplayer-dash, which
    // ships with video_player_android and is on the classpath. libmpv's DASH
    // support depends on how ffmpeg was configured in the build, and media_kit
    // makes no guarantee about it; a manifest it cannot demux fails as a blank
    // player rather than as an unsupported format, which is indistinguishable
    // from a dead channel.
    //
    // This is the same reasoning as the DRM branch above, and the same reason
    // it overrides a preference: the engine setting is a choice between two
    // players that can both play the stream, and here only one can.
    if (formatHint == vp.VideoFormat.dash && !isDesktopPlatform) {
      return _NativeController(
        vp.VideoPlayerController.networkUrl(
          url,
          httpHeaders: httpHeaders,
          formatHint: formatHint,
          videoPlayerOptions: videoPlayerOptions,
        ),
      );
    }
    // media_kit on desktop unconditionally (no native backend there); on
    // Android only when the user asked for it. PlayerEngine.external never
    // reaches here — the player page hands off before building a controller —
    // but if it somehow does, falling through to the native backend is the
    // safe answer, not a crash.
    if (!preferPlatform && _useMediaKit() && _mediaKitUsable()) {
      return _MediaKitController(
        _MediaKitSource.uri(url, httpHeaders, formatHint: formatHint),
      );
    }
    return _NativeController(
      vp.VideoPlayerController.networkUrl(
        url,
        httpHeaders: httpHeaders,
        formatHint: formatHint,
        videoPlayerOptions: videoPlayerOptions,
      ),
    );
  }

  factory PlayerController.file(
    File file, {
    vp.VideoPlayerOptions? videoPlayerOptions,
    bool preferPlatform = false,
  }) {
    if (!preferPlatform && _useMediaKit() && _mediaKitUsable()) {
      return _MediaKitController(_MediaKitSource.path(file.path));
    }
    return _NativeController(
      vp.VideoPlayerController.file(
        file,
        videoPlayerOptions: videoPlayerOptions,
      ),
    );
  }

  Future<void> initialize();
  Future<void> play();
  Future<void> pause();
  Future<void> seekTo(Duration position);
  Future<void> setPlaybackSpeed(double speed);
  Future<void> setVolume(double volume);
  Future<void> setLooping(bool looping);

  bool get letterboxesInternally;

  /// Whether this backend can enumerate and switch audio tracks at all.
  ///
  /// False for `video_player`: ExoPlayer has track selection internally but the
  /// plugin exposes no API for it, so the UI must hide or disable the control
  /// rather than offer one that silently does nothing.
  bool get supportsAudioTracks => false;

  /// Selectable audio tracks, empty when unsupported or when the media has a
  /// single track. Only meaningful after [initialize] has completed.
  List<PlayerAudioTrack> get audioTracks => const <PlayerAudioTrack>[];

  /// [PlayerAudioTrack.id] of the track currently being decoded, if known.
  String? get activeAudioTrackId => null;

  /// No-op on backends where [supportsAudioTracks] is false.
  Future<void> setAudioTrack(String id) async {}

  /// Whether this backend can enumerate and switch VIDEO renditions.
  ///
  /// False for `video_player` for the same reason as audio: ExoPlayer selects
  /// HLS variants internally and the plugin exposes no API for it. There,
  /// adaptive selection is the behaviour and there is no list to offer — which
  /// is a different thing from having no choice, and the UI should say so by
  /// omitting the control rather than showing an empty one.
  bool get supportsVideoTracks => false;

  /// Selectable video renditions, empty when unsupported or when the stream
  /// carries a single one. Only meaningful after [initialize] has completed.
  List<PlayerVideoTrack> get videoTracks => const <PlayerVideoTrack>[];

  /// [PlayerVideoTrack.id] of the rendition being decoded, if known. `auto`
  /// while the engine is choosing for itself.
  String? get activeVideoTrackId => null;

  /// No-op on backends where [supportsVideoTracks] is false.
  Future<void> setVideoTrack(String id) async {}

  /// Whether this backend can list and switch the subtitle tracks carried in
  /// the stream itself — an MKV's text tracks, an HLS master's subtitle
  /// renditions.
  ///
  /// libmpv only. The platform player neither lists nor draws them.
  bool get supportsSubtitleTracks => false;

  /// The stream's own subtitle tracks, empty when unsupported or when it
  /// carries none. Only meaningful after [initialize] has completed.
  List<PlayerSubtitleTrack> get subtitleTracks => const <PlayerSubtitleTrack>[];

  /// [PlayerSubtitleTrack.id] of the track being read, or null when none is.
  String? get activeSubtitleTrackId => null;

  /// Picks one of [subtitleTracks]; [PlayerSubtitleTrack.off] turns them off.
  Future<void> setSubtitleTrack(String id) async {}

  /// The chosen stream track's current line, empty between lines.
  ///
  /// The backend does not draw it: the player page does, in the viewer's
  /// subtitle style, the same way it draws a downloaded subtitle file.
  ValueListenable<String> get embeddedSubtitleText => _noEmbeddedText;

  /// Whether this backend can adjust the picture while playing.
  ///
  /// libmpv only. The platform player exposes no runtime video equalizer at
  /// all, so the UI hides the control rather than offering a menu that silently
  /// does nothing — the same rule the audio-track control follows, and for the
  /// same reason: a setting that appears to work and does not is worse than an
  /// absent one, because the viewer concludes the app is broken rather than
  /// that the feature is unavailable.
  bool get supportsColorProfile => false;

  /// Applies [profile], or restores the untouched picture for a neutral one.
  Future<void> setColorProfile(ColorProfile profile) async {}

  /// Whether this backend can run GLSL shaders over the video.
  ///
  /// libmpv only, and the same rule as everywhere else in this class: a
  /// backend that cannot do it says so, and the UI removes the control rather
  /// than offering one that silently does nothing.
  bool get supportsShaders => false;

  /// Runs [paths] as the shader chain, in order. An empty list clears it.
  ///
  /// Paths, not names: they are handed to mpv and must already exist on disk.
  Future<void> setShaders(List<String> paths) async {}

  /// The frame on screen right now, as JPEG bytes, or null.
  ///
  /// Null on backends that cannot do it, and the UI hides the control rather
  /// than offering a share button that produces nothing. `video_player` has no
  /// frame-grab API at all — the pixels live in a platform texture the Dart
  /// side never sees.
  Future<Uint8List?> grabFrame() async => null;

  Widget buildView({BoxFit fit = BoxFit.contain});

  /// Fires when [initialize], still running, has handed the stream to another
  /// backend — libmpv giving way to the platform player.
  ///
  /// For a caller that bounds the start (see `withinStartupBudget`): the
  /// engine that takes over has to open the stream from scratch, and timing it
  /// from when the first one began would fail it for the first one's delay.
  Stream<void> get backendSwitches => const Stream<void>.empty();

  @override
  Future<void> dispose();
}

/// Native-language names for the codes that actually turn up in stream
/// metadata, keyed by both ISO 639-1 and 639-2 because muxers disagree about
/// which to write. Native rather than English on purpose: this list is how a
/// user picks a dub, and someone hunting for the Russian track scans for
/// "Русский", not "Russian".
///
/// A code that is missing here falls back to its own uppercase form, which is
/// still strictly better than the raw mpv track id.
const Map<String, String> _languageNames = <String, String>{
  'en': 'English',
  'eng': 'English',
  'ru': 'Русский',
  'rus': 'Русский',
  'uz': 'O\'zbekcha',
  'uzb': 'O\'zbekcha',
  'tr': 'Türkçe',
  'tur': 'Türkçe',
  'es': 'Español',
  'spa': 'Español',
  'fr': 'Français',
  'fra': 'Français',
  'fre': 'Français',
  'de': 'Deutsch',
  'deu': 'Deutsch',
  'ger': 'Deutsch',
  'it': 'Italiano',
  'ita': 'Italiano',
  'pt': 'Português',
  'por': 'Português',
  'ja': '日本語',
  'jpn': '日本語',
  'ko': '한국어',
  'kor': '한국어',
  'zh': '中文',
  'zho': '中文',
  'chi': '中文',
  'hi': 'हिन्दी',
  'hin': 'हिन्दी',
  'ar': 'العربية',
  'ara': 'العربية',
  'fa': 'فارسی',
  'fas': 'فارسی',
  'per': 'فارسی',
  'he': 'עברית',
  'heb': 'עברית',
  'th': 'ไทย',
  'tha': 'ไทย',
  'vi': 'Tiếng Việt',
  'vie': 'Tiếng Việt',
  'id': 'Bahasa Indonesia',
  'ind': 'Bahasa Indonesia',
  'ms': 'Bahasa Melayu',
  'msa': 'Bahasa Melayu',
  'may': 'Bahasa Melayu',
  'pl': 'Polski',
  'pol': 'Polski',
  'nl': 'Nederlands',
  'nld': 'Nederlands',
  'dut': 'Nederlands',
  'sv': 'Svenska',
  'swe': 'Svenska',
  'no': 'Norsk',
  'nor': 'Norsk',
  'da': 'Dansk',
  'dan': 'Dansk',
  'fi': 'Suomi',
  'fin': 'Suomi',
  'cs': 'Čeština',
  'ces': 'Čeština',
  'cze': 'Čeština',
  'sk': 'Slovenčina',
  'slk': 'Slovenčina',
  'slo': 'Slovenčina',
  'uk': 'Українська',
  'ukr': 'Українська',
  'ro': 'Română',
  'ron': 'Română',
  'rum': 'Română',
  'hu': 'Magyar',
  'hun': 'Magyar',
  'el': 'Ελληνικά',
  'ell': 'Ελληνικά',
  'gre': 'Ελληνικά',
  'bg': 'Български',
  'bul': 'Български',
  'sr': 'Српски',
  'srp': 'Српски',
  'hr': 'Hrvatski',
  'hrv': 'Hrvatski',
  'kk': 'Қазақша',
  'kaz': 'Қазақша',
  'ky': 'Кыргызча',
  'kir': 'Кыргызча',
  'tg': 'Тоҷикӣ',
  'tgk': 'Тоҷикӣ',
  'tk': 'Türkmençe',
  'tuk': 'Türkmençe',
  'az': 'Azərbaycan',
  'aze': 'Azərbaycan',
  'bn': 'বাংলা',
  'ben': 'বাংলা',
  'ta': 'தமிழ்',
  'tam': 'தமிழ்',
  'te': 'తెలుగు',
  'tel': 'తెలుగు',
};

/// One selectable audio track, flattened out of whatever the backend calls it.
class PlayerAudioTrack {
  const PlayerAudioTrack({
    required this.id,
    required this.title,
    required this.language,
    this.ordinal = 1,
  });

  /// Backend-specific handle passed straight back to [setAudioTrack].
  final String id;
  final String? title;
  final String? language;

  /// 1-based position in the track list. Only used to build a label when the
  /// stream carries no usable metadata at all — several providers (vidapi
  /// among them) mux HLS audio renditions with neither NAME nor LANGUAGE, and
  /// mpv then reports nothing but the numeric track id.
  final int ordinal;

  /// True when the container actually told us something about this track.
  /// False means [label] is a positional guess, and the UI should say
  /// "Audio 1" in the user's language rather than pretend it knows more.
  bool get hasMetadata {
    final t = title?.trim();
    final l = language?.trim();
    return (t != null && t.isNotEmpty) || (l != null && l.isNotEmpty);
  }

  /// Resolved native language name, e.g. `rus` → `Русский`. Null when the
  /// track carries no language code.
  String? get languageName {
    final l = language?.trim().toLowerCase();
    if (l == null || l.isEmpty) return null;
    // Strip region/variant suffixes: `pt-BR`, `en_US`, `rus (dub)` → base code.
    final base = l.split(RegExp(r'[-_ ]')).first;
    return _languageNames[base] ?? base.toUpperCase();
  }

  /// Human-readable label, best-effort: mpv fills `title` and `language`
  /// inconsistently depending on the container, so fall back through both
  /// before giving up and using the position.
  ///
  /// Deliberately never returns the bare [id] — a sheet listing "1" and "2" is
  /// indistinguishable from a bug.
  String get label {
    final t = title?.trim();
    final lang = languageName;
    if (t != null && t.isNotEmpty && lang != null) {
      // Don't repeat "Русский (Русский)" when the muxer wrote the language
      // into the title as well.
      if (t.toLowerCase() == lang.toLowerCase()) return t;
      return '$t ($lang)';
    }
    if (t != null && t.isNotEmpty) return t;
    if (lang != null) return lang;
    return 'Audio $ordinal';
  }
}

final ValueNotifier<String> _noEmbeddedText = ValueNotifier<String>('');

/// One subtitle track inside the stream.
class PlayerSubtitleTrack extends PlayerAudioTrack {
  const PlayerSubtitleTrack({
    required super.id,
    required super.title,
    required super.language,
    super.ordinal,
  });

  /// The id that turns the stream's subtitles off.
  static const String off = 'no';

  @override
  String get label => hasMetadata ? super.label : 'Subtitle $ordinal';
}

/// Whether a controller built right now should use the libmpv backend.
bool _useMediaKit() =>
    !isAndroidEmulator && resolvePlayerEngine() == PlayerEngine.mediaKit;

/// media_kit needs its native side initialised exactly once before the first
/// [mk.Player]. `main()` does this eagerly on desktop; on Android the engine is
/// opt-in, so it is done by [warmUpPlayerEngine] at startup when the user has
/// actually selected media_kit, and lazily by the first controller otherwise.
bool _mediaKitReady = false;

/// Initialise libmpv if it has not been, and report whether it can be used.
///
/// Checked before choosing the backend rather than inside the controller's
/// constructor, because by then the choice is already made and a throw there
/// leaves the caller holding a controller that will never initialise. Now the
/// engine that cannot start is never handed out in the first place.
///
/// Since media_kit became the default this is no longer the opt-in path it was
/// built as: a device without a loadable libmpv used to be someone who had
/// turned it on and could turn it off again, and is now anyone. A caught throw
/// costs the decoration; an uncaught one costs every playback.
bool _mediaKitUsable() {
  if (_mediaKitReady) return !_mediaKitFailed;
  _mediaKitReady = true;
  try {
    mk.MediaKit.ensureInitialized();
    return true;
  } catch (e, stack) {
    _mediaKitFailed = true;
    markMediaKitUnavailable();
    debugPrint('[player] libmpv did not load, using the platform player: $e');
    debugPrintStack(stackTrace: stack);
    return false;
  }
}

bool _mediaKitFailed = false;

/// How long to wait for libmpv to put a decoded frame on the screen.
///
/// Generous on purpose. A false positive here demotes a working engine for the
/// rest of the session, which is a worse outcome than a few seconds spent once
/// on a device that is about to show a black screen either way.
const Duration _firstFrameTimeout = Duration(seconds: 5);

/// How long libmpv may hold a stream whose video track it has already found
/// without producing a picture, before the platform player is tried instead.
///
/// The track list exists only once the container has been read, so this is
/// not a slow network: it is a decoder that has stalled. It used to be caught
/// only by the 30 s readiness wait, which a player page that moves to the next
/// server after 25 s (see `startupBudget`) never reaches.
const Duration _pictureTimeout = Duration(seconds: 12);

/// How long a playing stream may stall on a held `tcp:` error before it is
/// reported. Above `network-timeout` (see [_MediaKitController.initialize]),
/// so ffmpeg's own reconnect gets its go first.
const Duration _networkGrace = Duration(seconds: 25);

/// Set as the error when libmpv plays but cannot display.
///
/// A sentinel rather than prose: the player matches on it to rebuild with the
/// platform backend, and a human-readable string would be one careless edit
/// away from silently breaking that.
const String kVideoOutputUnavailable = 'sozo:no-video-output';

/// Loads libmpv ahead of the first playback, but only when media_kit is the
/// selected engine.
///
/// `MediaKit.ensureInitialized()` is synchronous and pulls a large native
/// library onto the platform thread. Left to the lazy path in
/// [_MediaKitController]'s constructor it runs while the player page is opening
/// — the user taps play and the UI locks up for the load. Doing it at startup
/// moves that cost to a moment where nothing is waiting on it.
///
/// Conditional on the resolved engine: someone who picked the platform player,
/// and every iOS install, never pays the memory or load cost of a backend they
/// are not using. Someone who switches mid-session gets the lazy path once,
/// which is why [_mediaKitUsable] does the work rather than this.
///
/// Doing it here also means a device where libmpv will not load finds out at
/// startup, with nothing waiting on the answer, instead of at the moment
/// someone taps play.
Future<void> warmUpPlayerEngine() async {
  if (kIsWeb) return;
  if (!_useMediaKit()) return;
  _mediaKitUsable();
}

class _NativeController extends PlayerController {
  _NativeController(this._inner) {
    _inner.addListener(_sync);
  }

  final vp.VideoPlayerController _inner;
  bool _disposed = false;
  Future<void>? _disposal;

  void _sync() {
    if (!_disposed) value = _inner.value;
  }

  @override
  Future<void> initialize() async {
    await _inner.initialize();
    if (!_disposed) value = _inner.value;
  }

  @override
  Future<void> play() => _inner.play();

  @override
  Future<void> pause() => _inner.pause();

  @override
  Future<void> seekTo(Duration position) => _inner.seekTo(position);

  @override
  Future<void> setPlaybackSpeed(double speed) => _inner.setPlaybackSpeed(speed);

  @override
  Future<void> setVolume(double volume) => _inner.setVolume(volume);

  @override
  Future<void> setLooping(bool looping) => _inner.setLooping(looping);

  @override
  bool get letterboxesInternally => false;

  @override
  Widget buildView({BoxFit fit = BoxFit.contain}) => vp.VideoPlayer(_inner);

  @override
  Future<void> dispose() {
    final pending = _disposal;
    if (pending != null) return pending;
    _disposed = true;
    super.dispose();
    return _disposal = _disposeOnce();
  }

  Future<void> _disposeOnce() async {
    _inner.removeListener(_sync);
    await _inner.dispose();
  }
}

class _MediaKitSource {
  _MediaKitSource.uri(Uri uri, this.headers, {this.formatHint})
    : source = uri.isScheme('file') ? uri.toFilePath() : uri.toString(),
      uri = uri.isScheme('file') ? null : uri;
  _MediaKitSource.path(this.source)
    : headers = const <String, String>{},
      formatHint = null,
      uri = null;

  /// What libmpv is given: a URL string, or a path for a local file.
  final String source;

  /// The network URL, or null for a local file. Kept because libmpv takes both
  /// as one string and the platform backend does not — it has a separate
  /// constructor for each, and by then the distinction is gone.
  final Uri? uri;
  final vp.VideoFormat? formatHint;

  final Map<String, String> headers;
}

class _MediaKitController extends PlayerController {
  _MediaKitController(this._src) {
    // Must precede the first Player(): a field initializer would run before
    // this body, so _player is deliberately late. Both factories check this
    // first, so by here it is a cheap already-done flag — kept because a
    // controller built any other way still has to initialise before Player().
    _mediaKitUsable();
    _player = mk.Player(
      configuration: mk.PlayerConfiguration(
        // demuxer-max-bytes and demuxer-max-back-bytes: media_kit sets both
        // from this. A seek inside the demuxer cache is answered from memory
        // (demuxer-seekable-cache is on whenever the cache is, and media_kit
        // turns the cache on); one outside it waits for a whole HLS segment
        // to download before a frame can be decoded. media_kit's 32 MiB held
        // only ~35–45 s of a 1080p stream either side of the playhead, so
        // most swipes missed it. Not on TV boxes, the devices short on RAM.
        bufferSize: isTvPlatform ? 32 * 1024 * 1024 : 64 * 1024 * 1024,
      ),
    );
    // No androidAttachSurfaceAfterVideoParameters here, deliberately.
    //
    // Setting it to false does fix the black first frame — the picture was
    // black until the first seek because the surface was attached only after
    // mpv reported the video's parameters, and seeking was simply the first
    // event that forced a redraw. But it also moves when mpv's render context
    // is created relative to the Dart callbacks media_kit registers, and the
    // app started aborting on teardown: SIGABRT on the mpv core thread,
    // "Callback invoked after it has been deleted".
    //
    // A black first frame is an annoyance. A crash is not, so this stays on the
    // library's default until the black frame has a fix that does not touch
    // native lifetimes.
    _videoController = mkv.VideoController(_player);
  }

  final _MediaKitSource _src;

  /// The platform backend, once libmpv has proved it cannot display.
  ///
  /// Swapped in rather than reported upward. Everything above this class asked
  /// for "a controller for this URL" and does not care which library provides
  /// it; making the player page handle an engine that half-works would spread
  /// one library's quirk across the whole feature.
  PlayerController? _fallback;

  late final mk.Player _player;
  late final mkv.VideoController _videoController;
  List<PlayerAudioTrack> _audioTracks = const <PlayerAudioTrack>[];
  String? _activeAudioTrackId;
  List<PlayerVideoTrack> _videoTracks = const <PlayerVideoTrack>[];
  List<PlayerSubtitleTrack> _subtitleTracks = const <PlayerSubtitleTrack>[];
  String? _activeSubtitleTrackId;
  final ValueNotifier<String> _embeddedText = ValueNotifier<String>('');
  String? _activeVideoTrackId;
  final List<StreamSubscription<dynamic>> _subs =
      <StreamSubscription<dynamic>>[];
  bool _disposed = false;
  Future<void>? _mpvDisposal;
  Future<void>? _disposal;
  final _closed = Completer<void>();
  String? _error;

  /// A `tcp:` error ffmpeg logged that has not (yet) been judged fatal. See
  /// [_holdNetworkError].
  String? _heldNetworkError;

  /// The last `tcp:` error since this stream opened. Judging a stall
  /// recovered forgets [_heldNetworkError], but the file can still end early
  /// on it once the cache runs dry.
  String? _lastNetworkError;
  Duration _stalledAt = Duration.zero;
  Timer? _networkGraceTimer;
  final StreamController<void> _backendSwitches =
      StreamController<void>.broadcast(sync: true);

  @override
  Stream<void> get backendSwitches => _backendSwitches.stream;

  /// How often mpv's playhead reaches listeners.
  ///
  /// mpv reports `time-pos` on every displayed frame, 24 to 60 times a
  /// second, and each report rebuilt the seek row, the scrub preview, the
  /// subtitle layer and the page listener. video_player polls ExoPlayer every
  /// 100 ms, so this is parity with the platform engine, not a loss: at 100 ms
  /// the thumb of an episode moves well under a pixel per tick, and
  /// downloaded subtitles are timed exactly as they are on ExoPlayer.
  static const Duration _positionInterval = Duration(milliseconds: 100);

  /// How long after a seek a far-off `time-pos` is treated as one that was
  /// already on its way when the seek was issued, and how far off counts.
  static const Duration _seekLandingWindow = Duration(seconds: 2);
  static const Duration _seekLandingSlack = Duration(milliseconds: 1500);

  final Stopwatch _sincePosition = Stopwatch();
  final Stopwatch _sinceSeek = Stopwatch();
  Duration? _heldPosition;
  Duration? _seekTarget;
  Timer? _positionFlush;

  void _onPosition(Duration p) {
    final target = _seekTarget;
    if (target != null) {
      // Showing a pre-seek tick would snap the thumb back to where the
      // finger left it, then forward again.
      final stale = (p - target).abs() > _seekLandingSlack;
      if (stale && _sinceSeek.elapsed < _seekLandingWindow) return;
      _seekTarget = null;
    }
    if (_sincePosition.isRunning &&
        _sincePosition.elapsed < _positionInterval) {
      _heldPosition = p;
      // Trailing edge, so the last position before a pause or the end of
      // the file still lands.
      _positionFlush ??= Timer(_positionInterval - _sincePosition.elapsed, () {
        _positionFlush = null;
        final held = _heldPosition;
        if (held != null) _flushPosition(held);
      });
      return;
    }
    _flushPosition(p);
  }

  void _flushPosition(Duration p) {
    _positionFlush?.cancel();
    _positionFlush = null;
    _heldPosition = null;
    _sincePosition
      ..reset()
      ..start();
    _emit(value.copyWith(position: p));
  }

  @override
  Future<void> initialize() async {
    _wire();
    // Which rendition of an HLS master mpv opens on. It has no adaptive
    // switching afterwards, and left alone it always took the top one —
    // Data saver and a pinned 480p both started at 1080p first.
    final platform = _player.platform;
    if (platform is mk.NativePlayer) {
      try {
        await platform.setProperty(
          'hls-bitrate',
          PlayerController.mpvHlsBitrate,
        );
      } catch (e) {
        debugPrint('[player] hls-bitrate not applied: $e');
      }
      // media_kit creates every Player with hr-seek=yes and
      // hr-seek-framedrop=no. hr-seek stays: every seek here is an absolute
      // one, and a keyframe seek on a stream with 6–10 s GOPs can land a
      // +10 s skip back where it started. framedrop goes back to mpv's own
      // default: the frames between the keyframe and the target are thrown
      // away anyway, and with it off the decoder had to decode every one of
      // them first — the freeze after each swipe and seek-bar release. Safe
      // here because nothing sets a --vf filter (colour profiles and shaders
      // act in the VO), the one case mpv's manual says framedrop can skip
      // the target frame.
      try {
        await platform.setProperty('hr-seek-framedrop', 'yes');
      } catch (e) {
        debugPrint('[player] hr-seek-framedrop not applied: $e');
      }
      // media_kit opens every Player with network-timeout=5 (media_kit 1.2.6,
      // player/native/player/real.dart). On mobile data a five-second stall is
      // routine: log_045e01 has mp4upload starts that died 5.3 s after
      // "loading url", and log_2e4886 a vidapi episode killed a minute in by
      // "tcp: ffurl_read returned 0xffffff92" — ETIMEDOUT, i.e. that timer.
      // mpv's own default is 60; 15 survives a handover and still turns a
      // dead host into an error well inside the page's startup budget.
      //
      // The reconnect flags are for progressive files (mp4upload, playmogo):
      // a dropped connection resumes at its byte offset instead of ending the
      // stream, and a failed connect is tried again a couple of times.
      // reconnect_delay_max=5 caps that at about three attempts. HLS segments
      // are retried by seg_max_retry=5, which media_kit puts in
      // demuxer-lavf-o; that property is deliberately not set here, because
      // setting it replaces media_kit's whole list, protocol_whitelist
      // included.
      try {
        await platform.setProperty('network-timeout', '15');
        await platform.setProperty(
          'stream-lavf-o',
          'reconnect=1,reconnect_streamed=1,'
              'reconnect_on_network_error=1,reconnect_delay_max=5',
        );
      } catch (e) {
        debugPrint('[player] network options not applied: $e');
      }
    }
    final recovered = await initializeWithDecoderFallback(
      initialize: () async {
        await _player.open(
          mk.Media(
            _src.source,
            httpHeaders: _src.headers.isEmpty ? null : _src.headers,
          ),
          play: false,
        );
        await _awaitReady();
      },
      canFallback: () => !_disposed && !kIsWeb && Platform.isAndroid,
      fallback: _swapToPlatformBackend,
    );
    if (recovered) return;
    if (_disposed) return;
    final w = _player.state.width ?? 0;
    final h = _player.state.height ?? 0;

    // This detects a missing surface, not proof of visible pixels. On Android
    // media_kit_video 1.3.1 completes this future on SetSurfaceSize. Emulator
    // software-rendering can still display black, so emulator playback is
    // routed to the platform backend before constructing this controller.
    if (w > 0 && h > 0 && !await _surfaceBecomesAvailable()) {
      if (_disposed) return;
      // A codec/stream can fail while other MediaKit videos still work. Do not
      // silently change the user's engine for every later title in the session.
      if (kIsWeb || !Platform.isAndroid) {
        throw StateError(kVideoOutputUnavailable);
      }
      debugPrint(
        '[player] libmpv surface unavailable — trying platform playback for this stream',
      );
      await _swapToPlatformBackend();
      return;
    }

    // The surface exists; the texture showing it may not yet. media_kit_video
    // 1.3.1 attaches mpv to the Android surface (--wid) only when the native
    // side answers SetSurfaceSize with VideoOutput.Resize, and its listener for
    // that ends in `player.seek(Duration.zero)`
    // (android_video_controller/real.dart, widListener) — the library's own
    // repaint. Returning before it ran left two gaps: the page's resume seek
    // could land first and be undone by the library's seek to 0:00, and a
    // texture that never arrived meant audio under a black rectangle with
    // nothing reporting it.
    //
    // So: wait, bounded, for the texture; let the library's seek go first;
    // then repaint where we are. Ordinary player commands only — nothing here
    // moves when the render context is created or torn down, which is what
    // androidAttachSurfaceAfterVideoParameters=false broke (see constructor).
    if (!kIsWeb && Platform.isAndroid && w > 0 && h > 0) {
      final attached = await _repaintOnceAttached();
      if (_disposed) return;
      if (!attached) {
        debugPrint(
          '[player] libmpv texture never attached — trying platform playback',
        );
        await _swapToPlatformBackend();
        return;
      }
    }

    // Whatever ffmpeg complained about on the way in, the stream started.
    _heldNetworkError = null;
    value = value.copyWith(
      isInitialized: _error == null,
      duration: _player.state.duration,
      size: (w > 0 && h > 0) ? Size(w.toDouble(), h.toDouble()) : value.size,
      errorDescription: _error,
    );
  }

  /// Tear libmpv down and continue on the platform player.
  ///
  /// The viewer sees a slightly longer load, not an error — which is the right
  /// trade for a device where the alternative was a black rectangle that
  /// nothing reported as broken.
  Future<void> _swapToPlatformBackend() async {
    await _teardownMpv();
    if (_disposed) return;

    final replacement = _src.uri == null && _src.formatHint == null
        ? _NativeController(vp.VideoPlayerController.file(File(_src.source)))
        : _NativeController(
            vp.VideoPlayerController.networkUrl(
              _src.uri ?? Uri.file(_src.source),
              httpHeaders: _src.headers,
              formatHint: _src.formatHint,
            ),
          );
    _fallback = replacement;
    // Its value is this controller's value from here on, so the page's existing
    // listeners keep working without knowing anything changed.
    replacement.addListener(() {
      if (!_disposed) value = replacement.value;
    });
    if (!_backendSwitches.isClosed) _backendSwitches.add(null);
    await replacement.initialize();
    if (_disposed) {
      await replacement.dispose();
      return;
    }
    value = replacement.value;
  }

  /// Whether the plugin has made a video surface available.
  /// Android does not confirm that pixels were rendered (see initialize).
  Future<bool> _surfaceBecomesAvailable() async {
    try {
      await _videoController.waitUntilFirstFrameRendered.timeout(
        _firstFrameTimeout,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Waits for the video texture, then redraws the frame mpv is on.
  /// False when no texture arrived: audio would play under a black rectangle.
  Future<bool> _repaintOnceAttached() async {
    final id = _videoController.id;
    if (id.value == null) {
      final attached = Completer<void>();
      void onId() {
        if (id.value != null && !attached.isCompleted) attached.complete();
      }

      id.addListener(onId);
      try {
        await Future.any([
          attached.future,
          _closed.future,
        ]).timeout(_firstFrameTimeout, onTimeout: () {});
      } finally {
        id.removeListener(onId);
      }
    }
    if (_disposed) return true;
    if (id.value == null) return false;
    // media_kit's surface listener runs under its own lock and ends in
    // seek(0). It is a handful of property writes, so a short wait puts this
    // seek after it rather than before, and the page's resume seek after both.
    // The lock is not public (AndroidVideoController is not exported), so this
    // is ordering by time, not by handshake.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (_disposed) return true;
    // Not on a live or unknown-length stream, where a seek means rejoining
    // the edge rather than redrawing a frame.
    if (_player.state.duration <= Duration.zero) return true;
    try {
      await _player.seek(_player.state.position);
    } catch (e) {
      debugPrint('[player] repaint seek failed: $e');
    }
    return true;
  }

  /// Holds a `tcp:` error rather than reporting it.
  ///
  /// media_kit turns every error-level line ffmpeg logs under `tcp:` into an
  /// error event (media_kit 1.2.6 real.dart, the log-message handler). Most
  /// are stalls the HLS demuxer re-requests and the http layer reconnects
  /// past, and reported at once one of them ended the episode: log_2e4886,
  /// 21:10:11, a minute into a vidapi stream that was playing.
  ///
  /// Before the first frame the start's own bounds judge it: a host that never
  /// answers ends in mpv's "Failed to open", reported as before, or in the
  /// readiness timeout, which then reports the held error (see
  /// [_awaitReady]) rather than blaming a decoder. Once playing, it is
  /// reported only if playback is still stuck after [_networkGrace].
  void _holdNetworkError(String e) {
    _heldNetworkError = e;
    _lastNetworkError = e;
    if (!value.isInitialized) return;
    if (_networkGraceTimer?.isActive ?? false) return;
    _stalledAt = _player.state.position;
    _networkGraceTimer = Timer(_networkGrace, _judgeNetworkStall);
  }

  void _judgeNetworkStall() {
    _networkGraceTimer?.cancel();
    _networkGraceTimer = null;
    final held = _heldNetworkError;
    if (_disposed || _fallback != null || held == null) return;
    final state = _player.state;
    switch (judgeNetworkStall(
      stalledAt: _stalledAt,
      position: state.position,
      playing: state.playing,
      completed: state.completed,
      duration: state.duration,
    )) {
      case NetworkStall.recovered:
        _heldNetworkError = null;
      case NetworkStall.fatal:
        _heldNetworkError = null;
        _reportError(held);
      case NetworkStall.undecided:
        // Paused where it stalled: look again later rather than dropping it,
        // or a viewer who paused through the stall would come back to a
        // spinner nothing reports.
        _networkGraceTimer = Timer(_networkGrace, _judgeNetworkStall);
    }
  }

  void _reportError(String e) {
    _error = e;
    _emit(value.copyWith(errorDescription: e));
  }

  void _wire() {
    _subs
      ..add(_player.stream.position.listen(_onPosition))
      ..add(
        _player.stream.duration.listen(
          (d) => _emit(value.copyWith(duration: d)),
        ),
      )
      ..add(
        _player.stream.playing.listen(
          (p) => _emit(value.copyWith(isPlaying: p)),
        ),
      )
      ..add(
        _player.stream.buffering.listen(
          (b) => _emit(value.copyWith(isBuffering: b)),
        ),
      )
      ..add(
        _player.stream.completed.listen((c) {
          // An end of file right after a network error may be the connection
          // ending the file early rather than the episode ending: judge it now
          // instead of after the grace.
          if (c && value.isInitialized) {
            _heldNetworkError ??= _lastNetworkError;
            if (_heldNetworkError != null) _judgeNetworkStall();
          }
          _emit(value.copyWith(isCompleted: c));
        }),
      )
      ..add(_player.stream.width.listen((_) => _emitSize()))
      ..add(_player.stream.height.listen((_) => _emitSize()))
      // Both halves. This subscription existed and read only `t.audio`, so
      // every HLS rendition mpv reported was thrown away and the quality list
      // had nothing to offer but the provider's separate mirrors.
      ..add(
        _player.stream.tracks.listen((t) {
          _syncAudioTracks(t.audio);
          _syncVideoTracks(t.video);
          _syncSubtitleTracks(t.subtitle);
        }),
      )
      ..add(
        _player.stream.track.listen((t) {
          _activeAudioTrackId = t.audio.id;
          _activeVideoTrackId = t.video.id;
          final sid = t.subtitle.id;
          _activeSubtitleTrackId = sid == 'no' || sid == 'auto' ? null : sid;
        }),
      )
      // mpv's current subtitle line. Drawn by the page in the viewer's style
      // rather than by media_kit's own view, which has a fixed one — so the
      // size, colour and position settings reach these tracks too.
      ..add(
        _player.stream.subtitle.listen((lines) {
          _embeddedText.value = lines
              .map((l) => l.trim())
              .where((l) => l.isNotEmpty)
              .join('\n');
        }),
      )
      ..add(
        _player.stream.error.listen((e) {
          // A live stream has no length and no cache to ride out a stall
          // on: once it plays, a dropped connection is reported at once so
          // the page reconnects instead of showing a frozen picture.
          if (e.startsWith('tcp:') &&
              (!value.isInitialized ||
                  _player.state.duration > Duration.zero)) {
            _holdNetworkError(e);
            return;
          }
          _reportError(e);
        }),
      );
  }

  /// mpv always reports a `no` (disabled) and an `auto` pseudo-track. Neither is
  /// a real choice for "which dub am I listening to", so drop them and only
  /// surface the control when a genuine alternative exists.
  static bool _sameTracks(List<PlayerAudioTrack> a, List<PlayerAudioTrack> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].title != b[i].title ||
          a[i].language != b[i].language) {
        return false;
      }
    }
    return true;
  }

  /// Keeps [videoTracks] in step with mpv.
  ///
  /// `no` is dropped — it is mpv's "video off" entry and means nothing in a
  /// quality list. `auto` is KEPT, unlike the audio side: it is the default and
  /// the only way back to adaptive once a rendition has been pinned.
  ///
  /// A single real rendition is reported as none at all. One entry beside Auto
  /// is not a choice, and a quality control that opens onto one row reads as
  /// broken.
  void _syncVideoTracks(List<mk.VideoTrack> tracks) {
    final filtered = tracks.where((t) => t.id != 'no').toList();
    final real = <PlayerVideoTrack>[
      for (var i = 0; i < filtered.length; i++)
        PlayerVideoTrack(
          id: filtered[i].id,
          width: filtered[i].w,
          height: filtered[i].h,
          bitrate: filtered[i].bitrate,
          codec: filtered[i].codec,
          ordinal: i + 1,
        ),
    ];
    final selectable = real.where((t) => !t.isAuto).length;
    final next = selectable > 1
        ? onePerHeight(sortVideoTracks(real))
        : const <PlayerVideoTrack>[];
    // Same lesson as the audio list: mpv probes in stages and reports the same
    // renditions twice, bare then described. Comparing by value rather than
    // length is what stops the sheet keeping the un-probed copy.
    if (_sameVideoTracks(next, _videoTracks)) return;
    _videoTracks = next;
    // Not `_emit(value.copyWith())`: VideoPlayerValue compares by value,
    // so an identical copy notified nobody and a paused player's sheet
    // never saw its new tracks.
    if (!_disposed) notifyListeners();
  }

  static bool _sameVideoTracks(
    List<PlayerVideoTrack> a,
    List<PlayerVideoTrack> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _syncSubtitleTracks(List<mk.SubtitleTrack> tracks) {
    final filtered = tracks
        .where((t) => t.id != 'no' && t.id != 'auto' && !t.uri && !t.data)
        .toList();
    final next = <PlayerSubtitleTrack>[
      for (var i = 0; i < filtered.length; i++)
        PlayerSubtitleTrack(
          id: filtered[i].id,
          title: filtered[i].title,
          language: filtered[i].language,
          ordinal: i + 1,
        ),
    ];
    if (_sameTracks(next, _subtitleTracks)) return;
    _subtitleTracks = next;
    // Not `_emit(value.copyWith())`: VideoPlayerValue compares by value,
    // so an identical copy notified nobody and a paused player's sheet
    // never saw its new tracks.
    if (!_disposed) notifyListeners();
  }

  void _syncAudioTracks(List<mk.AudioTrack> tracks) {
    final filtered = tracks
        .where((t) => t.id != 'no' && t.id != 'auto')
        .toList();
    final real = <PlayerAudioTrack>[
      for (var i = 0; i < filtered.length; i++)
        PlayerAudioTrack(
          id: filtered[i].id,
          title: filtered[i].title,
          language: filtered[i].language,
          ordinal: i + 1,
        ),
    ];
    // Comparing only the count kept the first list mpv reported. It probes a stream in
    // stages, so the same two tracks arrive first as bare ids and again once their title
    // and language are known - identical length, different content - and the sheet was
    // left showing the un-probed version, which is why languages read as missing or wrong.
    if (_sameTracks(real, _audioTracks)) return;
    _audioTracks = real;
    // Nudge listeners so a sheet already on screen picks the new list up.
    // Not `_emit(value.copyWith())`: VideoPlayerValue compares by value,
    // so an identical copy notified nobody and a paused player's sheet
    // never saw its new tracks.
    if (!_disposed) notifyListeners();
  }

  void _emitSize() {
    final w = _player.state.width ?? 0;
    final h = _player.state.height ?? 0;
    if (w > 0 && h > 0) {
      _emit(value.copyWith(size: Size(w.toDouble(), h.toDouble())));
    }
  }

  void _emit(vp.VideoPlayerValue v) {
    if (_disposed) return;
    value = v;
  }

  Future<void> _awaitReady() async {
    try {
      await _awaitReadiness();
    } on TimeoutException {
      // A start that stalled on the network is the network's failure, not a
      // decoder's. Reported as a timeout it would hand the stream to the
      // platform player (initializeWithDecoderFallback) to fetch the same
      // unreachable bytes; reported as what ffmpeg said, the page walks on to
      // another server.
      final held = _heldNetworkError;
      if (held != null) throw StateError(held);
      rethrow;
    }
  }

  Future<void> _awaitReadiness() => awaitPlaybackReadiness(
    read: () => PlaybackReadiness(
      width: _player.state.width ?? 0,
      height: _player.state.height ?? 0,
      hasVideo: _player.state.tracks.video.any(
        (t) => t.id != 'no' && t.id != 'auto',
      ),
      hasAudio: _player.state.tracks.audio.any(
        (t) => t.id != 'no' && t.id != 'auto',
      ),
      duration: _player.state.duration,
      error: _error,
    ),
    signals: [
      _player.stream.duration,
      _player.stream.width,
      _player.stream.height,
      _player.stream.tracks,
      _player.stream.error,
    ],
    canceled: _closed.future,
    pictureTimeout: _pictureTimeout,
  );

  @override
  Future<void> play() => _fallback?.play() ?? _player.play();

  @override
  Future<void> pause() => _fallback?.pause() ?? _player.pause();

  @override
  Future<void> seekTo(Duration position) {
    final fallback = _fallback;
    if (fallback != null) return fallback.seekTo(position);
    // Shown now rather than when mpv's next time-pos arrives, as video_player
    // does for ExoPlayer: the seek bar lets go of the thumb on release, and
    // a second double-tap adds its step to the new position, not the old one.
    final duration = value.duration;
    final shown = position < Duration.zero
        ? Duration.zero
        : duration > Duration.zero && position > duration
        ? duration
        : position;
    _seekTarget = shown;
    _sinceSeek
      ..reset()
      ..start();
    _flushPosition(shown);
    return _player.seek(position);
  }

  @override
  Future<void> setPlaybackSpeed(double speed) =>
      _fallback?.setPlaybackSpeed(speed) ?? _player.setRate(speed);

  @override
  Future<void> setVolume(double volume) => _fallback != null
      ? _fallback!.setVolume(volume)
      : _player.setVolume((volume * 100).clamp(0.0, 100.0));

  @override
  Future<void> setLooping(bool looping) => _fallback != null
      ? _fallback!.setLooping(looping)
      : _player.setPlaylistMode(
          looping ? mk.PlaylistMode.single : mk.PlaylistMode.none,
        );

  @override
  bool get letterboxesInternally => _fallback?.letterboxesInternally ?? true;

  @override
  // False once swapped: the platform player cannot switch tracks, and the
  // control must disappear rather than sit there doing nothing.
  bool get supportsAudioTracks => _fallback?.supportsAudioTracks ?? true;

  /// True unless libmpv had to be swapped out mid-playback for the platform
  /// backend, which is a fallback that carries none of this.
  @override
  bool get supportsColorProfile => _fallback == null;

  @override
  bool get supportsShaders => _fallback == null;

  @override
  Future<Uint8List?> grabFrame() async {
    if (_fallback != null) return null;
    try {
      // Without subtitles: the point of sharing a frame is the frame, and a
      // burnt-in line of dialogue makes it somebody else's screenshot of a
      // moment rather than the moment.
      return await _player.screenshot(format: 'image/jpeg');
    } catch (e) {
      debugPrint('[player] could not grab a frame: $e');
      return null;
    }
  }

  @override
  Future<void> setShaders(List<String> paths) async {
    if (_fallback != null) return;
    final platform = _player.platform;
    if (platform is! mk.NativePlayer) return;
    try {
      if (paths.isEmpty) {
        // Cleared by setting the property empty rather than by leaving it —
        // switching a preset off has to actually remove the chain, and mpv
        // keeps whatever it was last given.
        await platform.setProperty('glsl-shaders', '');
        return;
      }
      // Separated by ':', which is what mpv's list properties take on every
      // platform this runs on. A path containing one would break the list, and
      // these are filenames this app chose, so none can.
      await platform.setProperty('glsl-shaders', paths.join(':'));
    } catch (e) {
      // An enhancement is never worth losing the episode over. A shader that
      // will not compile on this GPU should cost the sharpening, not playback.
      debugPrint('[player] shader chain not applied: $e');
    }
  }

  @override
  Future<void> setColorProfile(ColorProfile profile) async {
    if (_fallback != null) return;
    final platform = _player.platform;
    if (platform is! mk.NativePlayer) return;
    try {
      // One property at a time, because mpv has no combined call and a partial
      // application still leaves a coherent picture — the properties are
      // independent of one another.
      for (final entry in profile.properties.entries) {
        await platform.setProperty(entry.key, '${entry.value}');
      }
    } catch (e) {
      // A picture adjustment is never worth interrupting playback for. An
      // older libmpv missing one of these properties should cost that
      // property, not the episode.
      debugPrint('[player] colour profile ${profile.id} not applied: $e');
    }
  }

  @override
  List<PlayerAudioTrack> get audioTracks =>
      _fallback?.audioTracks ?? _audioTracks;

  @override
  String? get activeAudioTrackId => _fallback != null
      ? null
      : _activeAudioTrackId ?? _player.state.track.audio.id;

  @override
  @override
  bool get supportsVideoTracks => _fallback == null;

  @override
  List<PlayerVideoTrack> get videoTracks =>
      _fallback != null ? const <PlayerVideoTrack>[] : _videoTracks;

  @override
  String? get activeVideoTrackId =>
      _fallback != null ? null : _activeVideoTrackId;

  @override
  Future<void> setVideoTrack(String id) async {
    if (_fallback != null) return;
    final match = _player.state.tracks.video
        .where((t) => t.id == id)
        .cast<mk.VideoTrack?>()
        .firstWhere((_) => true, orElse: () => null);
    if (match == null) return;
    await _player.setVideoTrack(match);
    _activeVideoTrackId = id;
  }

  @override
  bool get supportsSubtitleTracks => _fallback == null;

  @override
  List<PlayerSubtitleTrack> get subtitleTracks =>
      _fallback != null ? const <PlayerSubtitleTrack>[] : _subtitleTracks;

  @override
  String? get activeSubtitleTrackId =>
      _fallback != null ? null : _activeSubtitleTrackId;

  @override
  ValueListenable<String> get embeddedSubtitleText =>
      _fallback != null ? _noEmbeddedText : _embeddedText;

  @override
  Future<void> setSubtitleTrack(String id) async {
    if (_fallback != null) return;
    if (id == PlayerSubtitleTrack.off) {
      await _player.setSubtitleTrack(mk.SubtitleTrack.no());
      _activeSubtitleTrackId = null;
      _embeddedText.value = '';
      return;
    }
    final match = _player.state.tracks.subtitle
        .where((t) => t.id == id)
        .cast<mk.SubtitleTrack?>()
        .firstWhere((_) => true, orElse: () => null);
    if (match == null) return;
    await _player.setSubtitleTrack(match);
    _activeSubtitleTrackId = id;
  }

  @override
  Future<void> setAudioTrack(String id) async {
    // The platform player has no track API at all, so there is nothing to
    // forward to. supportsAudioTracks already reports false once swapped, which
    // is what removes the control; this guard is for anything that asks anyway.
    if (_fallback != null) return;
    final match = _player.state.tracks.audio
        .where((t) => t.id == id)
        .cast<mk.AudioTrack?>()
        .firstWhere((_) => true, orElse: () => null);
    if (match == null) return;
    await _player.setAudioTrack(match);
    _activeAudioTrackId = id;
  }

  @override
  Widget buildView({BoxFit fit = BoxFit.contain}) =>
      // The surface, not just the controls: after a swap the mpv texture is a
      // dead black rectangle, and it is the thing the viewer is looking at.
      _fallback?.buildView(fit: fit) ??
      mkv.Video(
        controller: _videoController,
        fit: fit,
        fill: const Color(0xFF000000),
        controls: mkv.NoVideoControls,
        // The page draws the stream's subtitles itself, in the viewer's
        // style; media_kit's own view would draw them a second time in its
        // fixed one.
        subtitleViewConfiguration: const mkv.SubtitleViewConfiguration(
          visible: false,
        ),
      );

  @override
  Future<void> dispose() {
    final pending = _disposal;
    if (pending != null) return pending;
    _disposed = true;
    super.dispose();
    return _disposal = _disposeOnce();
  }

  Future<void> _disposeOnce() async {
    if (!_closed.isCompleted) _closed.complete();
    await _teardownMpv();
    await _backendSwitches.close();
    await _fallback?.dispose();
  }

  /// Release libmpv without ending this controller.
  ///
  /// Shared with [dispose] because the swap has to leave nothing of the old
  /// backend behind: an undisposed Player keeps decoding, and two backends on
  /// one stream is audio playing twice.
  Future<void> _teardownMpv() => _mpvDisposal ??= _releaseMpv();

  Future<void> _releaseMpv() async {
    // A held tick must not land in `value` after the swap has handed it to
    // the fallback.
    _positionFlush?.cancel();
    _positionFlush = null;
    // Nor a held network error judged against a player that is gone.
    _networkGraceTimer?.cancel();
    _networkGraceTimer = null;
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await _player.dispose();
  }
}
