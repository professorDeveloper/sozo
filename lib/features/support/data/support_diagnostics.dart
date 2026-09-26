import 'dart:io' show Platform;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:soplay/core/diagnostics/player_log.dart';
import 'package:soplay/core/player/player_engine.dart';
import 'package:soplay/features/support/data/support_models.dart';

/// What a support ticket may carry about the device, when the viewer lets it.
///
/// A fixed list of named fields and the player log, and nothing else: no
/// account, no email, no tokens, no device identifiers. The log is redacted as
/// it is written (see [PlayerLog.redact]) and the server redacts it again
/// before storing it. The viewer sees every field before sending.
class SupportDiagnostics {
  const SupportDiagnostics._();

  /// The newest end of the player log: the failure is almost always there,
  /// and 400 lines stay well inside the server's 64 KB.
  static const int logLines = 400;

  static Future<Map<String, String>> collect({
    required String language,
    SupportRequestArgs? args,
    bool includeLog = true,
  }) async {
    final out = <String, String>{};
    void put(String key, String? value) {
      final v = value?.trim();
      if (v != null && v.isNotEmpty) out[key] = v;
    }

    try {
      final info = await PackageInfo.fromPlatform();
      put('app', info.version);
      put('build', info.buildNumber);
    } catch (_) {}
    put('platform', Platform.operatingSystem);
    put('os', Platform.operatingSystemVersion);
    put('locale', Platform.localeName);
    put('language', language);
    put('timezone', _utcOffset(DateTime.now().timeZoneOffset));
    try {
      put('engine', switch (resolvePlayerEngine()) {
        PlayerEngine.native => 'exoplayer',
        PlayerEngine.mediaKit => 'mpv',
        PlayerEngine.external => 'external',
      });
    } catch (_) {}
    put('network', await _network());
    put('provider', args?.provider);
    put('content', args?.content);
    put('screen', args?.screen);
    final error = args?.error?.trim();
    if (error != null && error.isNotEmpty) {
      put('error', error.length > 200 ? '${error.substring(0, 199)}…' : error);
    }
    if (includeLog) {
      final log = PlayerLog.instance;
      if (log.lines.isNotEmpty) {
        put('log', log.formatForSupport(maxLines: logLines));
      }
    }
    return out;
  }

  static String _utcOffset(Duration offset) {
    final sign = offset.isNegative ? '-' : '+';
    final m = offset.inMinutes.abs();
    return 'UTC$sign${(m ~/ 60).toString().padLeft(2, '0')}:'
        '${(m % 60).toString().padLeft(2, '0')}';
  }

  static Future<String?> _network() async {
    try {
      final kinds = await Connectivity().checkConnectivity();
      if (kinds.contains(ConnectivityResult.wifi)) return 'wifi';
      if (kinds.contains(ConnectivityResult.ethernet)) return 'ethernet';
      if (kinds.contains(ConnectivityResult.mobile)) return 'mobile';
      if (kinds.contains(ConnectivityResult.vpn)) return 'vpn';
      if (kinds.contains(ConnectivityResult.none)) return 'none';
      return kinds.isEmpty ? null : kinds.first.name;
    } catch (_) {
      return null;
    }
  }
}
