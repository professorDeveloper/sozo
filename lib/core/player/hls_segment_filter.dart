/// Takes the segments [drop] matches out of a media playlist, with their timing.
///
/// Some catalogues splice a full-screen ad into every stream. It is ordinary
/// segments between two discontinuities, so the player cannot tell it from the
/// film; only the path gives it away, and the source knows that path. The two
/// discontinuities around it become one, because the film's timestamps still
/// jump there.
///
/// A master playlist comes back as it is: its entries are not segments. So does a
/// playlist the rule would empty, since that rule is wrong rather than the film.
String dropHlsSegments(String playlist, RegExp drop) {
  if (playlist.contains('#EXT-X-STREAM-INF')) return playlist;
  final out = <String>[];
  // From an #EXTINF up to its uri, which decides whether they stay.
  final pending = <String>[];
  var discontinuity = false;
  var kept = 0;
  var dropped = 0;
  for (final line in playlist.split('\n')) {
    final s = line.trim();
    if (s == '#EXT-X-DISCONTINUITY') {
      discontinuity = true;
    } else if (s.startsWith('#EXTINF') ||
        pending.isNotEmpty && s.startsWith('#')) {
      pending.add(line);
    } else if (s.isEmpty || s.startsWith('#')) {
      out.add(line);
    } else if (drop.hasMatch(s)) {
      pending.clear();
      dropped++;
    } else {
      if (discontinuity) out.add('#EXT-X-DISCONTINUITY');
      discontinuity = false;
      out
        ..addAll(pending)
        ..add(line);
      pending.clear();
      kept++;
    }
  }
  if (dropped == 0 || kept == 0) return playlist;
  return out.join('\n');
}

const _pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
const _iend = [0x49, 0x45, 0x4E, 0x44];
const _tsSync = 0x47;
const _tsPacket = 188;

/// Whether these first bytes are a PNG's.
bool startsWithPng(List<int> bytes) {
  if (bytes.length < _pngSignature.length) return false;
  for (var i = 0; i < _pngSignature.length; i++) {
    if (bytes[i] != _pngSignature[i]) return false;
  }
  return true;
}

/// Where the MPEG-TS starts in a segment wrapped in a PNG, or null if it cannot
/// be told yet from these bytes.
///
/// Some hosts store video on image CDNs: a real picture, some padding, then the
/// stream, at an offset that differs per segment. Neither player reads past the
/// picture. One sync byte proves nothing, since padding may hold one, so the next
/// packet has to start where it should as well.
int? transportStreamStart(List<int> bytes) {
  var end = -1;
  for (var i = _pngSignature.length; i + _iend.length <= bytes.length; i++) {
    if (bytes[i] == _iend[0] &&
        bytes[i + 1] == _iend[1] &&
        bytes[i + 2] == _iend[2] &&
        bytes[i + 3] == _iend[3]) {
      end = i + _iend.length + 4; // The chunk's CRC.
      break;
    }
  }
  if (end < 0) return null;
  for (var i = end; i + _tsPacket * 2 < bytes.length; i++) {
    if (bytes[i] == _tsSync &&
        bytes[i + _tsPacket] == _tsSync &&
        bytes[i + _tsPacket * 2] == _tsSync) {
      return i;
    }
  }
  return null;
}
