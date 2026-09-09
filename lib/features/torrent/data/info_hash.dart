/// BitTorrent info-hash helpers.
///
/// The same torrent reaches Sozo in two different encodings depending on which
/// tracker found it: Nyaa's RSS publishes the 40-character hex form, while
/// magnets built by Tokyo Toshokan (and plenty of other sites) use the
/// 32-character Base32 form defined in BEP 9. They are the same 20 bytes.
///
/// This matters because Tokyo Toshokan largely *mirrors* Nyaa. Without
/// normalising both encodings to one, a search returns every popular release
/// twice, and the two copies look unrelated.
abstract final class InfoHash {
  static final _hex40 = RegExp(r'^[0-9a-fA-F]{40}$');
  static final _base32_32 = RegExp(r'^[A-Za-z2-7]{32}$');
  static final _btihInMagnet =
      RegExp(r'xt=urn:btih:([0-9a-zA-Z]{32,40})', caseSensitive: false);

  /// Normalises any info-hash encoding to lowercase hex, or null if [raw] is
  /// not one.
  static String? normalize(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return null;
    if (_hex40.hasMatch(value)) return value.toLowerCase();
    if (_base32_32.hasMatch(value)) return _base32ToHex(value.toUpperCase());
    return null;
  }

  /// Pulls the info hash out of a magnet URI and normalises it.
  static String? fromMagnet(String? magnet) {
    if (magnet == null) return null;
    return normalize(_btihInMagnet.firstMatch(magnet)?.group(1));
  }

  /// RFC 4648 Base32 (no padding) to hex. Returns null on any invalid symbol
  /// rather than producing a hash that would silently fail to resolve.
  static String? _base32ToHex(String input) {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    var buffer = 0;
    var bits = 0;
    final bytes = <int>[];

    for (final char in input.codeUnits) {
      final index = alphabet.indexOf(String.fromCharCode(char));
      if (index < 0) return null;
      buffer = (buffer << 5) | index;
      bits += 5;
      if (bits >= 8) {
        bits -= 8;
        bytes.add((buffer >> bits) & 0xff);
      }
    }

    // A v1 info hash is exactly 20 bytes; anything else is not one.
    if (bytes.length != 20) return null;
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
