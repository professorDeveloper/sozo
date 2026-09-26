/// Splits the flat source list into servers and the qualities each one offers.
///
/// A provider returns one list mixing both — "SubsPlease · 1080p",
/// "Erai-raws · 720p" — and the player showed it raw, so picking a quality
/// could silently move you to another host. Servers and qualities are
/// independent choices and get one control each.
///
/// Everything here works on the source labels alone, so it stays testable
/// without a player or a widget tree.
class VideoOptionGroups {
  const VideoOptionGroups._();

  /// A height with its "p" ("1080p"), a bare standard height ("720"), or a
  /// named one ("4K", "FHD"). Any three or four digits used to count, so
  /// "x265" was a 265-line quality and "2024" a resolution.
  static final RegExp _resolution = RegExp(
    r'(?<![\dxX])(?:\d{3,4}[pP](?![a-zA-Z\d])|(?:144|240|288|360|480|540|576|720|900|1080|1440|2160|4320)(?![\d]))|(?<![a-zA-Z\d])(?:4K|2K|8K|UHD|FHD|QHD)(?![a-zA-Z\d])',
    caseSensitive: false,
  );
  static final RegExp _digits = RegExp(r'\d{3,4}');

  /// "·", "•", "|", a spaced dash ("Filemoon - 1080p") and a colon
  /// ("StreamWish:720p"). A dash inside a word ("Erai-raws") is not one.
  static final RegExp _separator = RegExp(r'\s*(?:[·•|:]|\s[-–—]\s)\s*');
  static final RegExp _spaces = RegExp(r'\s+');
  static final RegExp _edgePunctuation = RegExp(
    r'^[\s\-–—:·•|]+|[\s\-–—:·•|]+$',
  );

  static const Map<String, int> _named = {
    '4k': 2160,
    'uhd': 2160,
    '8k': 4320,
    '2k': 1440,
    'qhd': 1440,
    'fhd': 1080,
  };

  /// Labels that name no host at all still need something to group under.
  static const String _fallbackServer = 'Default';

  /// Words that describe a stream, not where it comes from. Read as host
  /// names, a provider's own ladder — "Auto", "1080p", "720p" — became two
  /// servers ("Auto" with nothing in it, "Default" with the rest), and the
  /// same resolutions were then parsed out of the master a second time.
  static const Set<String> _qualityWords = {
    'auto',
    'adaptive',
    'default',
    'hls',
    'multi',
    'hd',
    'sd',
    'hq',
    'lq',
    'mobile',
    'mobile hd',
    'full hd',
    'fullhd',
  };

  /// Of those, the ones that mean "let the stream choose": no quality text
  /// of their own, so the row reads as the player's Auto.
  static const Set<String> _adaptiveWords = {
    'auto',
    'adaptive',
    'default',
    'hls',
    'multi',
  };

  /// Encoding tags that ride along with a resolution ("4K HDR", "x265
  /// 1080p") and were left behind as the host's name.
  static const Set<String> _tagWords = {
    'hdr',
    'hdr10',
    'hdr10+',
    'dv',
    'dolby vision',
    'x264',
    'x265',
    'h264',
    'h265',
    'hevc',
    'avc',
    '10bit',
    '8bit',
  };

  static bool _isQualityWord(String text) =>
      _qualityWords.contains(text.trim().toLowerCase());

  /// [host], or empty when it names no host: only encoding tags ("x265
  /// 1080p", "4K HDR") or only a quality word ("HD 1080p"). A tag beside a
  /// real name stays — "Torrentio x265" and "Torrentio x264" are different
  /// files.
  static String _hostOnly(String host) {
    final words = [
      for (final w in host.split(_spaces))
        if (w.isNotEmpty) w,
    ];
    if (words.every((w) => _tagWords.contains(w.toLowerCase()))) return '';
    final tidy = _tidy(host);
    return _isQualityWord(tidy) ? '' : tidy;
  }

  static List<String> servers(List<String> labels) {
    final out = <String>[];
    for (final label in labels) {
      final name = serverOf(label);
      if (!out.contains(name)) out.add(name);
    }
    return out;
  }

  /// Positions in the ORIGINAL list, so the caller's selected index stays
  /// valid.
  static List<int> indicesFor(List<String> labels, String server) => [
    for (var i = 0; i < labels.length; i++)
      if (serverOf(labels[i]) == server) i,
  ];

