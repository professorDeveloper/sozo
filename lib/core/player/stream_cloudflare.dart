import 'package:dio/dio.dart';
import 'package:soplay/core/network/external_dio.dart';

/// What stands between the player and a stream host, as far as Cloudflare is
/// concerned.
enum CloudflareWall {
  /// Nothing of Cloudflare's: the failure is the stream's own.
  none,

  /// A challenge ("Just a moment…", Turnstile, a managed challenge). A browser
  /// that passes it earns a cf_clearance the player can then send — the thing
  /// the app's WebView solver exists for.
  challenge,

  /// A block page ("Sorry, you have been blocked"). Nothing to solve: no
  /// clearance is ever issued for it, so opening a solver would only show the
  /// viewer the same refusal.
  blocked,
}

/// Reads a refusal. Pure, so it can be tested on captured responses.
///
/// Only a 403, 429 or 503 from Cloudflare counts — its `Server` header or a
/// `cf-ray` — so a host's own 403 (an expired token, a missing Referer) is
/// never mistaken for a challenge. `cf-mitigated: challenge` is Cloudflare's
/// own statement and decides it outright; otherwise the page body does.
CloudflareWall classifyCloudflare({
  required int status,
  required Map<String, String> headers,
  required String body,
}) {
  if (status != 403 && status != 429 && status != 503) {
    return CloudflareWall.none;
  }
  String? header(String name) {
    for (final e in headers.entries) {
      if (e.key.toLowerCase() == name) return e.value.toLowerCase();
    }
    return null;
  }

  final fromCloudflare =
      (header('server') ?? '').contains('cloudflare') ||
      header('cf-ray') != null;
  if (!fromCloudflare) return CloudflareWall.none;
  if (header('cf-mitigated') == 'challenge') return CloudflareWall.challenge;

  final page = body.toLowerCase();
  if (page.contains('/cdn-cgi/challenge-platform') ||
      page.contains('cf_chl_') ||
      page.contains('just a moment') ||
      page.contains('challenges.cloudflare.com/turnstile')) {
    return CloudflareWall.challenge;
  }
  if (page.contains('sorry, you have been blocked') ||
      page.contains('attention required!') ||
      page.contains('cf-error-details')) {
    return CloudflareWall.blocked;
  }
  return CloudflareWall.none;
}

/// Asks [uri] once, with the player's [headers], and reads the answer.
///
/// A player engine reports a refused stream as "failed to open" at best, with
/// no status and no page, so the only way to tell a Cloudflare challenge from
/// any other failure is to ask the same way and look. Only the first few KB
/// are read — a challenge page is small, and a stream that answers 200 is not
/// worth downloading here. Any failure to ask is [CloudflareWall.none]: this
/// only ever adds a way out, it never decides a stream is broken.
Future<CloudflareWall> probeCloudflare(
  Uri uri,
  Map<String, String> headers, {
  Dio? dio,
}) async {
  try {
    final res = await (dio ?? ExternalDio.instance).getUri<ResponseBody>(
      uri,
      options: Options(
        headers: {...headers, 'Range': 'bytes=0-16383'},
        responseType: ResponseType.stream,
        validateStatus: (_) => true,
        followRedirects: true,
        receiveTimeout: const Duration(seconds: 8),
        sendTimeout: const Duration(seconds: 8),
        extra: const {'skipAuthInterceptor': true},
      ),
    );
    final status = res.statusCode ?? 0;
    final flat = <String, String>{
      for (final e in res.headers.map.entries) e.key: e.value.join(','),
    };
    // Only a refusal is worth reading; a 200/206 is the stream itself.
    var body = '';
    final stream = res.data?.stream;
    if (stream != null) {
      if (status == 403 || status == 429 || status == 503) {
        final bytes = <int>[];
        await for (final chunk in stream) {
          bytes.addAll(chunk);
          if (bytes.length >= 16384) break;
        }
        body = String.fromCharCodes(bytes);
      } else {
        await stream.listen(null).cancel();
      }
    }
    return classifyCloudflare(status: status, headers: flat, body: body);
  } catch (_) {
    return CloudflareWall.none;
  }
}
