import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter/foundation.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/player/local_hls_proxy.dart';

typedef PreviewInvoke =
    Future<dynamic> Function(String method, Map<String, dynamic>? arguments);

/// Frames for the seek bar, from the platform's own decoders.
///
/// A progressive file goes to MediaMetadataRetriever (Android) or
/// AVFoundation (iOS), as it always has. HLS on Android used to get nothing —
/// the retriever cannot read it, and most streams here are HLS — so it now
/// goes to Media3's FrameExtractor on the same channel, through the app's
/// local proxy (it takes no headers of its own) and at the lightest variant
/// (a 160px thumbnail needs one small rendition, not the ladder).
class FramePreviewService {
  FramePreviewService._();
  static const MethodChannel _ch = MethodChannel('soplay/preview');
  static bool get isSupported => Platform.isAndroid || Platform.isIOS;

  static final _native = FramePreviewSession(
    supported: isSupported,
    invoke: (method, args) => _ch.invokeMethod(method, args),
  );

  /// HLS frames: a playlist and a segment before the first one, so longer
  /// allowances, and kept open between drags on the native side.
  static final _hls = FramePreviewSession(
    supported: Platform.isAndroid,
    invoke: _invokeHls,
    openTimeout: const Duration(seconds: 15),
    frameTimeout: const Duration(seconds: 9),
  );

  static const int bucketMs = FramePreviewSession.bucketMs;

  static Future<Uint8List?> previewFrame(
    String url,
    Map<String, String> headers,
    int positionMs, {
    bool hls = false,
  }) {
    if (hls && Platform.isAndroid) {
      return _hls.previewFrame(url, headers, positionMs);
    }
    return _native.previewFrame(url, headers, positionMs);
  }

  static Future<void> endScrub() async {
    await Future.wait([_native.endScrub(), _hls.endScrub()]);
  }

  static Future<void> close() async {
    await Future.wait([_native.close(), _hls.close()]);
  }

  static Future<dynamic> _invokeHls(
    String method,
    Map<String, dynamic>? args,
  ) async {
    final a = <String, dynamic>{...?args, 'hls': true};
    if (method == 'open') {
      final url = a['url'] as String? ?? '';
      final headers =
          (a['headers'] as Map?)?.cast<String, String>() ?? const {};
      a['url'] = await _proxied(url, headers);
    }
    return _ch.invokeMethod(method, a);
  }

  /// One proxied address per stream, so the native side sees the same URL on
  /// every drag and keeps its extractor instead of rebuilding it.
  static final Map<String, Future<String>> _proxiedCache = {};

  static Future<String> _proxied(String url, Map<String, String> headers) {
    final keys = headers.keys.toList()..sort();
    final key = '$url\u0000${keys.map((k) => '$k=${headers[k]}').join('&')}';
    if (_proxiedCache.length > 8) _proxiedCache.clear();
    return _proxiedCache[key] ??= _proxy(url, headers);
  }

  /// The lightest variant, behind the local proxy so its headers go along.
  static Future<String> _proxy(String url, Map<String, String> headers) async {
    var target = url;
    final uri = Uri.tryParse(url);
    final local = uri != null && uri.host == '127.0.0.1';
    if (!local) {
      target = await _lightestVariant(url, headers) ?? url;
    }
    if (local || headers.isEmpty) return target;
    try {
      return await getIt<LocalHlsProxy>().register(
        upstreamUrl: target,
        headers: headers,
      );
    } catch (_) {
      return target;
    }
  }

  static Future<String?> _lightestVariant(
    String url,
    Map<String, String> headers,
  ) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.scheme.startsWith('http')) return null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await client.getUrl(uri);
      headers.forEach(req.headers.set);
      final res = await req.close().timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final body = await res
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 8));
      return lightestVariantOf(body, uri);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// For an HLS master playlist, its smallest variant; null for anything else.
  ///
  /// Handed a master, a decoder reads every rendition to choose one; a
  /// thumbnail needs only the lightest, so it is chosen here.
  @visibleForTesting
  static String? lightestVariantOf(String playlist, Uri base) {
    if (!playlist.contains('#EXT-X-STREAM-INF')) return null;
    final lines = const LineSplitter().convert(playlist);
    String? best;
    var bestRate = 1 << 62;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (!line.startsWith('#EXT-X-STREAM-INF')) continue;
      final rate =
          int.tryParse(
            RegExp(r'[:,]BANDWIDTH=(\d+)').firstMatch(line)?.group(1) ?? '',
          ) ??
          (1 << 61);
      for (var j = i + 1; j < lines.length; j++) {
        final next = lines[j].trim();
        if (next.isEmpty || next.startsWith('#')) continue;
        if (rate < bestRate) {
          bestRate = rate;
          best = base.resolve(next).toString();
        }
        break;
      }
    }
    return best;
  }
}

/// One decoder request plus the latest pending scrub position. Earlier queued
/// positions are superseded instead of keeping native decoders busy after a drag.
class FramePreviewSession {
  FramePreviewSession({
    required this.supported,
    required this.invoke,
    this.idleTimeout = const Duration(milliseconds: 1500),
    this.openTimeout = const Duration(seconds: 5),
    this.frameTimeout = const Duration(seconds: 3),
    this.maxFrames = 24,
    this.maxCacheBytes = 3 * 1024 * 1024,
  });
  final bool supported;
  final PreviewInvoke invoke;
  final Duration idleTimeout;
  final Duration openTimeout;
  final Duration frameTimeout;
  final int maxFrames;
  final int maxCacheBytes;
  static const int bucketMs = 5000;

