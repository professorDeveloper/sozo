import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:soplay/core/network/user_agent.dart';
import 'package:soplay/core/network/external_dio.dart';

/// A source's file that the device has to sign for itself before playing.
///
/// Some hosts (asilmedia's fayllar1) hand out a file only through a signed
/// URL whose token is bound to the User-Agent and the IP address that asked
/// for it. The server cannot sign on the phone's behalf — its token would be
/// for its own address — so it sends this instead: where to ask, under which
/// query parameter the file goes, and with what headers. The answer is a JSON
/// map from the file as sent to its signed URL.
class UrlSigner {
  const UrlSigner({
    required this.url,
    required this.param,
    this.headers = const {},
  });

  final String url;
  final String param;
  final Map<String, String> headers;

  static UrlSigner? fromJson(Map<String, dynamic> json) {
    final url = json['url'];
    final param = json['param'];
    if (url is! String || url.isEmpty || param is! String || param.isEmpty) {
      return null;
    }
    final raw = json['headers'];
    return UrlSigner(
      url: url,
      param: param,
      headers: raw is Map
          ? {
              for (final e in raw.entries)
                if (e.value != null) '${e.key}': '${e.value}',
            }
          : const {},
    );
  }

  /// Signed URLs already fetched, by file and User-Agent. Short-lived: the
  /// tokens expire, and a retry after that must ask again.
  static final Map<String, (String, DateTime)> _cache = {};
  static const _keep = Duration(minutes: 20);

  /// The signed URL for [file], asked with [playerHeaders]' User-Agent — the
  /// one the player will send, which the token is bound to. Null when the
  /// host would not sign it; the caller then plays the file as it was.
  Future<String?> sign(String file, Map<String, String> playerHeaders) async {
    final ua = _header(playerHeaders, 'User-Agent') ?? kSozoUserAgent;
    final key = '$file\u0000$ua';
    final now = DateTime.now();
    final held = _cache[key];
    if (held != null && now.difference(held.$2) < _keep) return held.$1;
    try {
      final uri = Uri.parse(url);
      final query = {
        ...uri.queryParameters,
        // Decoded as the page itself sends it: the host keys its answer by
        // the file exactly as asked, and either form is accepted.
        param: Uri.decodeFull(file),
      };
      final res = await ExternalDio.instance.get<String>(
        uri.replace(queryParameters: query).toString(),
        options: Options(
          headers: {...headers, 'User-Agent': ua},
          responseType: ResponseType.plain,
          validateStatus: (_) => true,
          receiveTimeout: const Duration(seconds: 8),
          extra: const {'skipAuthInterceptor': true},
        ),
      );
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.data ?? '');
      final signed = switch (body) {
        Map() => body.values.whereType<String>().firstOrNull,
        List() => body.whereType<String>().firstOrNull,
        String() => body,
        _ => null,
      };
      if (signed == null || !signed.startsWith('http')) return null;
      if (_cache.length > 64) _cache.clear();
      _cache[key] = (signed, now);
      return signed;
    } catch (_) {
      return null;
    }
  }

  static String? _header(Map<String, String> headers, String name) {
    final lower = name.toLowerCase();
    for (final e in headers.entries) {
      if (e.key.toLowerCase() == lower) return e.value;
    }
    return null;
  }
}
