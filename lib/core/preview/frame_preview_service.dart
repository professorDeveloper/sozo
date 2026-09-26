import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
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
    frameTimeout: const Duration(seconds: 6),
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

  static FramePreviewSession _sessionFor(bool hls) =>
      hls && Platform.isAndroid ? _hls : _native;

  /// The cached frame nearest [positionMs] for [url], if any is close enough —
  /// shown at once while the exact one is decoded.
  static Uint8List? nearest(
    String url,
    int positionMs, {
    bool hls = false,
    int? withinMs,
  }) {
    final s = _sessionFor(hls);
    return s.serves(url) ? s.nearest(positionMs, withinMs: withinMs) : null;
  }

  /// This source keeps failing to decode and nothing is held for it.
  static bool failing(String url, {bool hls = false}) {
    final s = _sessionFor(hls);
    return s.serves(url) && s.failing;
  }

  /// Ticks whenever any frame lands in a cache, so a card still waiting on
  /// its exact frame can show one that has just become near enough.
  static final ValueNotifier<int> frames = ValueNotifier<int>(0);

  /// Spacing of the background grid for [durationMs], for [nearest]'s reach.
  static int gridSpacingMs(int durationMs, {required bool metered}) {
    final count = gridCount(durationMs, metered: metered);
    return (durationMs ~/ count).clamp(bucketMs, 1 << 30);
  }

  /// How many frames the grid holds: one every ~20 seconds on Wi-Fi, so an
  /// episode and a two-hour film are both dense enough that a scrub lands
  /// near a real frame; fewer on mobile data, where each costs a segment.
  @visibleForTesting
  static int gridCount(int durationMs, {required bool metered}) {
    if (metered) return 16;
    return (durationMs ~/ 20000).clamp(40, FramePreviewSession.maxGridFrames);
  }

  /// Frames near [positionMs], in [direction] (+1 ahead, -1 behind), fetched
  /// while the finger is still down — the next place a drag is going — only
  /// when the decoder is otherwise idle.
  static void prefetch(
    String url,
    int positionMs,
    int direction, {
    bool hls = false,
  }) {
    final s = _sessionFor(hls);
    if (!s.serves(url) || s.busy) return;
    final step = direction >= 0 ? bucketMs * 2 : -bucketMs * 2;
    unawaited(s.frame(positionMs + step));
  }

  /// Coarse to fine: every eighth point first, then the points around
  /// [near] (the playhead), then the fourths, halves and the rest — so a
  /// scrub early on finds something near wherever it lands, and nearest of
  /// all where it most often lands.
  @visibleForTesting
  static List<int> gridOrder(int count, {int? near}) {
    final out = <int>[];
    final seen = <int>{};
    for (var i = 0; i < count; i += 8) {
      if (seen.add(i)) out.add(i);
    }
    if (near != null) {
      for (var d = 0; d <= 4; d++) {
        for (final i in [near + d, near - d]) {
          if (i >= 0 && i < count && seen.add(i)) out.add(i);
        }
      }
    }
    for (final step in const [4, 2, 1]) {
      for (var i = 0; i < count; i += step) {
        if (seen.add(i)) out.add(i);
      }
    }
    return out;
  }

  static _Warmer? _warmer;
  static bool _scrubbing = false;

  /// A drag on the seek bar started or ended. The warmer yields to it: the
  /// frame the viewer is pointing at always goes first.
  static set scrubbing(bool value) => _scrubbing = value;

  /// Starts filling the grid for [url] — evenly across [durationMs], coarse
  /// to fine, a frame at a time and paced so playback keeps the bandwidth —
  /// so a scrub finds a frame already there instead of waiting for one.
  /// Fewer frames on mobile data: each one costs a segment download.
  ///
  /// [cacheKey] names the episode rather than the stream — stream addresses
  /// are signed and change — so the grid is kept on disk and an episode
  /// opened again has every frame from the first touch. [positionMs] is where
  /// playback is: the frames around it come right after the coarse pass,
  /// since most scrubs are a minute or two either way.
  static void warm({
    required String url,
    required Map<String, String> headers,
    required int durationMs,
    bool hls = false,
    bool metered = false,
    String? cacheKey,
    int positionMs = 0,
  }) {
    if (!isSupported || durationMs < 60000) return;
    _warmer?.stop();
    // How far "near" reaches follows how sparse the grid is. Fixed at 30 s,
    // a far jump on the seek bar found nothing on a 16-frame metered grid.
    _sessionFor(hls).durationMs = durationMs;
    _warmer = _Warmer(
      session: _sessionFor(hls),
      url: url,
      headers: headers,
      durationMs: durationMs,
      count: gridCount(durationMs, metered: metered),
      pace: Duration(milliseconds: metered ? 900 : 250),
      cacheKey: cacheKey,
      positionMs: positionMs,
    )..start();
  }

  static Future<void> endScrub() async {
    await Future.wait([_native.endScrub(), _hls.endScrub()]);
  }

  static Future<void> close() async {
    _warmer?.stop();
    _warmer = null;
    // A drag that never reported its end (a second finger, a closed page)
    // would otherwise keep the next title's warmer waiting for good.
    _scrubbing = false;
    _proxiedCache.clear();
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
  ///
  /// Renewed after 20 minutes: the proxy drops a session nobody has touched
  /// for 30, and a preview session is touched only while frames are fetched.
  /// Kept past that, a scrub late in a film opened a dead address and every
  /// exact frame was missing.
  static final Map<String, (Future<String>, DateTime)> _proxiedCache = {};
  static const _proxiedTtl = Duration(minutes: 20);

  static Future<String> _proxied(String url, Map<String, String> headers) {
    final keys = headers.keys.toList()..sort();
    final key = '$url\u0000${keys.map((k) => '$k=${headers[k]}').join('&')}';
    if (_proxiedCache.length > 8) _proxiedCache.clear();
    final now = DateTime.now();
    final held = _proxiedCache[key];
    if (held != null && now.difference(held.$2) < _proxiedTtl) return held.$1;
    final fresh = _proxy(url, headers);
    _proxiedCache[key] = (fresh, now);
    return fresh;
  }

  /// The lightest variant, behind the local proxy so its headers go along.
  static Future<String> _proxy(String url, Map<String, String> headers) async {
    final uri = Uri.tryParse(url);
    final local = uri != null && uri.host == '127.0.0.1';
    // The lightest rendition whichever way the stream is reached: a stream
    // already on the local proxy used to open its whole master, and the
    // decoder picked a 720p segment for a 360px thumbnail. Its variants are
    // proxied paths of the same session, so they keep its headers.
    final target = await _lightestVariant(url, headers) ?? url;
    if (local || headers.isEmpty) return target;
    try {
      return await getIt<LocalHlsProxy>().register(
        upstreamUrl: target,
        headers: headers,
        // The player's own headers, Referer included: the CDN checks it.
        keepOriginHeaders: true,
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
      // Not an audio-only rendition: a decoder handed one has no frame to
      // give. Known by codecs naming no video, or by having no resolution
      // where the others do.
      final codecs =
          RegExp(r'CODECS="([^"]*)"').firstMatch(line)?.group(1) ?? '';
      if (codecs.isNotEmpty &&
          !RegExp(r'avc|hvc|hev|av01|vp0?9|dvh|mp4v').hasMatch(codecs)) {
        continue;
      }
      if (!line.contains('RESOLUTION=') &&
          playlist.contains('RESOLUTION=')) {
        continue;
      }
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

  /// Frames fetched ahead of any scrub, evenly across the video. Kept apart
  /// from [_cache] so a burst of scrubbing cannot evict the grid that makes
  /// the next scrub instant.
  final _grid = <int, Uint8List>{};
  static const int maxGridFrames = 120;

  /// Where this source's grid is kept on disk; null keeps it in memory only.
  String? _diskKey;

  /// Loads the grid kept for [key] and keeps new grid frames there.
  Future<void> attachDisk(String key) async {
    _diskKey = key;
    final frames = await PreviewDiskCache.load(key);
    if (_diskKey != key) return;
    for (final e in frames.entries) {
      if (_grid.length >= maxGridFrames) break;
      _grid.putIfAbsent(e.key, () => e.value);
    }
  }

  /// Held in the grid already, so the warmer can skip it.
  bool hasGridFrame(int positionMs) => _grid.containsKey(_bucketOf(positionMs));

  /// The length of the video the grid is filling, from
  /// [FramePreviewService.warm]; how far [nearest] reaches follows from it.
  int durationMs = 0;

  /// How far [nearest] looks when not told: the gap between the frames held
  /// so far, so a sparse grid early on still answers a far jump — a fixed
  /// 30 s found nothing between the first pass's points minutes apart. At
  /// most three minutes, past which a frame is more misleading than none.
  int get reachMs {
    final held = _grid.length + _cache.length;
    if (durationMs <= 0 || held == 0) return 30000;
    return (durationMs ~/ held * 3 ~/ 4).clamp(30000, 180000);
  }

  /// Nulls in a row from the decoder, reset by any frame. With nothing held
  /// either, the source cannot be decoded here and the card should say so by
  /// showing no picture rather than a skeleton that never fills.
  int _consecutiveNulls = 0;
  bool get failing =>
      _consecutiveNulls >= 3 && _cache.isEmpty && _grid.isEmpty;

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
    _grid.clear();
    _cacheBytes = 0;
    _misses.clear();
    _consecutiveNulls = 0;
    _retryOpenAfter = null;
    _identity = identity;
    _url = url;
    _headers = Map.of(headers);
    _diskKey = null;
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

  /// Whether [url] is the source this session is configured for.
  bool serves(String url) => _url == url;

  /// A request of the viewer's is out or waiting.
  bool get busy => _running != null || _queued != null;

  int _bucketOf(int positionMs) =>
      (positionMs.clamp(0, 1 << 53) ~/ bucketMs) * bucketMs;

  /// The cached frame closest to [positionMs], within [withinMs]; null when
  /// nothing is near enough. What the card shows while the exact frame is
  /// still being decoded.
  Uint8List? nearest(int positionMs, {int? withinMs}) {
    Uint8List? best;
    var bestGap = (withinMs ?? reachMs) + 1;
    void consider(Map<int, Uint8List> from) {
      for (final e in from.entries) {
        final gap = (e.key - positionMs).abs();
        if (gap < bestGap) {
          bestGap = gap;
          best = e.value;
        }
      }
    }

    consider(_grid);
    consider(_cache);
    return best;
  }

  /// One frame for the background grid. Skips a position already held, and
  /// declines — returning false, to be retried — while the viewer has a
  /// request of their own out.
  Future<bool> gridFrame(int positionMs) async {
    if (!supported || _url == null) return true;
    if (busy) return false;
    final bucket = _bucketOf(positionMs);
    if (_grid.containsKey(bucket)) return true;
    final bytes = _cache.remove(bucket) ?? await frame(bucket);
    if (bytes != null && _grid.length < maxGridFrames) {
      _cache.remove(bucket);
      _grid[bucket] = bytes;
      FramePreviewService.frames.value++;
      final key = _diskKey;
      if (key != null) unawaited(PreviewDiskCache.save(key, bucket, bytes));
    }
    // Tried, frame or not; the warmer comes back for the holes at the end.
    return true;
  }

  bool _sameHeaders(Map<String, String> first, Map<String, String> second) =>
      first.length == second.length &&
      first.entries.every((entry) => second[entry.key] == entry.value);

  Future<Uint8List?> frame(int positionMs) {
    if (!supported || _url == null) return Future.value(null);
    _idle?.cancel();
    final bucket = _bucketOf(positionMs);
    final gridded = _grid[bucket];
    if (gridded != null) {
      _scheduleIdle();
      return Future.value(gridded);
    }
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
      _consecutiveNulls = bytes == null ? _consecutiveNulls + 1 : 0;
      if (bytes == null) {
        _misses[request.bucket] = DateTime.now().add(
          const Duration(seconds: 2),
        );
        if (_misses.length > maxFrames) _misses.remove(_misses.keys.first);
      }
      if (bytes != null && bytes.length <= maxCacheBytes) {
        _cache[request.bucket] = bytes;
        _cacheBytes += bytes.length;
        FramePreviewService.frames.value++;
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
    _diskKey = null;
    _cache.clear();
    _grid.clear();
    _cacheBytes = 0;
    _misses.clear();
    _consecutiveNulls = 0;
    durationMs = 0;
    _retryOpenAfter = null;
    await endScrub();
  }
}

/// Fills a session's grid in the background. See [FramePreviewService.warm].
class _Warmer {
  _Warmer({
    required this.session,
    required this.url,
    required this.headers,
    required this.durationMs,
    required this.count,
    required this.pace,
    this.cacheKey,
    this.positionMs = 0,
  });

  final FramePreviewSession session;
  final String url;
  final Map<String, String> headers;
  final int durationMs;
  final int count;
  final Duration pace;
  final String? cacheKey;
  final int positionMs;
  bool _stopped = false;

  void stop() => _stopped = true;

  void start() => unawaited(_loop());

  Future<void> _loop() async {
    await session.open(url, headers);
    final key = cacheKey;
    if (key != null) await session.attachDisk(key);
    // The first and last few percent are logos and credits.
    final start = durationMs * 0.02;
    final span = durationMs * 0.96;
    final near = ((positionMs - start) / span * (count - 1)).round();
    final order = FramePreviewService.gridOrder(
      count,
      near: near.clamp(0, count - 1),
    );
    // A second pass for the points the first left empty: a frame cancelled
    // by a drag or refused once is usually there on the next try, and the
    // first pass counting it as done left a hole in the seek bar for good.
    for (var pass = 0; pass < 2; pass++) {
      for (final i in order) {
        final at = (start + span * i / (count - 1)).round();
        if (session.hasGridFrame(at)) continue;
        while (true) {
          if (_stopped || !session.serves(url)) return;
          if (!FramePreviewService._scrubbing && await session.gridFrame(at)) {
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
        await Future<void>.delayed(pace);
      }
    }
  }
}

class _FrameRequest {
  _FrameRequest(this.generation, this.bucket);
  final int generation;
  final int bucket;
  final result = Completer<Uint8List?>();
}

/// The seek-bar grid on disk, one folder per episode.
///
/// In memory it went with the player: opening the same episode again — the
/// usual way back to something — downloaded every frame a second time and
/// the first scrubs showed nothing. Bounded to the most recent
/// [maxEpisodes] episodes; the cache directory is the platform's to clear.
class PreviewDiskCache {
  PreviewDiskCache._();

  static const int maxEpisodes = 24;

  @visibleForTesting
  static Directory? debugRoot;

  static Future<Directory> _root() async {
    final base = debugRoot ?? await getTemporaryDirectory();
    return Directory('${base.path}/preview_grid');
  }

  static String _folder(String key) =>
      sha1.convert(utf8.encode(key)).toString().substring(0, 20);

  static Future<Map<int, Uint8List>> load(String key) async {
    final out = <int, Uint8List>{};
    try {
      final dir = Directory('${(await _root()).path}/${_folder(key)}');
      if (!await dir.exists()) return out;
      // Touched, so pruning keeps what is being watched.
      await _touch(dir);
      await for (final f in dir.list()) {
        if (f is! File || !f.path.endsWith('.jpg')) continue;
        final name = f.uri.pathSegments.last;
        final bucket = int.tryParse(name.substring(0, name.length - 4));
        if (bucket == null) continue;
        out[bucket] = await f.readAsBytes();
      }
    } catch (_) {}
    return out;
  }

  static final Set<String> _pruned = {};

  static Future<void> save(String key, int bucket, Uint8List bytes) async {
    try {
      final root = await _root();
      final dir = Directory('${root.path}/${_folder(key)}');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
        await _touch(dir);
        if (_pruned.add(key)) unawaited(_prune(root));
      }
      await File('${dir.path}/$bucket.jpg').writeAsBytes(bytes, flush: false);
    } catch (_) {}
  }

  static Future<void> _touch(Directory dir) async {
    try {
      await File('${dir.path}/.at').writeAsString('');
    } catch (_) {}
  }

  static Future<DateTime> _usedAt(Directory dir) async {
    final marker = File('${dir.path}/.at');
    return (await marker.exists())
        ? (await marker.stat()).modified
        : (await dir.stat()).modified;
  }

  static Future<void> _prune(Directory root) async {
    try {
      final dirs = <Directory>[
        await for (final e in root.list())
          if (e is Directory) e,
      ];
      if (dirs.length <= maxEpisodes) return;
      final dated = <(Directory, DateTime)>[
        for (final d in dirs) (d, await _usedAt(d)),
      ]..sort((a, b) => a.$2.compareTo(b.$2));
      for (final (d, _) in dated.take(dirs.length - maxEpisodes)) {
        await d.delete(recursive: true);
      }
    } catch (_) {}
  }
}
