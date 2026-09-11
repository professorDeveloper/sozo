import 'dart:async';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ExtensionBridge {
  ExtensionBridge._();
  static final ExtensionBridge instance = ExtensionBridge._();

  static String? _override;

  static void setUrl(String? url) {
    final v = (url ?? '').trim();
    _override = v.isEmpty ? null : v;
  }

  static String get baseUrl {
    final o = _override;
    if (o != null && o.isNotEmpty) return o;
    if (!dotenv.isInitialized) return '';
    return (dotenv.maybeGet('EXTENSION_BRIDGE_URL') ?? '').trim();
  }

  static bool get isEnabled => !Platform.isAndroid && baseUrl.isNotEmpty;

  /// Splits the pasted phone link into the address requests go to and the
  /// access token they carry.
  ///
  /// The phone's link is `http://<lan-ip>:8765/?t=<token>` — the bridge refuses
  /// any request without that token, because it listens on the whole network
  /// and its routes install and run extension code. A link saved before the
  /// token existed has no `t` and simply parses to an empty token; the phone
  /// then answers 401 until the new link is pasted.
  static ({String base, String token}) parse(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return (base: '', token: '');
    final uri = Uri.tryParse(v);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return (base: v.replaceAll(RegExp(r'/+$'), ''), token: '');
    }
    final token = uri.queryParameters['t'] ?? '';
    final path = uri.path.replaceAll(RegExp(r'/+$'), '');
    final base = Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: path.isEmpty ? null : path,
    ).toString();
    return (base: base, token: token);
  }

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 60),
      responseType: ResponseType.plain,
    ),
  );

  Future<String?> call(
    String system,
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    final link = parse(baseUrl);
    final base = link.base;
    if (base.isEmpty) return null;
    try {
      final resp = await _dio.get<String>(
        '$base/$system/$method',
        queryParameters: params?.map(
          (k, v) => MapEntry(k, v?.toString() ?? ''),
        ),
        options: Options(
          headers: {
            if (link.token.isNotEmpty) 'X-Sozo-Bridge-Token': link.token,
          },
        ),
      );
      return resp.data;
    } catch (_) {
      return null;
    }
  }
}
