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

  static final RegExp _resolution = RegExp(r'\d{3,4}');
  static final RegExp _separator = RegExp(r'\s*[·•|]\s*');
  static final RegExp _spaces = RegExp(r'\s+');

  /// Labels that name no host at all still need something to group under.
  static const String _fallbackServer = 'Default';

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

  static int? resolutionOf(String label) =>
      int.tryParse(_resolution.firstMatch(qualityOf(label))?.group(0) ?? '');

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
        final host = [...parts.take(at), ...parts.skip(at + 1)].join(' · ');
        return (
          server: host.isEmpty ? _fallbackServer : host,
          quality: parts[at],
        );
      }
      // Nothing resolution-shaped anywhere: the whole label names a host, the
      // way "SUB · Mp4Upload" does. Taking the first part as the server would
      // make a language tag into a host and the host into a quality.
      return (server: text, quality: '');
    }

    final words = text.split(_spaces);
    final at = words.indexWhere(_resolution.hasMatch);
    // Nothing resolution-shaped in it: the whole label names a server, the way
    // "Server 1" or "SUB Mp4Upload" does.
    if (at < 0) return (server: text, quality: '');

    final host = [...words.take(at), ...words.skip(at + 1)].join(' ');
    return (server: host.isEmpty ? _fallbackServer : host, quality: words[at]);
  }
}
