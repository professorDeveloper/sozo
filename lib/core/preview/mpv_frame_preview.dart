import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import 'package:soplay/core/player/player_engine.dart';

/// Scrub previews from a second, silent libmpv.
///
/// The platform decoders the preview used to rely on each open only some of
/// what the app plays: Android's `MediaMetadataRetriever` cannot read HLS at
/// all — which is most streams here — and the desktop builds had no preview
/// decoder of any kind. libmpv, already shipped for playback, reads every one
/// of them, so the seek bar can show a frame wherever a video can play.
///
/// It is a second player, not the one on screen: paused, muted, no audio or
/// subtitle track decoded, no video output (`vo=null` — a frame is taken from
/// the decoder, never drawn), and seeking to keyframes only. Not scaled here:
/// the Android libmpv build carries no scale filter, and asking for one fails
/// the whole load — the preview widget decodes the JPEG at thumbnail size. A scrub costs a few segment fetches, not a
/// second playback.
///
/// Speaks the same `open` / `frame` / `close` protocol as the platform
/// channel, so [FramePreviewSession] drives it unchanged — including its
/// rule that only the latest position of a drag is ever decoded.
class MpvFramePreview {
  Player? _player;
  String? _identity;
  bool _broken = false;

  /// Completed when a seek has finished and the frame at it is decoded.
  Completer<void>? _seekDone;
  bool _seeking = false;

  /// Kept open this long after the finger lifts, because scrubbing comes in
  /// runs — a second drag a few seconds after the first should not pay for
  /// opening the stream again.
  static const Duration _linger = Duration(seconds: 45);
  Timer? _dispose;

  Future<dynamic> invoke(String method, Map<String, dynamic>? args) async {
    switch (method) {
      case 'open':
        return _open(
          args?['url'] as String? ?? '',
          (args?['headers'] as Map?)?.cast<String, String>() ?? const {},
        );
      case 'frame':
        return _frame((args?['posMs'] as num?)?.toInt() ?? 0);
      case 'close':
        _scheduleDispose();
        return null;
    }
    return null;
  }

  Future<bool> _open(String url, Map<String, String> headers) async {
    if (_broken || url.isEmpty) return false;
    _dispose?.cancel();
    final identity = '$url\u0000${headers.entries.join(',')}';
    if (_identity == identity && _player != null) return true;
    await _release();

    final Player player;
    try {
      MediaKit.ensureInitialized();
      player = Player(
        configuration: const PlayerConfiguration(
          vo: 'null',
          muted: true,
          // Enough for a segment or two; this player never plays ahead.
          bufferSize: 4 * 1024 * 1024,
          logLevel: MPVLogLevel.v,
        ),
      );
    } catch (e) {
      // No loadable libmpv on this device: say so once and stop asking.
      _broken = true;
      markMediaKitUnavailable();
      debugPrint('[preview:mpv] unavailable: $e');
      return false;
    }
    _player = player;
    _identity = identity;
    if (kDebugMode) {
      player.stream.error.listen((e) => debugPrint('[preview:mpv] error: $e'));
      player.stream.log.listen(
        (l) => debugPrint('[preview:mpv] ${l.prefix}: ${l.text.trim()}'),
      );
    }
    try {
      final native = player.platform;
      if (native is NativePlayer) {
        for (final e in const {
          'aid': 'no',
          'sid': 'no',
          'hwdec': 'no',
          'hr-seek': 'no',
          'demuxer-readahead-secs': '1',
          'cache-pause': 'no',
          'ytdl': 'no',
        }.entries) {
          await native.setProperty(e.key, e.value);
        }
        await native.observeProperty('seeking', (value) async {
          final seeking = value == 'yes' || value == 'true' || value == '1';
          if (_seeking && !seeking) {
            final done = _seekDone;
            if (done != null && !done.isCompleted) done.complete();
          }
          _seeking = seeking;
        });
      }
      await player.open(Media(url, httpHeaders: headers), play: false);
      // Opened is not loaded: wait until the stream says how long it is,
      // which is when a seek into it means something.
      if (player.state.duration == Duration.zero) {
        await player.stream.duration
            .firstWhere((d) => d > Duration.zero)
            .timeout(const Duration(seconds: 8));
      }
      return true;
    } catch (e) {
      debugPrint('[preview:mpv] open failed: $e');
      await _release();
      return false;
    }
  }

  Future<Uint8List?> _frame(int positionMs) async {
    final player = _player;
    if (player == null) return null;
    final done = _seekDone = Completer<void>();
    await player.seek(Duration(milliseconds: positionMs));
    try {
      await done.future.timeout(const Duration(milliseconds: 2500));
    } on TimeoutException {
      // A seek inside what is already buffered can finish before the
      // `seeking` flag is ever seen to rise; the frame is there regardless.
    }
    if (!identical(player, _player)) return null;
    try {
      return await player.screenshot(format: 'image/jpeg');
    } catch (e) {
      debugPrint('[preview:mpv] frame failed: $e');
      return null;
    }
  }

  void _scheduleDispose() {
    _dispose?.cancel();
    _dispose = Timer(_linger, () => unawaited(_release()));
  }

  Future<void> _release() async {
    _dispose?.cancel();
    _dispose = null;
    final player = _player;
    _player = null;
    _identity = null;
    _seeking = false;
    final done = _seekDone;
    if (done != null && !done.isCompleted) done.complete();
    _seekDone = null;
    if (player != null) {
      try {
        await player.dispose();
      } catch (_) {}
    }
  }
}