  String? _identity;
  String? _url;
  Map<String, String> _headers = {};
  // Survives hot restart without colliding with a previous native generation.
  int _generation = DateTime.now().microsecondsSinceEpoch;
  int? _openedGeneration;
  final _cache = <int, Uint8List>{};
  final _misses = <int, DateTime>{};
  DateTime? _retryOpenAfter;
  int _cacheBytes = 0;
  final _pending = <(int, int), _FrameRequest>{};
  _FrameRequest? _running;
  _FrameRequest? _queued;
  Timer? _idle;

  Future<void> open(String url, Map<String, String> headers) async {
    if (!supported) return;
    final keys = headers.keys.toList()..sort();
    final identity =
        '$url\u0000${jsonEncode({for (final key in keys) key: headers[key]})}';
    if (_identity == identity) return;
    if (_identity != null || _running != null) unawaited(endScrub());
    _generation++;
    _cache.clear();
    _cacheBytes = 0;
    _misses.clear();
    _retryOpenAfter = null;
    _identity = identity;
    _url = url;
    _headers = Map.of(headers);
  }

  Future<Uint8List?> previewFrame(
    String url,
    Map<String, String> headers,
    int positionMs,
  ) async {
    await open(url, headers);
    if (_url != url || !_sameHeaders(headers, _headers)) return null;
    return frame(positionMs);
  }

  bool _sameHeaders(Map<String, String> first, Map<String, String> second) =>
      first.length == second.length &&
      first.entries.every((entry) => second[entry.key] == entry.value);

  Future<Uint8List?> frame(int positionMs) {
    if (!supported || _url == null) return Future.value(null);
    _idle?.cancel();
    final bucket = (positionMs.clamp(0, 1 << 53) ~/ bucketMs) * bucketMs;
    final cached = _cache.remove(bucket);
    if (cached != null) {
      _cache[bucket] = cached;
      _scheduleIdle();
      return Future.value(cached);
    }
    final now = DateTime.now();
    if ((_retryOpenAfter?.isAfter(now) ?? false) ||
        (_misses[bucket]?.isAfter(now) ?? false)) {
      _scheduleIdle();
      return Future.value(null);
    }
    final key = (_generation, bucket);
    final existing = _pending[key];
    if (existing != null) return existing.result.future;
    final request = _FrameRequest(_generation, bucket);
    _pending[key] = request;
    if (_running == null) {
      _run(request);
    } else {
      final superseded = _queued;
      if (superseded != null) _finish(superseded, null);
      _queued = request;
    }
    return request.result.future;
  }

  void _run(_FrameRequest request) async {
    _running = request;
    Uint8List? bytes;
    try {
      if (request.generation != _generation || _url == null) return;
      if (_openedGeneration != request.generation) {
        final opened = await invoke('open', {
          'url': _url,
          'headers': _headers,
          'warmMs': -1,
          'generation': request.generation,
        }).timeout(openTimeout);
        if (request.generation != _generation) return;
        if (opened == false) {
          _retryOpenAfter = DateTime.now().add(const Duration(seconds: 2));
          return;
        }
        _openedGeneration = request.generation;
      }
      final raw = await invoke('frame', {
        'posMs': request.bucket,
        'generation': request.generation,
      }).timeout(frameTimeout);
      if (request.generation != _generation) return;
      bytes = raw is Uint8List ? raw : null;
      if (bytes == null) {
        _misses[request.bucket] = DateTime.now().add(
          const Duration(seconds: 2),
        );
        if (_misses.length > maxFrames) _misses.remove(_misses.keys.first);
      }
      if (bytes != null && bytes.length <= maxCacheBytes) {
        _cache[request.bucket] = bytes;
        _cacheBytes += bytes.length;
        while (_cache.length > maxFrames || _cacheBytes > maxCacheBytes) {
          _cacheBytes -= _cache.remove(_cache.keys.first)!.length;
        }
      }
    } on TimeoutException {
      if (request.generation == _generation) await endScrub();
    } catch (_) {
      if (request.generation == _generation) {
        _openedGeneration = null;
        _retryOpenAfter = DateTime.now().add(const Duration(seconds: 2));
      }
    } finally {
      _finish(request, request.generation == _generation ? bytes : null);
      if (identical(_running, request)) _running = null;
      final next = _queued;
      _queued = null;
      if (next != null && next.generation == _generation) {
        _run(next);
      } else {
        if (next != null) _finish(next, null);
        _scheduleIdle();
      }
    }
  }

  void _finish(_FrameRequest request, Uint8List? bytes) {
    _pending.remove((request.generation, request.bucket));
    if (!request.result.isCompleted) request.result.complete(bytes);
  }

  void _scheduleIdle() {
    _idle?.cancel();
    if (_openedGeneration != null) {
      _idle = Timer(idleTimeout, () {
        unawaited(endScrub());
      });
    }
  }

  /// Drop native resources and pending work as soon as the finger lifts. Cache
  /// remains scoped to the configured source for inexpensive repeated scrubs.
  Future<void> endScrub() async {
    _idle?.cancel();
    _idle = null;
    final closedGeneration = ++_generation;
    _generation++; // A later open must be newer than this asynchronous close.
    _openedGeneration = null;
    for (final request in _pending.values.toList()) {
      _finish(request, null);
    }
    _queued = null;
    if (!supported) return;
    try {
      await invoke('close', {
        'generation': closedGeneration,
      }).timeout(const Duration(seconds: 1));
    } catch (_) {}
  }

  Future<void> close() async {
    _identity = null;
    _url = null;
    _headers = {};
    _cache.clear();
    _cacheBytes = 0;
    _misses.clear();
    _retryOpenAfter = null;
    await endScrub();
  }
}

class _FrameRequest {
  _FrameRequest(this.generation, this.bucket);
  final int generation;
  final int bucket;
  final result = Completer<Uint8List?>();
}
