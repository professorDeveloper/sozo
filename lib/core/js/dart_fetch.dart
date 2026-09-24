import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:soplay/core/network/private_address.dart';
import 'package:soplay/core/network/user_agent.dart';
import 'package:soplay/core/network/http_headers.dart';

import '../network/cf_bypass_service.dart';
import 'js_log.dart';
import 'safe_cookie_manager.dart';

class DartFetch {
  final Dio _dio;
  final CfBypassService? _cfService;
  final Dio? _backendDio;

  final Map<String, String> _savedCookies = {};

  /// The image widget uses a different HTTP client. Export only cookies whose
  /// domain/path match this image, retaining the clearance cookie's user agent.
  Future<Map<String, String>> headersForImage(
    String url,
    Map<String, String> provided,
  ) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !['http', 'https'].contains(uri.scheme)) return provided;
    final cookies = <String, String>{};
    for (final manager in _dio.interceptors.whereType<SafeCookieManager>()) {
      for (final cookie in await manager.cookieJar.loadForRequest(uri)) {
        cookies[cookie.name] = cookie.value;
      }
    }
    final clearance = _savedCookies[uri.host];
    final explicit = provided.entries
        .where((entry) => entry.key.toLowerCase() == 'cookie')
        .map((entry) => entry.value);
    for (final header in [?clearance, ...explicit]) {
      for (final part in header.split(';')) {
        final index = part.indexOf('=');
        if (index > 0) {
          cookies[part.substring(0, index).trim()] = part
              .substring(index + 1)
              .trim();
        }
      }
    }
    return mergeHttpHeaders([
      provided,
      {
        if (cookies.isNotEmpty)
          'Cookie': cookies.entries
              .map((e) => '${e.key}=${e.value}')
              .join('; '),
        if (clearance != null) 'User-Agent': kSozoUserAgent,
      },
    ]);
  }

  /// Bounded binary downloads for EPUB host helpers; uses the same cookie jar.
  Future<Uint8List> fetchBytes(
    String url,
    Map<String, String> headers, {
    int maxBytes = 32 * 1024 * 1024,
  }) async {
    final target = Uri.tryParse(url);
    if (target == null ||
        !['https', 'http'].contains(target.scheme) ||
        PrivateAddress.isObviouslyPrivate(target) ||
        await PrivateAddress.resolvesPrivate(target.host)) {
      throw StateError('EPUB URL is not a public HTTP address');
    }
    final requestHeaders = Map<String, String>.from(headers);
    final clearance = _savedCookies[target.host];
    if (clearance != null) {
      requestHeaders.removeWhere((key, _) => key.toLowerCase() == 'user-agent');
      requestHeaders['User-Agent'] = kSozoUserAgent;
      final cookieKey = requestHeaders.keys
          .where((k) => k.toLowerCase() == 'cookie')
          .firstOrNull;
      final existing = cookieKey == null
          ? null
          : requestHeaders.remove(cookieKey);
      requestHeaders['Cookie'] = existing == null
          ? clearance
          : '$clearance; $existing';
    }
    final cancel = CancelToken();
    Future<Uint8List> download() async {
      final response = await _dio.get<ResponseBody>(
        url,
        cancelToken: cancel,
        options: Options(
          headers: requestHeaders,
          responseType: ResponseType.stream,
          validateStatus: (status) =>
              status != null && status >= 200 && status < 300,
          receiveDataWhenStatusError: false,
        ),
      );
      final body = response.data!;
      final length = int.tryParse(
        body.headers['content-length']?.firstOrNull ?? '',
      );
      if (length != null && length > maxBytes) {
        cancel.cancel('EPUB exceeds size limit');
        throw StateError('EPUB is larger than ${maxBytes ~/ (1024 * 1024)} MB');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in body.stream) {
        if (bytes.length + chunk.length > maxBytes) {
          cancel.cancel('EPUB exceeds size limit');
          throw StateError(
            'EPUB is larger than ${maxBytes ~/ (1024 * 1024)} MB',
          );
        }
        bytes.add(chunk);
      }
      return bytes.takeBytes();
    }

    try {
      return await download().timeout(const Duration(seconds: 55));
    } on TimeoutException {
      cancel.cancel('EPUB download timed out');
      rethrow;
    }
  }

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

  /// Every refusal and challenge, numbered, for callers that run concurrently.
  ///
  /// [_lastBlock] and a single pending host are one slot shared by every call
  /// in flight: cross-search runs several providers at once through this one
  /// fetch, so one call's `clearBlock()` wiped the refusal another had just
  /// met, and two challenged hosts overwrote each other so only one was ever
  /// solved. The JavaScript side cannot say which call a fetch belongs to, so
  /// a caller takes a [mark] when it starts and reads only what was recorded
  /// after it — preferring hosts it knows are its own (see [blockSince]).
  int _seq = 0;
  final List<_FetchEvent> _events = [];
  static const int _maxEvents = 64;

  /// Solves already running, so concurrent calls challenged by the same host
  /// share one WebView instead of each opening their own.
  final Map<String, Future<bool>> _solving = {};

  /// A position in the event log; see [blockSince] and [cfHostsSince].
  int mark() => _seq;

  void _record(String? host, String message, {bool cf = false}) {
    _lastBlock = message;
    _events.add(_FetchEvent(++_seq, host, message, cf));
    if (_events.length > _maxEvents) _events.removeAt(0);
  }

  /// The refusal to blame for a call that started at [mark], or null.
  ///
  /// With [preferHosts] (the provider's own domains), a refusal from one of
  /// them wins over one from a host some other call in flight was using.
  String? blockSince(int mark, {Iterable<String> preferHosts = const []}) {
    final since = _events.where((e) => e.seq > mark).toList();
    if (since.isEmpty) return null;
    final prefer = preferHosts
        .map((h) => h.toLowerCase().replaceFirst(RegExp(r'^www\.'), ''))
        .where((h) => h.isNotEmpty)
        .toList();
    if (prefer.isNotEmpty) {
      for (final e in since.reversed) {
        final host = (e.host ?? '').toLowerCase();
        if (prefer.any((d) => host == d || host.endsWith('.$d'))) {
          return e.message;
        }
      }
    }
    return since.last.message;
  }

  /// Hosts that answered with a Cloudflare challenge after [mark] and are
  /// still unsolved.
  Set<String> cfHostsSince(int mark) => {
    for (final e in _events)
      if (e.seq > mark && e.cf && e.host != null && _pendingCf.contains(e.host))
        e.host!,
  };

  /// Solves each of [hosts] once — joining a solve already in progress for
  /// the same host. True when at least one clearance was obtained.
  Future<bool> solveCfHosts(Iterable<String> hosts) async {
    var any = false;
    for (final host in hosts.toSet()) {
      final running = _solving[host] ??= _solveHost(host).whenComplete(() {
        _solving.remove(host);
      });
      if (await running) any = true;
    }
    return any;
  }

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
  final Set<String> _pendingCf = <String>{};

  bool get hasPendingCfChallenge => _pendingCf.isNotEmpty;

  /// The host of that challenge, for the *manual* solve.
  ///
  /// The button on the error screen has nothing but a provider id to go on, and
  /// an extension routinely fetches from an API or CDN host its metadata never
  /// mentions — TeamX is configured as `olympustaff.com` and reads from it, but
  /// plenty of sources are not so tidy. The host that actually came back
  /// challenged is the one to send a WebView to.
  String? get pendingCfHost => _pendingCf.isEmpty ? null : _pendingCf.last;

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
    _pendingCf.remove(host);
    _lastBlock = null;
    unawaited(_pushCookiesToBackend(host, cookieHeader));
    return true;
  }

  /// Solve the most recently recorded challenge. Returns whether a clearance
  /// was obtained. Kept for callers that run one call at a time; concurrent
  /// ones use [cfHostsSince] and [solveCfHosts].
  Future<bool> solvePendingCfChallenge() async {
    final host = pendingCfHost;
    if (host == null) return false;
    return solveCfHosts([host]);
  }

  Future<bool> _solveHost(String host) async {
    _pendingCf.remove(host);
    final cf = _cfService;
    if (cf == null) return false;
    JsLog.req('fetch', 'CF challenge on $host — solving …');
    final cookieHeader = await cf.solve(
      host: host,
      url: 'https://$host/',
      userAgent: kSozoUserAgent,
    );
    if (cookieHeader == null) return false;
    _savedCookies[host] = cookieHeader;
    unawaited(_pushCookiesToBackend(host, cookieHeader));
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
    final target = Uri.tryParse(req.url);
    if (target == null ||
        PrivateAddress.isObviouslyPrivate(target) ||
        await PrivateAddress.resolvesPrivate(target.host)) {
      JsLog.err('fetch', 'refused private address ${_shortUrl(req.url)}');
      _record(
        host,
        '${host ?? 'address'} is on the local network and was not fetched',
      );
      return const {'status': 0, 'data': null, 'headers': {}};
    }
    final extraHeaders = Map<String, String>.from(req.headers);
    if (host != null) {
      final cached = _savedCookies[host];
      if (cached != null) {
        final existing = extraHeaders['Cookie'] ?? extraHeaders['cookie'];
        extraHeaders['Cookie'] = existing != null
            ? '$cached; $existing'
            : cached;
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
        // Record, do not solve — see [_pendingCf]. The cookie just sent is
        // the one that got challenged, so it is dead either way.
        _savedCookies.remove(host);
        _pendingCf.remove(host);
        _pendingCf.add(host);
      }

      if (_looksLikeCfChallenge(status, headers, response.data)) {
        _record(
          host,
          '${host ?? 'server'} is behind a Cloudflare challenge',
          cf: true,
        );
      } else if (status >= 400) {
        _record(host, '${host ?? 'server'} refused the request ($status)');
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
        // Where the redirects ended, which plugins read as `response.url`.
        'url': response.realUri.toString(),
      };
    } catch (e) {
      JsLog.err('fetch', '${req.method} ${_shortUrl(req.url)} — $e');
      _record(host, '${host ?? 'network'}: ${_shortError(e)}');
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

  bool _looksLikeCfChallenge(
    int status,
    Map<String, String> headers,
    String? body,
  ) {
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

  /// Shares a clearance with the backend so its own scrapers can use it.
  ///
  /// `cf_clearance` is only honoured together with the User-Agent that earned
  /// it, and every clearance here is earned under the app's own agent
  /// ([kSozoUserAgent] — the solve and the replay both send it). This used to
  /// pass an empty header map, so the backend was told the agent was '' and
  /// replayed the cookie under its own, which Cloudflare rejects.
  Future<void> _pushCookiesToBackend(String host, String cookies) async {
    final dio = _backendDio;
    if (dio == null) return;
    try {
      await dio.post(
        '/cf-cookies',
        data: {'host': host, 'cookies': cookies, 'userAgent': kSozoUserAgent},
        options: Options(extra: const {'skipCfBypassInterceptor': true}),
      );
    } catch (_) {}
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
    return _Request(method: method, url: url, headers: headers, body: body);
  }

  dynamic _decodeBody(String? data, String? contentType) {
    if (data == null || data.isEmpty) return data;
    if (contentType != null &&
        contentType.toLowerCase().contains('application/json')) {
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
}

class _FetchEvent {
  const _FetchEvent(this.seq, this.host, this.message, this.cf);

  final int seq;
  final String? host;
  final String message;
  final bool cf;
}
