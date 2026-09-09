import 'dart:async';
import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:soplay/core/network/user_agent.dart';

import '../network/cf_bypass_service.dart';
import 'js_log.dart';
import 'safe_cookie_manager.dart';

class DartFetch {
  final Dio _dio;
  final CfBypassService? _cfService;
  final Dio? _backendDio;

  final Map<String, String> _savedCookies = {};

  /// The last request the network refused outright.
  ///
  /// Extensions parse whatever body they are handed, so a 403 or an unsolved
  /// challenge page reaches them as "nothing matched" rather than as a failure.
  /// Remembering it here is the only place that can still tell the two apart by
  /// the time a caller sees an empty list.
  String? _lastBlock;

  String? takeBlock() {
    final block = _lastBlock;
    _lastBlock = null;
    return block;
  }

  void clearBlock() => _lastBlock = null;

  /// Host whose Cloudflare challenge still needs solving, if any.
  ///
  /// The solve deliberately does NOT happen inside [_send]. An extractor's
  /// fetch runs inside a JavaScript handler of the runtime WebView, and that
  /// handler's reply travels the same platform channel a headless WebView needs
  /// in order to be created and run. Solving there meant the reply could not be
  /// delivered until the solve finished and the solve could not finish until the
  /// channel was free: `solved animepahe.pw (16810ms)` in the log, then the
  /// caller waiting out its whole 60s timeout on a challenge that had already
  /// passed. It read as a Heisenbug — adding a log statement near the completion
  /// was enough to jog the channel and let the call through.
  ///
  /// So [_send] only records the host here and lets the challenged response go
  /// back to JS. Whoever drives the call solves afterwards, outside the handler,
  /// and runs it again.
  String? _pendingCfHost;

  bool get hasPendingCfChallenge => _pendingCfHost != null;

  /// The host of that challenge, for the *manual* solve.
  ///
  /// The button on the error screen has nothing but a provider id to go on, and
  /// an extension routinely fetches from an API or CDN host its metadata never
  /// mentions — TeamX is configured as `olympustaff.com` and reads from it, but
  /// plenty of sources are not so tidy. The host that actually came back
  /// challenged is the one to send a WebView to.
  String? get pendingCfHost => _pendingCfHost;

  /// Take on a clearance earned outside this class, and report whether there
  /// was one to take.
  ///
  /// [solvePendingCfChallenge] does its work headlessly, which cannot answer a
  /// challenge that wants a person — a checkbox, a captcha. Those go to the
  /// interactive `CloudflareSolverPage` and its visible WebView, and the cookie
  /// it earns lands in the *WebView's* jar. Dio keeps its own, entirely
  /// separate one here, so until the value is copied across [_send] cannot see
  /// it: the solver page popped `true`, the caller reloaded, and the identical
  /// challenge came straight back.
  Future<bool> adoptSolvedClearance(String host) async {
    final cf = _cfService;
    if (cf == null) return false;
    final cookieHeader = await cf.readClearance(host);
    if (cookieHeader == null) return false;
    JsLog.res('fetch', 'adopted a clearance for $host');
    _savedCookies[host] = cookieHeader;
    // The recorded challenge is answered; leaving it would send the next
    // automatic solve after a host that is already cleared.
    if (_pendingCfHost == host) _pendingCfHost = null;
    _lastBlock = null;
    unawaited(_pushCookiesToBackend(host, cookieHeader, const {}));
    return true;
  }

  /// Solve the recorded challenge. Returns whether a clearance was obtained.
  Future<bool> solvePendingCfChallenge() async {
    final host = _pendingCfHost;
    _pendingCfHost = null;
    final cf = _cfService;
    if (host == null || cf == null) return false;
    JsLog.req('fetch', 'CF challenge on $host — solving …');
    final cookieHeader = await cf.solve(
      host: host,
      url: 'https://$host/',
      userAgent: kSozoUserAgent,
    );
    if (cookieHeader == null) return false;
    _savedCookies[host] = cookieHeader;
    unawaited(_pushCookiesToBackend(host, cookieHeader, const {}));
    return true;
  }

  DartFetch._(this._dio, this._cfService, this._backendDio);

  Dio get dio => _dio;

