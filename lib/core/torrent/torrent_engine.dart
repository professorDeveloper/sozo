import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:soplay/core/torrent/torrent_status.dart';
import 'package:soplay/core/torrent/torrent_stream_url.dart';

/// Talks to the TorrServer instance running inside the app.
///
/// ## The shape of the thing
///
/// Native code does two things — load the Go runtime and bind a port. From
/// there this is an ordinary HTTP client against `http://127.0.0.1:<port>`:
///
/// ```
/// GET  /echo                                   is it alive
/// POST /torrents  {action: add,  link}         -> status (hash)
/// POST /torrents  {action: get,  hash}         -> status (file_stats, speeds)
/// POST /torrents  {action: list}               -> [status]
/// POST /torrents  {action: drop, hash}         close the stream
/// POST /torrents  {action: rem,  hash}         forget it entirely
/// GET  /stream/<name>?link=<hash>&index=<i>&play
/// ```
///
/// The last line is the whole point: a magnet becomes a plain, seekable HTTP
/// URL, so `PlayerController.networkUrl` opens a torrent with no idea that it
/// is one.
///
/// ## Waiting for metadata
///
/// `add` returns as soon as the torrent is registered, which for a magnet is
/// *before* the file list exists — it still has to be fetched from the swarm.
/// Reading `file_stats` right away gets null, and building a stream URL from
/// null is the failure users see as "torrent won't play". [awaitMetadata] is
/// the fix: poll until the files appear or the swarm proves unreachable.
class TorrentEngine {
  TorrentEngine({Dio? dio}) : _dio = dio ?? _buildDio();

  static const MethodChannel _channel = MethodChannel('soplay/torrent');

  final Dio _dio;

  int? _port;
  Future<int>? _starting;

  /// Only Android ships the native server: the artifact is an Android AAR with
  /// `libgojni.so`, and there is no iOS or desktop equivalent bundled. Callers
  /// check this before offering torrent playback at all — an unavailable
  /// feature should be absent, not a button that errors.
  bool get isSupported => !kIsWeb && Platform.isAndroid;

  bool get isRunning => _port != null;

