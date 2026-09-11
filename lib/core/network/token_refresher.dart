import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/network/certificate_pinning.dart';

/// Single-flight JWT freshener for the socket handshake.
///
/// The socket bypasses Dio, and [AuthInterceptor] only refreshes reactively on
/// a 401 — so we proactively refresh when the access token is within 60s of
/// expiry (or when a handshake was rejected). This does NOT touch
/// [AuthInterceptor]; it refreshes on a BARE Dio with no interceptors.
class TokenRefresher {
  TokenRefresher(this._hive);

  final HiveService _hive;
  Dio? _bareDio;
  Future<String?>? _inFlight;

  /// Returns a token valid for > 60s.
  ///
  /// When [force] is true (e.g. after a handshake `unauthorized`) it always
  /// attempts a refresh regardless of the decoded expiry. Returns null if the
  /// user is not logged in, or if a forced refresh fails.
  Future<String?> ensureFresh({bool force = false}) async {
    final token = _hive.getToken();
    if (token == null || token.isEmpty) return null;
    if (!force && !_needsRefresh(token)) return token;

    final refreshed = await (_inFlight ??=
        _performRefresh().whenComplete(() => _inFlight = null));
    if (refreshed != null && refreshed.isNotEmpty) return refreshed;

    // Non-forced refresh failure: fall back to the (still possibly valid)
    // current token so a transient network blip doesn't block connection.
    return force ? null : token;
  }

  bool _needsRefresh(String token) {
    final exp = _decodeExp(token);
    if (exp == null) return false; // can't tell — leave it to the server.
    final expiresAt =
        DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true);
    final threshold = expiresAt.subtract(const Duration(seconds: 60));
    return DateTime.now().toUtc().isAfter(threshold);
  }

  /// Decodes the `exp` (seconds since epoch) from the JWT payload segment.
  int? _decodeExp(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
      switch (payload.length % 4) {
        case 2:
          payload += '==';
          break;
        case 3:
          payload += '=';
          break;
      }
      final decoded = utf8.decode(base64.decode(payload));
      final map = jsonDecode(decoded);
      if (map is Map && map['exp'] is num) {
        return (map['exp'] as num).toInt();
      }
    } catch (_) {}
    return null;
  }

  Future<String?> _performRefresh() async {
    final refreshToken = _hive.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) return null;
    try {
      // Bare so the auth interceptor cannot recurse into another refresh —
      // but pinned like every other request to the API: this one carries the
      // refresh token.
      final dio = _bareDio ??= Dio(BaseOptions(baseUrl: AppConstants.baseUrl))
        ..httpClientAdapter = CertificatePinning.adapter();
      final res = await dio.post(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
      );
      final data = res.data;
      if (data is! Map) return null;
      final newAccess = data['accessToken'] as String? ?? '';
      final newRefresh = data['refreshToken'] as String? ?? refreshToken;
      if (newAccess.isEmpty) return null;
      await _hive.saveTokens(accessToken: newAccess, refreshToken: newRefresh);
      return newAccess;
    } catch (_) {
      return null;
    }
  }
}