  factory DartFetch.create({CfBypassService? cfService, Dio? backendDio}) {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        sendTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 20),
        followRedirects: true,
        maxRedirects: 10,
        validateStatus: (_) => true,
        responseType: ResponseType.plain,
        // Without this dart:io stamps `Dart/3.x (dart:io)` on every extension
        // request, which Cloudflare refuses outright.
        headers: {'User-Agent': kSozoUserAgent},
      ),
    )..interceptors.add(SafeCookieManager(CookieJar()));
    return DartFetch._(dio, cfService, backendDio);
  }

  Future<Map<String, dynamic>> call(dynamic raw) async {
    final req = _coerceRequest(raw);
    if (req == null) {
      return const {'status': 0, 'data': null, 'headers': {}};
    }
    return _send(req, allowCfRetry: true);
  }

  Future<Map<String, dynamic>> _send(
    _Request req, {
    required bool allowCfRetry,
  }) async {
    final sw = Stopwatch()..start();
    JsLog.req('fetch', '${req.method} ${_shortUrl(req.url)}');

    final host = _hostOf(req.url);
    final extraHeaders = Map<String, String>.from(req.headers);
    if (host != null) {
      final cached = _savedCookies[host];
      if (cached != null) {
        final existing = extraHeaders['Cookie'] ?? extraHeaders['cookie'];
        extraHeaders['Cookie'] =
            existing != null ? '$cached; $existing' : cached;
        // cf_clearance is bound to the agent that earned it, and it was earned
        // under the app's own. Letting the extractor's agent ride along with
        // the cookie made Cloudflare reissue the challenge on every request
        // after the first — one call solved the challenge three times and still
        // came back empty.
        extraHeaders.remove('user-agent');
        extraHeaders['User-Agent'] = kSozoUserAgent;
      }
    }

    try {
      final response = await _dio.request<String>(
        req.url,
        data: req.body,
        options: Options(
          method: req.method,
          headers: extraHeaders,
          responseType: ResponseType.plain,
          followRedirects: true,
          validateStatus: (_) => true,
        ),
      );
      final headers = <String, String>{};
      response.headers.forEach((k, v) => headers[k] = v.join(','));
      final status = response.statusCode ?? 0;

      final cf = _cfService;
      if (allowCfRetry &&
          host != null &&
          cf != null &&
          _looksLikeCfChallenge(status, headers, response.data)) {
        // Record, do not solve — see [_pendingCfHost]. The cookie just sent is
        // the one that got challenged, so it is dead either way.
        _savedCookies.remove(host);
        _pendingCfHost = host;
      }

      if (_looksLikeCfChallenge(status, headers, response.data)) {
        _lastBlock = '${host ?? 'server'} is behind a Cloudflare challenge';
      } else if (status >= 400) {
        _lastBlock = '${host ?? 'server'} refused the request ($status)';
      }

      JsLog.res(
        'fetch',
        '${req.method} ${_shortUrl(req.url)}',
        status: status,
        ms: sw.elapsedMilliseconds,
      );
      return {
        'status': status,
        'data': _decodeBody(response.data, headers['content-type']),
        'headers': headers,
      };
    } catch (e) {
      JsLog.err('fetch', '${req.method} ${_shortUrl(req.url)} — $e');
      _lastBlock = '${host ?? 'network'}: ${_shortError(e)}';
      return const {'status': 0, 'data': null, 'headers': {}};
    }
  }

  static String _shortError(Object e) {
    if (e is DioException) {
      return switch (e.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout => 'timed out',
        DioExceptionType.connectionError => 'unreachable',
        DioExceptionType.badCertificate => 'bad certificate',
        _ => e.message ?? 'request failed',
      };
    }
    return '$e';
  }

  bool _looksLikeCfChallenge(int status, Map<String, String> headers, String? body) {
    if (status == 428 && body != null && body.contains('cfChallenge')) {
      return true;
    }
    // Cloudflare sets this whenever it interfered, whatever the status.
    if (headers['cf-mitigated']?.isNotEmpty ?? false) return true;
    // A managed challenge is routinely served as 200 or 429. Gating the body
    // sniff on 403/503 alone let those through as a successful response, and
    // the extension then parsed the challenge page and found nothing in it.
    if (status != 403 && status != 503 && status != 429 && status != 200) {
      return false;
    }
    if (status == 200 || status == 429) {
      if (body == null) return false;
      return body.contains('cdn-cgi/challenge-platform') ||
          body.contains('__cf_chl_') ||
          body.contains('Just a moment...');
    }
    final server = (headers['server'] ?? '').toLowerCase();
    if (server.contains('cloudflare')) return true;
    if (body == null) return false;
    return body.contains('cdn-cgi/challenge-platform') ||
        body.contains('__cf_chl_') ||
        body.contains('Just a moment...');
  }

  Future<void> _pushCookiesToBackend(
    String host,
    String cookies,
    Map<String, String> reqHeaders,
  ) async {
    final dio = _backendDio;
    if (dio == null) return;
    try {
      await dio.post(
        '/cf-cookies',
        data: {
          'host': host,
          'cookies': cookies,
          'userAgent': reqHeaders['User-Agent'] ?? reqHeaders['user-agent'] ?? '',
        },
        options: Options(extra: const {'skipCfBypassInterceptor': true}),
      );
    } catch (_) {
    }
  }

  String? _hostOf(String url) {
    try {
      return Uri.parse(url).host;
    } catch (_) {
      return null;
    }
  }

  String _shortUrl(String url) {
    if (url.length <= 90) return url;
    return '${url.substring(0, 80)}…';
  }

  _Request? _coerceRequest(dynamic raw) {
    if (raw is! Map) return null;
    final url = raw['url'] as String?;
    if (url == null || url.isEmpty) return null;
    final method = (raw['method'] as String? ?? 'GET').toUpperCase();
    final headers = <String, String>{};
    final rawHeaders = raw['headers'];
    if (rawHeaders is Map) {
      rawHeaders.forEach((k, v) {
        if (k is String && v != null) headers[k] = v.toString();
      });
    }
    final body = raw['body'];
    return _Request(
      method: method,
      url: url,
      headers: headers,
      body: body,
    );
  }

  dynamic _decodeBody(String? data, String? contentType) {
    if (data == null || data.isEmpty) return data;
    if (contentType != null && contentType.toLowerCase().contains('application/json')) {
      try {
        return jsonDecode(data);
      } catch (_) {
        return data;
      }
    }
    return data;
  }
}

class _Request {
  final String method;
  final String url;
  final Map<String, String> headers;
  final dynamic body;

  const _Request({
    required this.method,
    required this.url,
    required this.headers,
    this.body,
  });

  /// The same request with one header set. Used to replay a Cloudflare-blocked
  /// call under the agent that solved the challenge.
  _Request copyWithHeader(String name, String value) => _Request(
    method: method,
    url: url,
    headers: {...headers, name: value},
    body: body,
  );
}
