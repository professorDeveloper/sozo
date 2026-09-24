import 'package:xml/xml.dart';

/// One video rendition in a DASH manifest.
class DashRepresentation {
  const DashRepresentation({
    required this.id,
    required this.height,
    this.width,
    this.bandwidth,
    this.codecs,
  });

  final String id;
  final int height;
  final int? width;
  final int? bandwidth;
  final String? codecs;
}

/// Reading and narrowing a DASH manifest (MPD), so a DASH stream can offer
/// the same manual quality an HLS one does.
///
/// Neither engine here exposes DASH track selection: ExoPlayer has it but the
/// plugin does not surface it, and media_kit hands DASH to the platform
/// player. So a quality is chosen the other way round — the player is given a
/// manifest that holds only that rendition, served by the local proxy.
abstract final class DashManifest {
  static bool looksLikeMpd(String text) =>
      text.contains('<MPD') || text.contains(':MPD');

  static bool _isVideoSet(XmlElement set) {
    String? attr(XmlElement e, String name) => e.getAttribute(name);
    final mime = (attr(set, 'mimeType') ?? attr(set, 'contentType') ?? '')
        .toLowerCase();
    if (mime.startsWith('video')) return true;
    if (mime.startsWith('audio') || mime.startsWith('text')) return false;
    // Declared on the Representations instead, or only by their size.
    for (final r in set.findElements('Representation')) {
      final m = (attr(r, 'mimeType') ?? '').toLowerCase();
      if (m.startsWith('video') || attr(r, 'height') != null) return true;
    }
    return attr(set, 'maxHeight') != null || attr(set, 'height') != null;
  }

  static Iterable<XmlElement> _allByLocalName(XmlNode root, String name) => root
      .descendants
      .whereType<XmlElement>()
      .where((e) => e.name.local == name);

  /// The video renditions, tallest first, one per height (the highest
  /// bitrate of each) — the list a quality picker offers.
  static List<DashRepresentation> videoRepresentations(String mpd) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(mpd);
    } catch (_) {
      return const [];
    }
    final byHeight = <int, DashRepresentation>{};
    for (final set in _allByLocalName(doc, 'AdaptationSet')) {
      if (!_isVideoSet(set)) continue;
      final setHeight = int.tryParse(set.getAttribute('height') ?? '');
      for (final r in set.childElements.where(
        (e) => e.name.local == 'Representation',
      )) {
        final id = r.getAttribute('id');
        final height =
            int.tryParse(r.getAttribute('height') ?? '') ?? setHeight;
        if (id == null || id.isEmpty || height == null || height <= 0) {
          continue;
        }
        final rep = DashRepresentation(
          id: id,
          height: height,
          width: int.tryParse(r.getAttribute('width') ?? ''),
          bandwidth: int.tryParse(r.getAttribute('bandwidth') ?? ''),
          codecs: r.getAttribute('codecs'),
        );
        final held = byHeight[height];
        if (held == null || (rep.bandwidth ?? 0) > (held.bandwidth ?? 0)) {
          byHeight[height] = rep;
        }
      }
    }
    return byHeight.values.toList()
      ..sort((a, b) => b.height.compareTo(a.height));
  }

  /// [mpd] with every video Representation other than [keepId] removed from
  /// the set that holds it (audio and subtitles untouched), and every
  /// absolute address passed through [rewriteUrl] — the proxy's own paths,
  /// so segment requests go through it and carry the stream's headers.
  ///
  /// [keepId] null narrows nothing and only rewrites. The manifest comes back
  /// unchanged when it does not parse.
  static String narrow(
    String mpd, {
    String? keepId,
    String Function(String absoluteUrl)? rewriteUrl,
  }) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(mpd);
    } catch (_) {
      return mpd;
    }
    if (keepId != null) {
      for (final set in _allByLocalName(doc, 'AdaptationSet').toList()) {
        if (!_isVideoSet(set)) continue;
        final reps = set.childElements
            .where((e) => e.name.local == 'Representation')
            .toList();
        if (!reps.any((r) => r.getAttribute('id') == keepId)) continue;
        for (final r in reps) {
          if (r.getAttribute('id') != keepId) r.remove();
        }
      }
    }
    if (rewriteUrl != null) {
      bool absolute(String v) =>
          v.startsWith('http://') || v.startsWith('https://');
      for (final base in _allByLocalName(doc, 'BaseURL')) {
        final v = base.innerText.trim();
        if (absolute(v)) base.innerText = rewriteUrl(v);
      }
      for (final e in doc.descendants.whereType<XmlElement>()) {
        for (final name in const ['media', 'initialization', 'sourceURL']) {
          final v = e.getAttribute(name);
          if (v != null && absolute(v)) e.setAttribute(name, rewriteUrl(v));
        }
      }
    }
    return doc.toXmlString();
  }
}
