/// The URLs and headers a Jellyfin server expects, built without any I/O.
///
/// Auth rides in the query string as well as the header for everything a
/// player, a download or a subtitle loader fetches: headers do not survive a
/// cast hand-off, an external player or a download resumed later, while the
/// key in the URL does.
class JellyfinUrls {
  JellyfinUrls._();

  static const String clientName = 'Sozo';

  /// Turns what someone typed into a base URL: scheme added, trailing slash
  /// and a pasted web-client path (`/web/#/home.html`) removed.
  static String normalizeBaseUrl(String input) {
    var text = input.trim();
    if (text.isEmpty) return '';
    if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(text)) {
      text = 'http://$text';
    }
    final uri = Uri.tryParse(text);
    if (uri == null || uri.host.isEmpty) return '';
    var path = uri.path;
    final web = path.toLowerCase().indexOf('/web');
    if (web >= 0) path = path.substring(0, web);
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return Uri(
      scheme: uri.scheme.toLowerCase(),
      userInfo: uri.userInfo,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: path,
    ).toString();
  }

  /// `api_key` was the only query key up to 10.8; 10.9 added `ApiKey`, and
  /// later releases stopped accepting the old one.
  static String keyParam(String version) {
    final parts = version.split('.');
    final major = int.tryParse(parts.isNotEmpty ? parts[0] : '');
    final minor = int.tryParse(parts.length > 1 ? parts[1] : '');
    if (major == null) return 'ApiKey';
    if (major < 10) return 'api_key';
    if (major == 10 && (minor ?? 0) < 9) return 'api_key';
    return 'ApiKey';
  }

  static String authorization({
    required String deviceName,
    required String deviceId,
    required String version,
    String? token,
  }) {
    String q(String v) => v.replaceAll('"', "'");
    final b = StringBuffer('MediaBrowser Client="$clientName", ')
      ..write('Device="${q(deviceName)}", ')
      ..write('DeviceId="${q(deviceId)}", ')
      ..write('Version="${q(version)}"');
    if (token != null && token.isNotEmpty) b.write(', Token="${q(token)}"');
    return b.toString();
  }

  /// [path] resolved against [base], keeping a reverse-proxy base path.
  static String absolute(String base, String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return '$base${path.startsWith('/') ? '' : '/'}$path';
  }

  static String image(
    String base,
    String itemId, {
    String type = 'Primary',
    String? tag,
    int? index,
    int maxWidth = 400,
  }) {
    final slot = index == null ? type : '$type/$index';
    return Uri.parse('$base/Items/$itemId/Images/$slot')
        .replace(
          queryParameters: {
            'maxWidth': '$maxWidth',
            'quality': '90',
            if (tag != null && tag.isNotEmpty) 'tag': tag,
          },
        )
        .toString();
  }

  /// The file as stored, byte for byte; `static=true` tells the server not to
  /// remux, so seeking and downloads behave like any other progressive file.
  static String directStream({
    required String base,
    required String itemId,
    required String mediaSourceId,
    required String container,
    required String token,
    required String keyParam,
    required String deviceId,
    String? playSessionId,
    String? tag,
  }) {
    final ext = container.split(',').first.trim().toLowerCase();
    final suffix = ext.isEmpty ? '' : '.$ext';
    return Uri.parse('$base/Videos/$itemId/stream$suffix')
        .replace(
          queryParameters: {
            'static': 'true',
            'MediaSourceId': mediaSourceId,
            'DeviceId': deviceId,
            if (playSessionId != null && playSessionId.isNotEmpty)
              'PlaySessionId': playSessionId,
            if (tag != null && tag.isNotEmpty) 'Tag': tag,
            keyParam: token,
          },
        )
        .toString();
  }

  /// An H.264/AAC HLS transcode capped at [maxHeight] and [videoBitrate].
  ///
  /// Built by hand because PlaybackInfo only returns a `TranscodingUrl` when
  /// the server itself decided against direct play, and the player needs a
  /// transcode to fall back to when direct play fails on the device.
  static String hls({
    required String base,
    required String itemId,
    required String mediaSourceId,
    required String token,
    required String keyParam,
    required String deviceId,
    required int videoBitrate,
    int? maxHeight,
    String? playSessionId,
    int? audioStreamIndex,
  }) {
    return Uri.parse('$base/Videos/$itemId/master.m3u8')
        .replace(
          queryParameters: {
            'MediaSourceId': mediaSourceId,
            'DeviceId': deviceId,
            if (playSessionId != null && playSessionId.isNotEmpty)
              'PlaySessionId': playSessionId,
            'VideoCodec': 'h264',
            'AudioCodec': 'aac',
            'SegmentContainer': 'ts',
            'VideoBitrate': '$videoBitrate',
            'AudioBitrate': '192000',
            'TranscodingMaxAudioChannels': '2',
            if (maxHeight != null) 'MaxHeight': '$maxHeight',
            if (audioStreamIndex != null)
              'AudioStreamIndex': '$audioStreamIndex',
            'RequireAvc': 'false',
            'BreakOnNonKeyFrames': 'true',
            'SubtitleMethod': 'External',
            keyParam: token,
          },
        )
        .toString();
  }

  static String subtitle({
    required String base,
    required String itemId,
    required String mediaSourceId,
    required int index,
    required String token,
    required String keyParam,
    String format = 'vtt',
  }) {
    return Uri.parse(
      '$base/Videos/$itemId/$mediaSourceId/Subtitles/$index/0/Stream.$format',
    ).replace(queryParameters: {keyParam: token}).toString();
  }

  /// Adds the key to a server-relative URL that may or may not carry one.
  static String withKey(String url, String keyParam, String token) {
    final uri = Uri.parse(url);
    final hasKey = uri.queryParameters.keys.any(
      (k) => k.toLowerCase() == 'apikey' || k.toLowerCase() == 'api_key',
    );
    if (hasKey) return url;
    return uri
        .replace(queryParameters: {...uri.queryParameters, keyParam: token})
        .toString();
  }

  /// The item a stream URL belongs to, from its `/Videos/<id>/` segment.
  ///
  /// Normalised to the dashless lowercase form: PlaybackInfo's own
  /// TranscodingUrl writes the id as a dashed GUID, the rest of the API does
  /// not, and a variant playlist the player expanded keeps only the path.
  static String? itemIdFromStreamUrl(String url) {
    final segments = Uri.tryParse(url)?.pathSegments ?? const <String>[];
    for (var i = 0; i < segments.length - 1; i++) {
      if (segments[i].toLowerCase() == 'videos') {
        return normalizeId(segments[i + 1]);
      }
    }
    return null;
  }

  static String normalizeId(String id) => id.replaceAll('-', '').toLowerCase();

  static const int ticksPerMs = 10000;

  static int msToTicks(Duration d) => d.inMilliseconds * ticksPerMs;

  static Duration ticksToDuration(Object? ticks) {
    final n = ticks is num ? ticks.toInt() : int.tryParse('$ticks') ?? 0;
    return Duration(milliseconds: n ~/ ticksPerMs);
  }
}
