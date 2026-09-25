import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';

class SafeCookieManager extends Interceptor {
  SafeCookieManager(this.cookieJar);

  final CookieJar cookieJar;

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    try {
      final cookies = await cookieJar.loadForRequest(options.uri);
      final header = _formatCookies(cookies);
      if (header.isNotEmpty) {
        final existing = options.headers[HttpHeaders.cookieHeader];
        options.headers[HttpHeaders.cookieHeader] =
            existing is String && existing.isNotEmpty
            ? '$existing; $header'
            : header;
      }
    } catch (_) {}
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) async {
    try {
      await _saveCookies(response);
    } catch (_) {}
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final res = err.response;
    if (res != null) {
      try {
        await _saveCookies(res);
      } catch (_) {}
    }
    handler.next(err);
  }

  Future<void> _saveCookies(Response response) async {
    final raw = response.headers[HttpHeaders.setCookieHeader];
    if (raw == null || raw.isEmpty) return;
    final realUri = response.realUri;
    final parsed = <Cookie>[];
    for (final value in raw) {
      final cookie = _safeParse(value);
      if (cookie != null) parsed.add(cookie);
    }
    if (parsed.isEmpty) return;
    await cookieJar.saveFromResponse(realUri, parsed);
  }

  Cookie? _safeParse(String value) {
    try {
      return Cookie.fromSetCookieValue(value);
    } catch (_) {
      return _parseSanitized(value);
    }
  }

  Cookie? _parseSanitized(String value) {
    final sanitized = _stripBadAttributes(value);
    if (sanitized == null) return null;
    try {
      return Cookie.fromSetCookieValue(sanitized);
    } catch (_) {
      return null;
    }
  }

  String? _stripBadAttributes(String value) {
    final parts = value.split(';');
    if (parts.isEmpty) return null;
    final kept = <String>[parts.first];
    for (var i = 1; i < parts.length; i++) {
      final attr = parts[i].trim();
      if (attr.isEmpty) continue;
      final lower = attr.toLowerCase();
      if (lower.startsWith('secure=') || lower == 'secure') {
        kept.add('Secure');
        continue;
      }
      if (lower.startsWith('httponly=') || lower == 'httponly') {
        kept.add('HttpOnly');
        continue;
      }
      if (lower.startsWith('samesite')) {
        kept.add(attr);
        continue;
      }
      kept.add(attr);
    }
    return kept.join('; ');
  }

  String _formatCookies(List<Cookie> cookies) {
    return cookies
        .where((c) => c.name.isNotEmpty)
        .map((c) => '${c.name}=${c.value}')
        .join('; ');
  }
}