  /// The distinct qualities [server] offers, so a picker can say what choosing
  /// it gets you.
  static List<String> qualitiesFor(List<String> labels, String server) {
    final out = <String>[];
    for (final i in indicesFor(labels, server)) {
      final quality = qualityOf(labels[i]);
      if (quality.isNotEmpty && !out.contains(quality)) out.add(quality);
    }
    return out;
  }

  static String serverOf(String label) => _split(label).server;

  /// The label with the host stripped off — empty when the label carries no
  /// quality of its own.
  static String qualityOf(String label) => _split(label).quality;

  static int? resolutionOf(String label) {
    final token = _resolution.firstMatch(qualityOf(label))?.group(0);
    if (token == null) return null;
    return _named[token.toLowerCase()] ??
        int.tryParse(_digits.firstMatch(token)?.group(0) ?? '');
  }

  /// The index to land on when switching to [server], keeping the current
  /// resolution where that server has it.
  ///
  /// Falls back to the server's highest resolution rather than its first entry:
  /// providers list sources in arbitrary order, and dropping someone from 1080p
  /// to 360p because that entry happened to come first reads as a bug.
  static int switchTo(List<String> labels, int currentIndex, String server) {
    final candidates = indicesFor(labels, server);
    if (candidates.isEmpty) return currentIndex;

    final wanted = currentIndex >= 0 && currentIndex < labels.length
        ? resolutionOf(labels[currentIndex])
        : null;
    if (wanted != null) {
      for (final i in candidates) {
        if (resolutionOf(labels[i]) == wanted) return i;
      }
    }
    var best = candidates.first;
    for (final i in candidates) {
      if ((resolutionOf(labels[i]) ?? 0) > (resolutionOf(labels[best]) ?? 0)) {
        best = i;
      }
    }
    return best;
  }

  static ({String server, String quality}) _split(String label) {
    final text = label.trim();
    if (text.isEmpty) return (server: _fallbackServer, quality: '');

    final parts = [
      for (final part in text.split(_separator))
        if (part.trim().isNotEmpty) part.trim(),
    ];
    if (parts.length > 1) {
      // Which part is the quality is decided by what it LOOKS like, not by
      // where it sits. Assuming the host comes first put "480p · 1-server" in
      // backwards — the settings sheet offered a server called 480p and a
      // quality called 1-server.
      final at = parts.indexWhere(_resolution.hasMatch);
      if (at >= 0) {
        final host = [
          for (final p in [...parts.take(at), ...parts.skip(at + 1)])
            if (_hostOnly(p).isNotEmpty) _hostOnly(p),
        ].join(' · ');
        return (
          server: host.isEmpty ? _fallbackServer : host,
          quality: parts[at],
        );
      }
      // Nothing resolution-shaped anywhere: the whole label names a host, the
      // way "SUB · Mp4Upload" does — less any part that only describes the
      // stream ("Auto · Mp4Upload"). Taking the first part as the server would
      // make a language tag into a host and the host into a quality.
      final host = [
        for (final p in parts)
          if (!_isQualityWord(p)) p,
      ].join(' · ');
      if (host.isEmpty) return _qualityOnly(text);
      return (server: host, quality: '');
    }

    // A label that is only a quality word: "Auto", "HD", "Mobile HD".
    if (_isQualityWord(text)) return _qualityOnly(text);

    final words = text.split(_spaces);
    final at = words.indexWhere(_resolution.hasMatch);
    // Nothing resolution-shaped in it: the whole label names a server, the way
    // "Server 1" or "SUB Mp4Upload" does.
    if (at < 0) return (server: text, quality: '');

    final host = _hostOnly(
      [...words.take(at), ...words.skip(at + 1)].join(' '),
    );
    return (server: host.isEmpty ? _fallbackServer : host, quality: words[at]);
  }

  /// A label naming no host: grouped under the fallback server, with the
  /// word kept as its quality unless it means the stream's own choice.
  static ({String server, String quality}) _qualityOnly(String text) => (
    server: _fallbackServer,
    quality: _adaptiveWords.contains(text.trim().toLowerCase()) ? '' : text,
  );

  /// A host without the separator it was cut from: "Filemoon -" → "Filemoon".
  static String _tidy(String host) => host.replaceAll(_edgePunctuation, '');
}
