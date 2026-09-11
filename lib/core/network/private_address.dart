import 'dart:io';

/// Whether a URL points into the device's own network rather than the
/// internet: loopback, RFC 1918 private ranges, link-local, carrier-grade NAT,
/// unique-local IPv6, or a `.local` / `localhost` name.
///
/// Extractor code is downloaded from the backend and runs with a general
/// fetch bridge ([DartFetch]). Without this check it could reach the router's
/// admin page, a NAS, the TorrServer or the HLS proxy on 127.0.0.1 — anything
/// on the user's LAN — with the phone as the client.
class PrivateAddress {
  PrivateAddress._();

  static bool isPrivateIp(InternetAddress address) {
    if (address.isLoopback || address.isLinkLocal || address.isMulticast) {
      return true;
    }
    final b = address.rawAddress;
    if (address.type == InternetAddressType.IPv4 && b.length == 4) {
      return _privateV4(b[0], b[1]);
    }
    if (address.type == InternetAddressType.IPv6 && b.length == 16) {
      // Unspecified (::).
      if (b.every((x) => x == 0)) return true;
      // Unique local fc00::/7.
      if ((b[0] & 0xfe) == 0xfc) return true;
      // IPv4-mapped ::ffff:a.b.c.d — judge the embedded address.
      final mapped = b.sublist(0, 10).every((x) => x == 0) &&
          b[10] == 0xff &&
          b[11] == 0xff;
      if (mapped) return _privateV4(b[12], b[13]) || b[12] == 127;
    }
    return false;
  }

  static bool _privateV4(int a, int b) {
    if (a == 0 || a == 10 || a == 127) return true;
    if (a == 169 && b == 254) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    if (a == 192 && b == 168) return true;
    if (a == 100 && b >= 64 && b <= 127) return true;
    return false;
  }

  /// A quick verdict from the URL alone: a non-http(s) scheme, a local
  /// hostname, or a literal private IP. Hostnames that merely *resolve* to a
  /// private address need [resolvesPrivate].
  static bool isObviouslyPrivate(Uri uri) {
    if (uri.scheme != 'http' && uri.scheme != 'https') return true;
    final host = uri.host.toLowerCase();
    if (host.isEmpty) return true;
    if (host == 'localhost' || host.endsWith('.localhost')) return true;
    if (host.endsWith('.local') || host.endsWith('.internal')) return true;
    final literal = InternetAddress.tryParse(host);
    return literal != null && isPrivateIp(literal);
  }

  static final Map<String, (bool, DateTime)> _dnsCache = {};

  /// Whether [host] resolves to a private address. Cached for five minutes;
  /// a lookup that fails or times out answers false and leaves the request
  /// to fail on its own.
  static Future<bool> resolvesPrivate(String host) async {
    final key = host.toLowerCase();
    final hit = _dnsCache[key];
    if (hit != null && DateTime.now().isBefore(hit.$2)) return hit.$1;
    var private = false;
    try {
      final addresses = await InternetAddress.lookup(key)
          .timeout(const Duration(seconds: 3));
      private = addresses.any(isPrivateIp);
    } catch (_) {
      private = false;
    }
    if (_dnsCache.length > 256) _dnsCache.clear();
    _dnsCache[key] = (private, DateTime.now().add(const Duration(minutes: 5)));
    return private;
  }
}
