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
import 'package:soplay/core/system/platform_utils.dart';
import 'package:video_player/video_player.dart' as vp;

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

  factory PlayerController.networkUrl(
    Uri url, {
    Map<String, String> httpHeaders = const <String, String>{},
    vp.VideoFormat? formatHint,
    vp.VideoPlayerOptions? videoPlayerOptions,
    DrmConfig? drm,
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
    if (_useMediaKit() && _mediaKitUsable()) {
      return _MediaKitController(_MediaKitSource.uri(url, httpHeaders));
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
  }) {
    if (_useMediaKit() && _mediaKitUsable()) {
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
  'en': 'English', 'eng': 'English',
  'ru': 'Русский', 'rus': 'Русский',
  'uz': 'O\'zbekcha', 'uzb': 'O\'zbekcha',
  'tr': 'Türkçe', 'tur': 'Türkçe',
  'es': 'Español', 'spa': 'Español',
  'fr': 'Français', 'fra': 'Français', 'fre': 'Français',
  'de': 'Deutsch', 'deu': 'Deutsch', 'ger': 'Deutsch',
  'it': 'Italiano', 'ita': 'Italiano',
  'pt': 'Português', 'por': 'Português',
  'ja': '日本語', 'jpn': '日本語',
  'ko': '한국어', 'kor': '한국어',
  'zh': '中文', 'zho': '中文', 'chi': '中文',
  'hi': 'हिन्दी', 'hin': 'हिन्दी',
  'ar': 'العربية', 'ara': 'العربية',
  'fa': 'فارسی', 'fas': 'فارسی', 'per': 'فارسی',
  'he': 'עברית', 'heb': 'עברית',
  'th': 'ไทย', 'tha': 'ไทย',
  'vi': 'Tiếng Việt', 'vie': 'Tiếng Việt',
  'id': 'Bahasa Indonesia', 'ind': 'Bahasa Indonesia',
  'ms': 'Bahasa Melayu', 'msa': 'Bahasa Melayu', 'may': 'Bahasa Melayu',
  'pl': 'Polski', 'pol': 'Polski',
  'nl': 'Nederlands', 'nld': 'Nederlands', 'dut': 'Nederlands',
  'sv': 'Svenska', 'swe': 'Svenska',
  'no': 'Norsk', 'nor': 'Norsk',
  'da': 'Dansk', 'dan': 'Dansk',
  'fi': 'Suomi', 'fin': 'Suomi',
  'cs': 'Čeština', 'ces': 'Čeština', 'cze': 'Čeština',
  'sk': 'Slovenčina', 'slk': 'Slovenčina', 'slo': 'Slovenčina',
  'uk': 'Українська', 'ukr': 'Українська',
  'ro': 'Română', 'ron': 'Română', 'rum': 'Română',
  'hu': 'Magyar', 'hun': 'Magyar',
  'el': 'Ελληνικά', 'ell': 'Ελληνικά', 'gre': 'Ελληνικά',
  'bg': 'Български', 'bul': 'Български',
  'sr': 'Српски', 'srp': 'Српски',
  'hr': 'Hrvatski', 'hrv': 'Hrvatski',
  'kk': 'Қазақша', 'kaz': 'Қазақша',
  'ky': 'Кыргызча', 'kir': 'Кыргызча',
  'tg': 'Тоҷикӣ', 'tgk': 'Тоҷикӣ',
  'tk': 'Türkmençe', 'tuk': 'Türkmençe',
  'az': 'Azərbaycan', 'aze': 'Azərbaycan',
  'bn': 'বাংলা', 'ben': 'বাংলা',
  'ta': 'தமிழ்', 'tam': 'தமிழ்',
  'te': 'తెలుగు', 'tel': 'తెలుగు',
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

/// Whether a controller built right now should use the libmpv backend.
bool _useMediaKit() => resolvePlayerEngine() == PlayerEngine.mediaKit;

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

  void _sync() {
    if (!_disposed) value = _inner.value;
  }

  @override
  Future<void> initialize() async {
    await _inner.initialize();
    value = _inner.value;
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
  Future<void> dispose() async {
    _disposed = true;
    _inner.removeListener(_sync);
    await _inner.dispose();
    super.dispose();
  }
}


class _MediaKitSource {
  _MediaKitSource.uri(Uri uri, this.headers)
      : source = uri.isScheme('file') ? uri.toFilePath() : uri.toString(),
        uri = uri.isScheme('file') ? null : uri;
  _MediaKitSource.path(this.source)
      : headers = const <String, String>{},
        uri = null;

  /// What libmpv is given: a URL string, or a path for a local file.
  final String source;

  /// The network URL, or null for a local file. Kept because libmpv takes both
  /// as one string and the platform backend does not — it has a separate
  /// constructor for each, and by then the distinction is gone.
  final Uri? uri;

  final Map<String, String> headers;
}

class _MediaKitController extends PlayerController {
  _MediaKitController(this._src) {
    // Must precede the first Player(): a field initializer would run before
    // this body, so _player is deliberately late. Both factories check this
    // first, so by here it is a cheap already-done flag — kept because a
    // controller built any other way still has to initialise before Player().
    _mediaKitUsable();
    _player = mk.Player();
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
  String? _activeVideoTrackId;
  final List<StreamSubscription<dynamic>> _subs = <StreamSubscription<dynamic>>[];
  bool _disposed = false;
  bool _mpvGone = false;
  String? _error;

  @override
  Future<void> initialize() async {
    _wire();
    await _player.open(
      mk.Media(
        _src.source,
        httpHeaders: _src.headers.isEmpty ? null : _src.headers,
      ),
      play: false,
    );
    await _awaitReady();
    if (_disposed) return;
    final w = _player.state.width ?? 0;
    final h = _player.state.height ?? 0;

    // Decoded is not the same as displayed.
    //
    // libmpv draws through its own GL context, and where that context cannot be
    // created the player carries on perfectly: it demuxes, it decodes, it
    // reports a size and a duration, it plays the audio — and the texture never
    // receives a frame. What the viewer gets is a black rectangle with sound,
    // and nothing anywhere reports an error, because by libmpv's account
    // nothing went wrong.
    //
    // Waiting for the first frame is the only signal that separates the two.
    // Dimensions being known means a frame has already been decoded, so the
    // remaining step is local work and a few seconds is generous; the cost is
    // paid once, by a device that was going to show nothing anyway.
    if (w > 0 && h > 0 && !await _firstFrameArrives()) {
      markMediaKitUnavailable();
      debugPrint('[player] libmpv played without a picture — using the '
          'platform player for this device');
      await _swapToPlatformBackend();
      return;
    }

    value = value.copyWith(
      isInitialized: _error == null,
      duration: _player.state.duration,
      size: (w > 0 && h > 0)
          ? Size(w.toDouble(), h.toDouble())
          : value.size,
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

    final replacement = _src.uri == null
        ? _NativeController(vp.VideoPlayerController.file(File(_src.source)))
        : _NativeController(
            vp.VideoPlayerController.networkUrl(
              _src.uri!,
              httpHeaders: _src.headers,
            ),
          );
    _fallback = replacement;
    // Its value is this controller's value from here on, so the page's existing
    // listeners keep working without knowing anything changed.
    replacement.addListener(() {
      if (!_disposed) value = replacement.value;
    });
    await replacement.initialize();
    if (_disposed) {
      await replacement.dispose();
      return;
    }
    value = replacement.value;
  }

  /// Whether the texture ever receives a frame.
  ///
  /// Not a health check on the file — that has already decoded. This asks
  /// whether this device can put what was decoded on the screen.
  Future<bool> _firstFrameArrives() async {
    try {
      await _videoController.waitUntilFirstFrameRendered
          .timeout(_firstFrameTimeout);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _wire() {
    _subs
      ..add(_player.stream.position
          .listen((p) => _emit(value.copyWith(position: p))))
      ..add(_player.stream.duration
          .listen((d) => _emit(value.copyWith(duration: d))))
      ..add(_player.stream.playing
          .listen((p) => _emit(value.copyWith(isPlaying: p))))
      ..add(_player.stream.buffering
          .listen((b) => _emit(value.copyWith(isBuffering: b))))
      ..add(_player.stream.completed
          .listen((c) => _emit(value.copyWith(isCompleted: c))))
      ..add(_player.stream.width.listen((_) => _emitSize()))
      ..add(_player.stream.height.listen((_) => _emitSize()))
      // Both halves. This subscription existed and read only `t.audio`, so
      // every HLS rendition mpv reported was thrown away and the quality list
      // had nothing to offer but the provider's separate mirrors.
      ..add(_player.stream.tracks.listen((t) {
        _syncAudioTracks(t.audio);
        _syncVideoTracks(t.video);
      }))
      ..add(_player.stream.track.listen((t) {
        _activeAudioTrackId = t.audio.id;
        _activeVideoTrackId = t.video.id;
      }))
      ..add(_player.stream.error.listen((e) {
        _error = e;
        _emit(value.copyWith(errorDescription: e));
      }));
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
    final next = selectable > 1 ? sortVideoTracks(real) : const <PlayerVideoTrack>[];
    // Same lesson as the audio list: mpv probes in stages and reports the same
    // renditions twice, bare then described. Comparing by value rather than
    // length is what stops the sheet keeping the un-probed copy.
    if (_sameVideoTracks(next, _videoTracks)) return;
    _videoTracks = next;
    _emit(value.copyWith());
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

  void _syncAudioTracks(List<mk.AudioTrack> tracks) {
    final filtered =
        tracks.where((t) => t.id != 'no' && t.id != 'auto').toList();
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
    _emit(value.copyWith());
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
    final completer = Completer<void>();
    void finish() {
      if (!completer.isCompleted) completer.complete();
    }

    final subs = <StreamSubscription<dynamic>>[
      _player.stream.duration.listen((d) {
        if (d > Duration.zero) finish();
      }),
      _player.stream.width.listen((w) {
        if ((w ?? 0) > 0) finish();
      }),
      _player.stream.playing.listen((p) {
        if (p) finish();
      }),
      _player.stream.error.listen((e) {
        _error = e;
        finish();
      }),
    ];

    if (_player.state.duration > Duration.zero ||
        (_player.state.width ?? 0) > 0) {
      finish();
    }
    final timer = Timer(const Duration(seconds: 30), finish);

    await completer.future;
    timer.cancel();
    for (final s in subs) {
      await s.cancel();
    }
  }

  @override
  Future<void> play() => _fallback?.play() ?? _player.play();

  @override
  Future<void> pause() => _fallback?.pause() ?? _player.pause();

  @override
  Future<void> seekTo(Duration position) =>
      _fallback?.seekTo(position) ?? _player.seek(position);

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
  String? get activeAudioTrackId =>
      _fallback != null ? null : _activeAudioTrackId ?? _player.state.track.audio.id;


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
      );


  @override
  Future<void> dispose() async {
    _disposed = true;
    await _teardownMpv();
    await _fallback?.dispose();
    super.dispose();
  }

  /// Release libmpv without ending this controller.
  ///
  /// Shared with [dispose] because the swap has to leave nothing of the old
  /// backend behind: an undisposed Player keeps decoding, and two backends on
  /// one stream is audio playing twice.
  Future<void> _teardownMpv() async {
    if (_mpvGone) return;
    _mpvGone = true;
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await _player.dispose();
  }
}
