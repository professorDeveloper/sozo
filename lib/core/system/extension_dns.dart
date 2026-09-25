import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// Who answers "what is the address of this host" for the extension runtimes.
///
/// Not a VPN and not a proxy. The bytes travel the same route to the same
/// servers from the same address; only the lookup moves. That is enough for the
/// common case — an ISP that blocks a site by refusing to resolve it — and
/// nothing at all for a block by address. The setting's description says so,
/// because this is the kind of feature people reach for expecting more.
enum DnsProvider {
  system('', 'settings.dns_system'),
  cloudflare('cloudflare', 'settings.dns_cloudflare'),
  google('google', 'settings.dns_google'),
  adguard('adguard', 'settings.dns_adguard'),
  quad9('quad9', 'settings.dns_quad9'),
  mullvad('mullvad', 'settings.dns_mullvad');

  const DnsProvider(this.id, this.labelKey);

  /// Empty for [system]; otherwise what the platform side persists and matches.
  final String id;
  final String labelKey;

  static DnsProvider byId(String? id) {
    final want = (id ?? '').trim().toLowerCase();
    for (final p in values) {
      if (p.id == want) return p;
    }
    return DnsProvider.system;
  }
}

class ExtensionDns {
  ExtensionDns._();

  static const MethodChannel _ch = MethodChannel('soplay/system_controls');

  /// Android only: the resolver belongs to the extension runtimes, and those
  /// are Android. Elsewhere this is a no-op rather than a broken switch.
  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// Applies [provider] and returns what is actually in force.
  ///
  /// Not always what was asked for — a resolver that cannot be built falls back
  /// to the system one rather than leaving the app unable to reach anything,
  /// and the caller needs to show that rather than a lie.
  static Future<DnsProvider> apply(DnsProvider provider) async {
    if (!isSupported) return DnsProvider.system;
    try {
      final applied = await _ch.invokeMethod<String>('setExtensionDns', {
        'id': provider.id,
      });
      return DnsProvider.byId(applied);
    } catch (_) {
      return DnsProvider.system;
    }
  }

  static Future<DnsProvider> current() async {
    if (!isSupported) return DnsProvider.system;
    try {
      return DnsProvider.byId(
        await _ch.invokeMethod<String>('getExtensionDns'),
      );
    } catch (_) {
      return DnsProvider.system;
    }
  }
}
