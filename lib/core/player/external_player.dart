import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Hands a stream to a third-party video app (VLC, MX Player, …) via a plain
/// ACTION_VIEW intent.
///
/// The hard limit here is headers. An Android intent carries only the URL (MX
/// Player reads a `headers` string-array extra, VLC ignores it entirely), so a
/// stream that is gated on `Referer`/`Origin`/`Cookie` will 403 in the external
/// app and show a black screen with no explanation. [gatingHeaders] exists so
/// the UI can warn *before* launching instead of after. See
/// `docs/CHROMECAST_PLAN.md` for the same constraint solved for casting.
class ExternalPlayer {
  const ExternalPlayer._();

  static const MethodChannel _channel = MethodChannel('soplay/platform');

  /// Headers that actually gate access, i.e. the ones whose absence changes the
  /// server's answer. `User-Agent`/`Accept`/`Accept-Language` are excluded on
  /// purpose: the app attaches them to every network stream
  /// (player_page.media.dart), external players send their own, and treating
  /// them as gating would warn on literally every source and train the user to
  /// ignore the warning.
  static const Set<String> _gatingHeaderNames = <String>{
    'referer',
    'origin',
    'cookie',
    'authorization',
  };

  static Map<String, String> gatingHeaders(Map<String, String> headers) {
    return <String, String>{
      for (final e in headers.entries)
        if (_gatingHeaderNames.contains(e.key.toLowerCase())) e.key: e.value,
    };
  }

  /// True when this stream can be handed off with no loss of access.
  ///
  /// Note a loopback URL is always safe: the local HLS proxy replays the real
  /// headers upstream, so the external app only ever sees `127.0.0.1` and needs
  /// nothing. That is the one path that makes gated sources work externally.
  static bool canHandOff(String url, Map<String, String> headers) {
    final uri = Uri.tryParse(url);
    if (uri != null && (uri.host == '127.0.0.1' || uri.host == 'localhost')) {
      return true;
    }
    return gatingHeaders(headers).isEmpty;
  }

  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// Launches the system chooser for [url]. Returns false when no app on the
  /// device can play it, so the caller can say so rather than appear to hang.
  static Future<bool> open({
    required String url,
    String? title,
    Map<String, String> headers = const <String, String>{},
    List<({String url, String label})> subtitles = const [],
  }) async {
    if (!isSupported) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('openExternalVideo', {
        'url': url,
        'title': title ?? '',
        'headers': gatingHeaders(headers),
        // The first is the one switched on. MX Player takes all of them,
        // VLC the first.
        'subtitles': [
          for (final s in subtitles) {'url': s.url, 'label': s.label},
        ],
      });
      return ok ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
