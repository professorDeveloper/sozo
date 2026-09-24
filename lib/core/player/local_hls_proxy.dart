import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:soplay/core/player/dash_manifest.dart';

class LocalHlsProxy {
  LocalHlsProxy(this._dio);

  static const _sessionTtl = Duration(minutes: 30);
  static const _cleanupInterval = Duration(minutes: 5);

  final Dio _dio;
  HttpServer? _server;
  int? _port;
  Timer? _cleanupTimer;
  final Map<String, _Session> _sessions = {};

  @visibleForTesting
  int? get debugPort => _port;

  Future<String> register({
    required String upstreamUrl,
    required Map<String, String> headers,
    Map<String, dynamic> localProxy = const {},
    Map<String, dynamic> requestTransform = const {},
    // A DASH stream served with only this video Representation left in its
    // manifest — how a DASH quality is picked, since neither engine exposes
    // DASH track selection.
    String? dashRepresentation,
  }) async {
    await _ensureStarted();
    final id = _randomId();
    final parsed = Uri.parse(upstreamUrl);
    final lastSlash = parsed.path.lastIndexOf('/');
    final basePath = lastSlash >= 0 ? parsed.path.substring(0, lastSlash) : '';
    _sessions[id] = _Session(
      origin: '${parsed.scheme}://${parsed.authority}',
      basePath: basePath,
      cdnQuery: parsed.query,
      headers: Map<String, String>.from(headers),
      transform: _RequestTransform.fromMaps(
        localProxy: localProxy,
        requestTransform: requestTransform,
      ),
      lastAccess: DateTime.now(),
      dashRepresentation: dashRepresentation,
    );
    final query = parsed.hasQuery ? '?${parsed.query}' : '';
    return 'http://127.0.0.1:$_port/hls/$id${parsed.path}$query';
  }

  Future<void> dispose() async {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    await _server?.close(force: true);
    _server = null;
    _port = null;
    _sessions.clear();
  }

  Future<void> _ensureStarted() async {
    if (_server != null) return;
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _port = _server!.port;
    debugPrint('[HLS_PROXY] listening on 127.0.0.1:$_port');
    _server!.listen(
      _handle,
      onError: (Object e) {
        debugPrint('[HLS_PROXY] server error: $e');
      },
    );
    _cleanupTimer = Timer.periodic(_cleanupInterval, (_) => _evictStale());
  }

  void _evictStale() {
    final now = DateTime.now();
    _sessions.removeWhere((_, s) => now.difference(s.lastAccess) > _sessionTtl);
  }