  /// Localhost only, so timeouts are about the server being busy fetching
  /// metadata rather than about the network.
  static Dio _buildDio() => Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 15),
        responseType: ResponseType.json,
        validateStatus: (status) => status != null && status < 500,
      ));

  String get _base {
    final port = _port;
    if (port == null) {
      throw StateError('Torrent server is not running; call ensureStarted()');
    }
    return 'http://127.0.0.1:$port';
  }

  /// Starts the server if it is not already up and returns its port.
  ///
  /// Concurrent callers share one start: the player and the file picker both
  /// want the engine the moment a torrent is tapped, and starting twice would
  /// bind a second port and orphan the first.
  Future<int> ensureStarted({List<String> trackers = const []}) {
    final port = _port;
    if (port != null) return Future.value(port);
    return _starting ??= _start(trackers).whenComplete(() => _starting = null);
  }

  Future<int> _start(List<String> trackers) async {
    if (!isSupported) {
      throw UnsupportedError('Torrent streaming is only available on Android');
    }
    final port = await _channel.invokeMethod<int>('start', {
      // Newline-separated, which is what TorrServer's addTrackers expects.
      'trackers': trackers.join('\n'),
    });
    if (port == null || port <= 0) {
      throw StateError('Torrent server failed to start');
    }
    _port = port;
    developer.log('server up on 127.0.0.1:$port', name: 'torrent');

    final cacheDir = await _channel.invokeMethod<String>('cacheDir');
    if (cacheDir != null && cacheDir.isNotEmpty) {
      await applyRecommendedSettings(cacheDir);
    }
    return port;
  }

  /// Points this instance at an already-running server.
  ///
  /// The server is process-wide, but a [TorrentEngine] is not — the player and
  /// the search page each hold their own. Rather than make the engine a
  /// singleton (and inherit a singleton's lifetime problems in tests), an
  /// instance that already knows the port from a stream URL can simply adopt
  /// it. See [TorrentStreamUrl].
  void attach(int port) {
    if (port > 0) _port = port;
  }

  /// Whether the server is up **anywhere in the process**, not just known to
  /// this instance.
  ///
  /// [isRunning] only reports what this object has started. The server itself
  /// outlives any single [TorrentEngine] — the search page, the player and the
  /// stats overlay each hold their own — so anything destructive (clearing the
  /// cache) has to ask the native side, which owns the real answer.
  Future<bool> isServerRunningInProcess() async {
    if (!isSupported) return false;
    if (_port != null) return true;
    try {
      final port = await _channel.invokeMethod<int>('port');
      if (port != null && port > 0) {
        _port = port;
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Deletes everything the server cached. Safe to call before it starts, and
  /// meant to run once at app launch — see the note in `TorrentServerBridge`.
  Future<void> clearCache() async {
    if (!isSupported) return;
    // Refuse while the server is live: its cache directory is open files, and
    // deleting them under a running torrent breaks playback that is working.
    if (await isServerRunningInProcess()) {
      developer.log('cache cleanup skipped — server is running', name: 'torrent');
      return;
    }
    try {
      await _channel.invokeMethod<bool>('clearCache');
    } on PlatformException catch (e) {
      developer.log('cache cleanup failed: ${e.message}', name: 'torrent');
    }
  }

  /// Registers [link] — a magnet URI or an HTTP `.torrent` URL — and returns
  /// the server's first view of it, usually without any file list yet.
  Future<TorrentStatus> add(
    String link, {
    String? title,
    String? poster,
  }) async {
    final status = await _post({
      'action': 'add',
      'link': link,
      'title': ?title,
      'poster': ?poster,
      // Not persisted across launches: the cache is wiped at startup anyway,
      // so a database entry would only ever point at data that is gone.
      'save_to_db': false,
    });
    if (status == null) {
      throw StateError('Torrent server rejected the link');
    }
    return status;
  }

  Future<TorrentStatus> get(String hash) async {
    final status = await _post({'action': 'get', 'hash': hash});
    if (status == null) {
      throw StateError('Torrent $hash is not known to the server');
    }
    return status;
  }

  /// Polls until the torrent's file list arrives.
  ///
  /// [timeout] is generous on purpose. Metadata for a healthy magnet lands in a
  /// second or two, but a torrent with two seeders on bad lines can take much
  /// longer, and giving up early looks identical to the torrent being dead —
  /// while actually being our impatience.
  Future<TorrentStatus> awaitMetadata(
    String hash, {
    Duration timeout = const Duration(seconds: 45),
    Duration interval = const Duration(milliseconds: 700),
    void Function(TorrentStatus status)? onProgress,
  }) async {
    final deadline = DateTime.now().add(timeout);
    TorrentStatus? last;

    while (DateTime.now().isBefore(deadline)) {
      try {
        final status = await get(hash);
        last = status;
        onProgress?.call(status);
        if (status.hasMetadata) return status;
        if (status.state == TorrentState.closed) {
          throw StateError('Torrent was closed before metadata arrived');
        }
      } on StateError {
        rethrow;
      } catch (_) {
        // A single failed poll is not a failed torrent.
      }
      await Future<void>.delayed(interval);
    }

    throw TimeoutException(
      'No metadata after ${timeout.inSeconds}s '
      '(${last?.label ?? 'no response'}) — the swarm may have no seeders',
    );
  }

  /// A snapshot every [interval] until the subscription is cancelled.
  ///
  /// Drives the player's live speed/peers readout. Errors are swallowed rather
  /// than closing the stream: one dropped poll during a stall should not tear
  /// down the overlay for the rest of the episode.
  Stream<TorrentStatus> watch(
    String hash, {
    Duration interval = const Duration(seconds: 1),
  }) async* {
    while (true) {
      try {
        yield await get(hash);
      } catch (_) {
        // Keep polling.
      }
      await Future<void>.delayed(interval);
    }
  }

  /// Settings pushed to the server right after it starts.
  ///
  /// The defaults it ships with are tuned for a desktop box on a wired line and
  /// are actively bad on a phone. Field names come from the server's own
  /// `BTSets` dump, so they are exactly what it understands.
  ///
  /// What each change is for:
  ///
  ///   * **`UseDisk` + `TorrentsSavePath`** — the default keeps the whole cache
  ///     in RAM. A 64 MB balloon inside an app that is also decoding 1080p
  ///     video is how a mid-range device gets its player killed mid-episode,
  ///     and the app already owns a cache directory to spill into.
  ///   * **`CacheSize`** — safe to raise once it is on disk, and a bigger cache
  ///     is what absorbs a swarm that delivers in bursts.
  ///   * **`PreloadCache`** — percent of the cache to fill before serving
  ///     bytes. The default 50 % of 64 MB is ~32 MB of waiting before the first
  ///     frame; 12 % of 128 MB is ~15 MB, which is still ~15 seconds of video
  ///     ahead but starts noticeably sooner.
  ///   * **`ConnectionsLimit`** — 25 peers is the single biggest brake on how
  ///     fast a stream starts. Anime swarms routinely have hundreds.
  ///   * **`RemoveCacheOnDrop`** — reclaim the disk the moment the user leaves
  ///     the player, rather than only at the next launch.
  static const Map<String, Object> recommendedSettings = {
    'UseDisk': true,
    'CacheSize': 128 * 1024 * 1024,
    'PreloadCache': 12,
    'ReaderReadAHead': 95,
    'ConnectionsLimit': 100,
    'RemoveCacheOnDrop': true,
    'RetrackersMode': 1,
  };

  /// Applies [recommendedSettings], merged onto whatever the server currently
  /// has so an unknown field is never dropped.
  ///
  /// Best-effort: a server that rejects the call still streams, just with the
  /// stock settings, so a failure here must not stop playback.
  Future<void> applyRecommendedSettings(String savePath) async {
    try {
      final current = await _dio.post<dynamic>(
        '$_base/settings',
        data: {'action': 'get'},
      );
      final sets = <String, dynamic>{
        if (current.data is Map) ...Map<String, dynamic>.from(current.data as Map),
        ...recommendedSettings,
        'TorrentsSavePath': savePath,
      };
      await _dio.post<dynamic>(
        '$_base/settings',
        data: {'action': 'set', 'sets': sets},
      );
      developer.log('settings applied', name: 'torrent');
    } catch (e) {
      developer.log('settings not applied: $e', name: 'torrent');
    }
  }

  /// Tells the server to start filling the read-ahead buffer for [file].
  ///
  /// Deliberately not awaited. The server holds this request open until the
  /// buffer is full, which is the thing being waited *for* — progress is read
  /// from [awaitPreload] instead.
  ///
  /// This is the fix for the worst symptom of naive torrent playback: hand the
  /// stream URL straight to the player and its `initialize()` blocks until the
  /// buffer fills anyway, except now it is behind a black screen with no
  /// progress, no peer count and no cancel. Same wait, no information.
  void startPreload(String hash, TorrentFileEntry file) {
    stopPreload(hash);
    final token = CancelToken();
    _preloadTokens[hash] = token;

    unawaited(
      _dio
          .getUri<dynamic>(
            _streamUri(hash, file, mode: 'preload'),
            cancelToken: token,
            options: Options(
              responseType: ResponseType.stream,
              // The server holds this open for as long as the buffer takes to
              // fill, which on a thin swarm is minutes.
              receiveTimeout: const Duration(minutes: 5),
            ),
          )
          .catchError((Object _) => Response<dynamic>(
                requestOptions: RequestOptions(path: ''),
              )),
    );
  }

  /// Cancels a running preload request.
  ///
  /// This is not tidiness. The preload holds a reader open on the torrent, and
  /// the play request opens another — two readers on one sequential stream is
  /// the same thrashing that makes scrub previews unusable on a torrent. The
  /// preload must be let go the moment its job is done.
  void stopPreload(String hash) {
    final token = _preloadTokens.remove(hash);
    if (token != null && !token.isCancelled) token.cancel('preload finished');
  }

  final Map<String, CancelToken> _preloadTokens = {};

  /// Polls until the read-ahead buffer is full enough to start playing.
  ///
  /// Returns as soon as the server reports the preload complete. On timeout it
  /// returns the last status rather than throwing: a partly filled buffer still
  /// plays, it just may stall, and refusing to start at all would be worse.
  Future<TorrentStatus> awaitPreload(
    String hash, {
    Duration timeout = const Duration(seconds: 60),
    Duration interval = const Duration(milliseconds: 500),
    void Function(TorrentStatus status)? onProgress,
  }) async {
    final deadline = DateTime.now().add(timeout);
    TorrentStatus? last;

    try {
      while (DateTime.now().isBefore(deadline)) {
        try {
          final status = await get(hash);
          last = status;
          onProgress?.call(status);
          final progress = status.preloadProgress;
          if (progress != null && progress >= 1) return status;
          // Some builds stop reporting a preload target once they are serving.
          if (progress == null && status.state == TorrentState.working) {
            return status;
          }
          if (status.state == TorrentState.closed) return status;
        } catch (_) {
          // A dropped poll is not a dropped torrent.
        }
        await Future<void>.delayed(interval);
      }
      return last ?? await get(hash);
    } finally {
      // Every exit path — filled, timed out, or the torrent closed under us —
      // must release the preload reader before the player opens its own.
      stopPreload(hash);
    }
  }

  /// The playable URL for one file inside a torrent.
  ///
  /// `index` is the server's own 1-based file id, and `play` is what makes it
  /// serve bytes rather than describe them. The file name is in the path only
  /// so players and download managers see a sensible name — the server routes
  /// on `link` and `index`.
  Uri streamUri(String hash, TorrentFileEntry file) =>
      _streamUri(hash, file, mode: 'play');

  /// `mode` is `play` to serve bytes or `preload` to only fill the buffer.
  Uri _streamUri(String hash, TorrentFileEntry file, {required String mode}) =>
      Uri.parse(
        '$_base/stream/${Uri.encodeComponent(file.name)}'
        '?link=$hash&index=${file.id}&$mode',
      );

  /// Closes the stream for one torrent but keeps it registered.
  Future<void> drop(String hash) async {
    stopPreload(hash);
    try {
      await _post({'action': 'drop', 'hash': hash});
    } catch (_) {}
  }

  /// Forgets a torrent entirely.
  Future<void> remove(String hash) async {
    try {
      await _post({'action': 'rem', 'hash': hash});
    } catch (_) {}
  }

  /// Drops and removes every torrent the server holds.
  ///
  /// Both steps are needed and in this order: `drop` closes the stream and
  /// stops the swarm connections, `rem` deletes the registration. Doing only
  /// the second leaves peers connected, which is exactly the leak this
  /// feature must not have — the app should not keep uploading after the user
  /// has closed the player.
  Future<void> clearAll() async {
    if (_port == null) return;
    try {
      final response = await _dio.post<dynamic>(
        '$_base/torrents',
        data: {'action': 'list'},
      );
      final list = response.data;
      if (list is! List) return;

      for (final item in list.whereType<Map>()) {
        final hash = item['hash']?.toString();
        if (hash == null || hash.isEmpty) continue;
        await drop(hash);
        await remove(hash);
      }
    } catch (e) {
      developer.log('clearAll failed: $e', name: 'torrent');
    }
  }

  /// Whether the server answers. Used to detect a server that died under us.
  Future<bool> ping() async {
    if (_port == null) return false;
    try {
      final response = await _dio.get<dynamic>('$_base/echo');
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<TorrentStatus?> _post(Map<String, dynamic> body) async {
    final response = await _dio.post<dynamic>('$_base/torrents', data: body);
    final data = response.data;
    if (data is! Map) return null;
    return TorrentStatus.fromJson(Map<String, dynamic>.from(data));
  }

  void dispose() => _dio.close(force: true);
}
