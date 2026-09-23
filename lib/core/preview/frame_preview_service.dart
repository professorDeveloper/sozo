import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import 'package:soplay/core/preview/mpv_frame_preview.dart';

typedef PreviewInvoke =
    Future<dynamic> Function(String method, Map<String, dynamic>? arguments);

/// Frames for the seek bar, from whichever decoder can open the stream.
///
/// Two backends behind one call. The platform one — `MediaMetadataRetriever`
/// on Android, AVFoundation on iOS — is cheap and exact for a progressive
/// file. It cannot read HLS on Android, and there is none on desktop, so those
/// go to [MpvFramePreview], a silent second libmpv; a progressive file the
/// platform decoder fails on goes there too. Between them every stream the
/// app plays gets a preview, except a torrent (see the player's gate).
class FramePreviewService {
  FramePreviewService._();
  static const MethodChannel _ch = MethodChannel('soplay/preview');

  static bool get _hasNative => Platform.isAndroid || Platform.isIOS;

  /// libmpv ships everywhere but iOS.
  static bool get _hasMpv =>
      Platform.isAndroid ||
      Platform.isMacOS ||
      Platform.isWindows ||
      Platform.isLinux;

  static bool get isSupported => _hasNative || _hasMpv;

  static final _native = FramePreviewSession(
    supported: _hasNative,
    invoke: (method, args) => _ch.invokeMethod(method, args),
  );

  static final _mpvBackend = MpvFramePreview();

  /// Longer allowances than the platform decoder's: opening HLS means the
  /// master playlist, a variant playlist and a segment before the first frame.
  static final _mpv = FramePreviewSession(
    supported: _hasMpv,
    invoke: _mpvBackend.invoke,
    openTimeout: const Duration(seconds: 10),
    frameTimeout: const Duration(seconds: 4),
    // Full-resolution JPEGs, so a larger budget for the same two dozen.
    maxCacheBytes: 8 * 1024 * 1024,
  );

  static const int bucketMs = FramePreviewSession.bucketMs;

  /// Which backend a stream goes to first.
  static bool _mpvFirst(bool hls) => !_hasNative || (Platform.isAndroid && hls);

  static Future<Uint8List?> previewFrame(
    String url,
    Map<String, String> headers,
    int positionMs, {
    bool hls = false,
  }) async {
    if (_mpvFirst(hls)) {
      return _hasMpv ? _mpv.previewFrame(url, headers, positionMs) : null;
    }
    final frame = await _native.previewFrame(url, headers, positionMs);
    if (frame != null || !_hasMpv) return frame;
    // The platform decoder could not read it — an unusual container, a
    // server it disagrees with. libmpv is the second opinion.
    return _mpv.previewFrame(url, headers, positionMs);
  }

  static Future<void> endScrub() async {
    await Future.wait([_native.endScrub(), _mpv.endScrub()]);
  }

  static Future<void> close() async {
    await Future.wait([_native.close(), _mpv.close()]);
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