  Future<void> _handle(HttpRequest req) async {
    final path = req.requestedUri.path;
    final match = RegExp(r'^/hls/([a-f0-9]+)(/.*)$').firstMatch(path);
    if (match == null) {
      await _reject(req, 404);
      return;
    }
    final sid = match.group(1)!;
    var cdnPath = match.group(2)!;
    final sess = _sessions[sid];
    if (sess == null) {
      await _reject(req, 410);
      return;
    }
    sess.lastAccess = DateTime.now();

    var origin = sess.origin;
    final hMatch = RegExp(r'^/_h/([A-Za-z0-9_-]+)(/.*)$').firstMatch(cdnPath);
    if (hMatch != null) {
      try {
        origin = 'https://${_b64UrlDecode(hMatch.group(1)!)}';
        cdnPath = hMatch.group(2)!;
      } catch (_) {
        await _reject(req, 400);
        return;
      }
    }

    final resolved = cdnPath.startsWith(sess.basePath) || origin != sess.origin
        ? cdnPath
        : '${sess.basePath}$cdnPath';
    final queryString = req.requestedUri.hasQuery
        ? '?${req.requestedUri.query}'
        : (origin == sess.origin && sess.cdnQuery.isNotEmpty
              ? '?${sess.cdnQuery}'
              : '');
    final upstreamUrl = '$origin$resolved$queryString';

    final upstreamHeaders = <String, String>{};
    final keepOriginHeaders = sess.transform?.keepsOriginHeaders == true;
    sess.headers.forEach((k, v) {
      final lower = k.toLowerCase();
      if (lower == 'host' ||
          lower == 'content-length' ||
          (!keepOriginHeaders && (lower == 'origin' || lower == 'referer'))) {
        return;
      }
      upstreamHeaders[k] = v;
    });
    _forwardIncomingHeader(req, upstreamHeaders, 'range', 'Range');
    _forwardIncomingHeader(req, upstreamHeaders, 'if-range', 'If-Range');
    upstreamHeaders.putIfAbsent('Accept-Encoding', () => 'identity');

    try {
      final transformed = sess.transform?.apply(
        origin: origin,
        logicalPath: resolved,
        headers: upstreamHeaders,
      );
      final requestUrl = transformed?.url ?? upstreamUrl;
      final requestHeaders = transformed?.headers ?? upstreamHeaders;
      final resp = await _dio.get<ResponseBody>(
        requestUrl,
        options: Options(
          headers: requestHeaders,
          responseType: ResponseType.stream,
          followRedirects: true,
          validateStatus: (_) => true,
        ),
      );
      final status = resp.statusCode ?? 502;
      if (status >= 400) {
        debugPrint(
          '[HLS_PROXY] upstream $status: $upstreamUrl '
          'sent=${requestHeaders.keys.toList()}',
        );
        final errorBody = resp.data;
        if (errorBody != null) {
          await errorBody.stream.drain<void>();
        }
        await _reject(req, status);
        return;
      }

      final contentType = (resp.headers.value('content-type') ?? '')
          .toLowerCase();
      final isManifest =
          contentType.contains('mpegurl') ||
          contentType.contains('m3u8') ||
          resolved.endsWith('.m3u8');
      final isDash =
          contentType.contains('dash+xml') || resolved.endsWith('.mpd');
      final body = resp.data;
      if (body == null) {
        await _reject(req, 502);
        return;
      }

      if (isDash) {
        final bytes = <int>[];
        await for (final chunk in body.stream) {
          bytes.addAll(chunk);
        }
        if (origin == sess.origin) {
          final lastSlash = resolved.lastIndexOf('/');
          if (lastSlash >= 0) sess.basePath = resolved.substring(0, lastSlash);
        }
        final text = utf8.decode(bytes, allowMalformed: true);
        final narrowed = DashManifest.narrow(
          text,
          keepId: sess.dashRepresentation,
          rewriteUrl: (abs) => _proxyPath(
            abs,
            base: '/hls/$sid',
            sessionOrigin: sess.origin,
            upstreamUrl: upstreamUrl,
          ),
        );
        req.response.headers.contentType = ContentType(
          'application',
          'dash+xml',
        );
        req.response.add(utf8.encode(narrowed));
        await req.response.close();
        return;
      }

      if (isManifest) {
        final bytes = <int>[];
        await for (final chunk in body.stream) {
          bytes.addAll(chunk);
        }
        if (origin == sess.origin) {
          final lastSlash = resolved.lastIndexOf('/');
          if (lastSlash >= 0) {
            sess.basePath = resolved.substring(0, lastSlash);
          }
        }
        final text = utf8.decode(bytes, allowMalformed: true);
        String rewritten;
        try {
          rewritten = _rewriteM3u8(
            text,
            base: '/hls/$sid',
            sessionOrigin: sess.origin,
            upstreamUrl: upstreamUrl,
          );
        } catch (e, st) {
          debugPrint('[HLS_PROXY] rewrite error: $e\n$st');
          rewritten = text;
        }
        req.response.headers.contentType = ContentType(
          'application',
          'vnd.apple.mpegurl',
        );
        req.response.add(utf8.encode(rewritten));
      } else {
        req.response.statusCode = status;
        if (contentType.isNotEmpty) {
          req.response.headers.set(HttpHeaders.contentTypeHeader, contentType);
        }
        _copyHeader(resp, req, 'content-length');
        _copyHeader(resp, req, 'content-range');
        _copyHeader(resp, req, 'accept-ranges');
        _copyHeader(resp, req, 'cache-control');
        _copyHeader(resp, req, 'etag');
        _copyHeader(resp, req, 'last-modified');
        await req.response.addStream(body.stream);
      }
      await req.response.close();
    } catch (e) {
      debugPrint('[HLS_PROXY] error: $e');
      await _reject(req, 502);
    }
  }

  void _forwardIncomingHeader(
    HttpRequest req,
    Map<String, String> headers,
    String incomingName,
    String outgoingName,
  ) {
    final value = req.headers.value(incomingName);
    if (value != null && value.isNotEmpty) {
      headers[outgoingName] = value;
    }
  }

  void _copyHeader(Response<dynamic> resp, HttpRequest req, String name) {
    final value = resp.headers.value(name);
    if (value != null && value.isNotEmpty) {
      req.response.headers.set(name, value);
    }
  }

  Future<void> _reject(HttpRequest req, int status) async {
    try {
      req.response.statusCode = status;
      await req.response.close();
    } catch (_) {}
  }

  /// [raw] as a path on this proxy, so the request comes back here and goes
  /// upstream with the session's headers.
  String _proxyPath(
    String raw, {
    required String base,
    required String sessionOrigin,
    required String upstreamUrl,
  }) {
    final trimmed = raw.trim();
    final Uri abs;
    try {
      final parsed = Uri.parse(trimmed);
      abs = parsed.isAbsolute
          ? parsed
          : Uri.parse(upstreamUrl).resolveUri(parsed);
    } catch (_) {
      return raw;
    }
    final query = abs.hasQuery ? '?${abs.query}' : '';
    if (abs.authority == Uri.parse(sessionOrigin).authority) {
      return '$base${abs.path}$query';
    }
    return '$base/_h/${_b64UrlEncode(abs.authority)}${abs.path}$query';
  }

  String _rewriteM3u8(
    String content, {
    required String base,
    required String sessionOrigin,
    required String upstreamUrl,
  }) {
    final sessionAuthority = Uri.parse(sessionOrigin).authority;
    final upstreamUri = Uri.parse(upstreamUrl);

    String rewriteUrl(String raw) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return raw;
      Uri abs;
      try {
        final parsed = Uri.parse(trimmed);
        abs = parsed.isAbsolute ? parsed : upstreamUri.resolveUri(parsed);
      } catch (_) {
        return '$base/$trimmed';
      }
      final query = abs.hasQuery ? '?${abs.query}' : '';
      if (abs.authority == sessionAuthority) {
        return '$base${abs.path}$query';
      }
      final tag = _b64UrlEncode(abs.authority);
      return '$base/_h/$tag${abs.path}$query';
    }

    final keyAttrPattern = RegExp(r'URI="([^"]+)"');
    final lines = content.split('\n');
    final out = <String>[];
    for (final line in lines) {
      final stripped = line.trim();
      if (stripped.isEmpty) {
        out.add(line);
        continue;
      }
      if (stripped.startsWith('#')) {
        out.add(
          line.replaceAllMapped(
            keyAttrPattern,
            (m) => 'URI="${rewriteUrl(m.group(1)!)}"',
          ),
        );
        continue;
      }
      out.add(rewriteUrl(line));
    }
    return out.join('\n');
  }

  static final _hex = '0123456789abcdef';
  static final _rng = Random.secure();

  String _randomId() {
    return List.generate(24, (_) => _hex[_rng.nextInt(16)]).join();
  }

  String _b64UrlEncode(String s) =>
      base64UrlEncode(utf8.encode(s)).replaceAll('=', '');

  String _b64UrlDecode(String s) {
    final padded = s + '=' * ((4 - s.length % 4) % 4);
    return utf8.decode(base64Url.decode(padded));
  }
}

class _TransformedRequest {
  const _TransformedRequest({required this.url, required this.headers});

  final String url;
  final Map<String, String> headers;
}

class _RequestTransform {
  _RequestTransform._({
    required this.type,
    required this.pageHost,
    required this.menuData,
    required this.deviceId,
    required this.firstPathLength,
    required this.secondPathLength,
    required this.extension,
    required this.deviceHeader,
    required this.matchHeader,
    required this.pathHeader,
    required this.targetHost,
  });

  static const _uzmoviType = 'uzmovi-rc4-v1';
  static const _chars =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  static final _rng = Random();

  final String type;
  final String pageHost;
  final String menuData;
  final String deviceId;
  final int firstPathLength;
  final int secondPathLength;
  final String extension;
  final String deviceHeader;
  final String matchHeader;
  final String pathHeader;
  final String? targetHost;

  bool get keepsOriginHeaders => type == _uzmoviType;

  static _RequestTransform? fromMaps({
    required Map<String, dynamic> localProxy,
    required Map<String, dynamic> requestTransform,
  }) {
    final type =
        _string(requestTransform['type']) ??
        _string(localProxy['transform']) ??
        _string(localProxy['type']);
    if (type != _uzmoviType) return null;

    final randomPath =
        _map(requestTransform['randomPath']) ?? _map(localProxy['randomPath']);
    final headerNames =
        _map(requestTransform['headerNames']) ??
        _map(localProxy['headerNames']);
    final pageHost =
        _string(requestTransform['pageHost']) ??
        _string(localProxy['pageHost']) ??
        'uzmovi.net';
    final menuData =
        _string(requestTransform['menuData']) ??
        _string(localProxy['menuData']);
    if (menuData == null || menuData.isEmpty) return null;
    final deviceId = _buildDeviceId(menuData);
    if (deviceId == null) return null;

    return _RequestTransform._(
      type: _uzmoviType,
      pageHost: pageHost,
      menuData: menuData,
      deviceId: deviceId,
      firstPathLength: _int(randomPath?['first']) ?? 30,
      secondPathLength: _int(randomPath?['second']) ?? 10,
      extension: _string(randomPath?['extension']) ?? '.mpd',
      deviceHeader: _string(headerNames?['deviceId']) ?? 'X-ATT-DeviceId',
      matchHeader: _string(headerNames?['match']) ?? 'X-Match',
      pathHeader: _string(headerNames?['path']) ?? 'X-Path',
      targetHost: _string(localProxy['targetHost']),
    );
  }

  _TransformedRequest? apply({
    required String origin,
    required String logicalPath,
    required Map<String, String> headers,
  }) {
    if (type != _uzmoviType) return null;
    final host = Uri.tryParse(origin)?.host.toLowerCase();
    final expected = targetHost?.toLowerCase();
    final isUzdown = host != null && host.endsWith('uzdown.space');
    final isTarget = expected != null && expected.isNotEmpty
        ? host == expected || isUzdown
        : isUzdown;
    if (!isTarget) return null;

    final requestUrl =
        '$origin/${_randomToken(firstPathLength)}/'
        '${_randomToken(secondPathLength)}$extension';
    final now = DateTime.now().millisecondsSinceEpoch;
    final matchPayload = jsonEncode({'path': logicalPath, 'time': now});

    final nextHeaders = Map<String, String>.from(headers);
    nextHeaders[deviceHeader] = deviceId;
    nextHeaders[matchHeader] = base64.encode(
      _rc4Bytes(pageHost, utf8.encode(matchPayload)),
    );
    nextHeaders[pathHeader] = _randomToken(40);
    return _TransformedRequest(url: requestUrl, headers: nextHeaders);
  }

  static String _randomToken(int length) {
    final safeLength = length <= 0 ? 1 : length;
    return List.generate(
      safeLength,
      (_) => _chars[_rng.nextInt(_chars.length)],
    ).join();
  }

  static String? _buildDeviceId(String menuData) {
    try {
      return base64.encode(_rc4Bytes('movie', _decodeBase64Flexible(menuData)));
    } catch (_) {
      return null;
    }
  }

  static List<int> _rc4Bytes(String key, List<int> input) {
    final keyBytes = utf8.encode(key);
    final state = List<int>.generate(256, (i) => i);
    var j = 0;
    for (var i = 0; i < 256; i++) {
      j = (j + state[i] + keyBytes[i % keyBytes.length]) & 0xff;
      final tmp = state[i];
      state[i] = state[j];
      state[j] = tmp;
    }

    final out = List<int>.filled(input.length, 0);
    var i = 0;
    j = 0;
    for (var n = 0; n < input.length; n++) {
      i = (i + 1) & 0xff;
      j = (j + state[i]) & 0xff;
      final tmp = state[i];
      state[i] = state[j];
      state[j] = tmp;
      final k = state[(state[i] + state[j]) & 0xff];
      out[n] = input[n] ^ k;
    }
    return out;
  }

  static List<int> _decodeBase64Flexible(String value) {
    final normalized = value.trim().replaceAll('-', '+').replaceAll('_', '/');
    final padded = normalized + '=' * ((4 - normalized.length % 4) % 4);
    return base64.decode(padded);
  }

  static Map<String, dynamic>? _map(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is! Map) return null;
    final out = <String, dynamic>{};
    raw.forEach((k, v) {
      if (k is String) out[k] = v;
    });
    return out;
  }

  static String? _string(dynamic raw) {
    if (raw == null) return null;
    final value = raw.toString();
    return value.isEmpty ? null : value;
  }

  static int? _int(dynamic raw) {
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '');
  }
}

class _Session {
  _Session({
    required this.origin,
    required this.basePath,
    required this.cdnQuery,
    required this.headers,
    required this.transform,
    required this.lastAccess,
    this.dashRepresentation,
  });

  final String? dashRepresentation;
  final String origin;
  String basePath;
  final String cdnQuery;
  final Map<String, String> headers;
  final _RequestTransform? transform;
  DateTime lastAccess;
}
