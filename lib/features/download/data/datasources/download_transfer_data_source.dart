import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:soplay/features/download/domain/download_layout.dart';
import 'package:soplay/features/download/domain/entities/download_failure.dart';
import 'package:soplay/features/download/domain/entities/download_kind.dart';

/// A step forward, reported to whoever is driving the transfer.
class TransferProgress {
  const TransferProgress({
    required this.completedUnits,
    required this.totalUnits,
    required this.sizeBytes,
  });

  final int completedUnits;
  final int totalUnits;
  final int sizeBytes;
}

/// What a transfer produced.
class TransferResult {
  const TransferResult.success({
    required this.artefactPath,
    required this.completedUnits,
    required this.totalUnits,
    required this.sizeBytes,
  })  : failure = null,
        detail = '';

  const TransferResult.failed(this.failure, this.detail)
      : artefactPath = '',
        completedUnits = 0,
        totalUnits = 0,
        sizeBytes = 0;

  /// Absolute path of what was written. Empty on failure.
  final String artefactPath;
  final int completedUnits;
  final int totalUnits;
  final int sizeBytes;
  final DownloadFailureKind? failure;
  final String detail;

  bool get ok => failure == null;
}

/// Thrown internally when a response is not the media it claimed to be.
class _NotMediaException implements Exception {
  const _NotMediaException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The in-process downloader: iOS, macOS, Windows, Linux.
///
/// Android does not use this — its transfers run in a foreground service so
/// they survive the app being backgrounded — but the two agree on the layout
/// on disk, byte for byte, so a download made by either is readable by the
/// other. That matters more than it sounds: the verifier is shared, and a
/// verifier that only understood one engine's output would condemn the other's
/// downloads as broken.
///
/// ## What is different from the code this replaces
///
/// * Nothing is written to its final name until it is finished. A killed
///   process used to leave a partial `video.mp4` that looked complete.
/// * Every multi-part download writes a manifest, so "is this whole" can be
///   answered later rather than assumed.
/// * A response that is not media is a failure with a name, instead of an
///   HTML error page saved under a video's extension.
class DownloadTransferDataSource {
  DownloadTransferDataSource({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 20),
                receiveTimeout: const Duration(minutes: 5),
                followRedirects: true,
                maxRedirects: 5,
                validateStatus: (s) => s != null && s < 400,
              ),
            );

  final Dio _dio;

  /// One failed segment out of a thousand should not cost the episode.
  static const int _segmentAttempts = 3;

  /// Content types that mean "this is not the file you asked for".
  static const List<String> _nonMediaTypes = [
    'text/html',
    'application/xhtml',
    'text/plain',
  ];

  Future<TransferResult> run({
    required String id,
    required String dirPath,
    required DownloadKind kind,
    required String sourceUrl,
    required Map<String, String> headers,
    required List<String> pageUrls,
    required CancelToken cancel,
    required void Function(TransferProgress) onProgress,
  }) async {
    try {
      await Directory(dirPath).create(recursive: true);
      return switch (kind) {
        DownloadKind.video => await _direct(
            dirPath: dirPath,
            url: sourceUrl,
            headers: headers,
            cancel: cancel,
            onProgress: onProgress,
          ),
        DownloadKind.hls => await _hls(
            dirPath: dirPath,
            url: sourceUrl,
            headers: headers,
            cancel: cancel,
            onProgress: onProgress,
          ),
        DownloadKind.manga => await _pages(
            dirPath: dirPath,
            pageUrls: pageUrls,
            headers: headers,
            cancel: cancel,
            onProgress: onProgress,
          ),
      };
    } on _NotMediaException catch (e) {
      return TransferResult.failed(DownloadFailureKind.notMedia, e.message);
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        return const TransferResult.failed(DownloadFailureKind.unknown, 'cancelled');
      }
      final status = e.response?.statusCode;
      final detail = status == null ? (e.message ?? '$e') : 'HTTP $status';
      return TransferResult.failed(
        DownloadFailureKind.classify(detail),
        detail,
      );
    } on FileSystemException catch (e) {
      // `ENOSPC` arrives here rather than from the network layer, and it is the
      // one failure where retrying without doing anything else is pointless.
      final detail = '${e.message} ${e.osError?.message ?? ''}'.trim();
      return TransferResult.failed(
        DownloadFailureKind.classify(detail),
        detail,
      );
    } catch (e) {
      return TransferResult.failed(DownloadFailureKind.classify('$e'), '$e');
    }
  }

  // --- one file ------------------------------------------------------------

  Future<TransferResult> _direct({
    required String dirPath,
    required String url,
    required Map<String, String> headers,
    required CancelToken cancel,
    required void Function(TransferProgress) onProgress,
  }) async {
    final extension = DownloadLayout.videoExtensionFor(url);
    final target = File('$dirPath/${DownloadLayout.videoStemName}$extension');
    final part = File(DownloadLayout.partOf(target.path));

    // Resume from whatever a previous attempt left in the `.part`.
    final existing = await part.exists() ? await part.length() : 0;

    final response = await _dio.get<ResponseBody>(
      url,
      cancelToken: cancel,
      options: Options(
        headers: {
          ...headers,
          if (existing > 0) 'Range': 'bytes=$existing-',
        },
        responseType: ResponseType.stream,
      ),
    );

    _rejectNonMedia(response.headers.value('content-type'));

    // 206 means the server honoured the range; anything else means starting
    // over, and appending to the old bytes would corrupt the file silently.
    final append = existing > 0 && response.statusCode == 206;
    if (!append && await part.exists()) await part.delete();

    final declared = _contentLength(response.headers);
    final total = declared > 0 ? (append ? existing + declared : declared) : 0;
    var written = append ? existing : 0;

    final sink = part.openWrite(
      mode: append ? FileMode.append : FileMode.write,
    );
    try {
      await for (final chunk in response.data!.stream) {
        if (cancel.isCancelled) {
          await sink.flush();
          return const TransferResult.failed(
            DownloadFailureKind.unknown,
            'cancelled',
          );
        }
        sink.add(chunk);
        written += chunk.length;
        onProgress(TransferProgress(
          completedUnits: written,
          totalUnits: total,
          sizeBytes: written,
        ));
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    if (written <= 0) {
      return const TransferResult.failed(
        DownloadFailureKind.incomplete,
        'nothing was written',
      );
    }
    // The server stated a length and we have less than it: the connection
    // dropped clean, which looks exactly like success from here.
    if (total > 0 && written < total) {
      return TransferResult.failed(
        DownloadFailureKind.incomplete,
        'truncated at $written of $total bytes',
      );
    }

    if (await target.exists()) await target.delete();
    await part.rename(target.path);

    return TransferResult.success(
      artefactPath: target.path,
      completedUnits: written,
      totalUnits: written,
      sizeBytes: written,
    );
  }

  // --- playlist ------------------------------------------------------------

  Future<TransferResult> _hls({
    required String dirPath,
    required String url,
    required Map<String, String> headers,
    required CancelToken cancel,
    required void Function(TransferProgress) onProgress,
  }) async {
    var playlistUrl = url;
    var playlist = await _text(url, headers, cancel);

    if (playlist.contains('#EXT-X-STREAM-INF')) {
      final variant = _pickVariant(playlist, _baseOf(url));
      if (variant == null) {
        return const TransferResult.failed(
          DownloadFailureKind.notMedia,
          'no variant in the master playlist',
        );
      }
      playlistUrl = variant;
      playlist = await _text(variant, headers, cancel);
    }

    final segments = _segmentUrls(playlist, _baseOf(playlistUrl));
    if (segments.isEmpty) {
      return const TransferResult.failed(
        DownloadFailureKind.notMedia,
        'no segments in the playlist',
      );
    }

    var bytes = 0;
    for (var i = 0; i < segments.length; i++) {
      if (cancel.isCancelled) {
        return const TransferResult.failed(
          DownloadFailureKind.unknown,
          'cancelled',
        );
      }
      final file = File('$dirPath/${DownloadLayout.segmentName(i)}');
      // A segment already on disk is only trusted if it is non-empty. The old
      // code trusted any file that existed, so a segment truncated by a killed
      // process was never re-fetched and the episode played to that point and
      // stopped.
      if (!await file.exists() || await file.length() <= 0) {
        await _fetchToFile(
          url: segments[i],
          file: file,
          headers: headers,
          cancel: cancel,
          attempts: _segmentAttempts,
        );
      }
      bytes += await file.length();
      onProgress(TransferProgress(
        completedUnits: i + 1,
        totalUnits: segments.length,
        sizeBytes: bytes,
      ));
    }

    // The manifest first, then the playlist. The playlist is what the verifier
    // treats as "this download exists", so writing it last means a crash
    // between the two leaves an incomplete download that still reads as
    // incomplete.
    await _writeManifest(
      dirPath: dirPath,
      kind: DownloadKind.hls,
      parts: segments.length,
      bytes: bytes,
    );
    await File('$dirPath/${DownloadLayout.hlsIndexName}')
        .writeAsString(_localPlaylist(playlist));

    return TransferResult.success(
      artefactPath: '$dirPath/${DownloadLayout.hlsIndexName}',
      completedUnits: segments.length,
      totalUnits: segments.length,
      sizeBytes: bytes,
    );
  }

  // --- pages ---------------------------------------------------------------

  Future<TransferResult> _pages({
    required String dirPath,
    required List<String> pageUrls,
    required Map<String, String> headers,
    required CancelToken cancel,
    required void Function(TransferProgress) onProgress,
  }) async {
    if (pageUrls.isEmpty) {
      return const TransferResult.failed(
        DownloadFailureKind.notMedia,
        'the chapter has no pages',
      );
    }

    var bytes = 0;
    for (var i = 0; i < pageUrls.length; i++) {
      if (cancel.isCancelled) {
        return const TransferResult.failed(
          DownloadFailureKind.unknown,
          'cancelled',
        );
      }
      final name = DownloadLayout.pageName(
        i,
        DownloadLayout.imageExtensionFor(pageUrls[i]),
      );
      final file = File('$dirPath/$name');
      if (!await file.exists() || await file.length() <= 0) {
        await _fetchToFile(
          url: pageUrls[i],
          file: file,
          headers: headers,
          cancel: cancel,
          attempts: _segmentAttempts,
        );
      }
      bytes += await file.length();
      onProgress(TransferProgress(
        completedUnits: i + 1,
        totalUnits: pageUrls.length,
        sizeBytes: bytes,
      ));
    }

    await _writeManifest(
      dirPath: dirPath,
      kind: DownloadKind.manga,
      parts: pageUrls.length,
      bytes: bytes,
    );

    return TransferResult.success(
      artefactPath: dirPath,
      completedUnits: pageUrls.length,
      totalUnits: pageUrls.length,
      sizeBytes: bytes,
    );
  }

  // --- helpers -------------------------------------------------------------

  /// Fetches one part, retrying a transient failure with a short backoff.
  Future<void> _fetchToFile({
    required String url,
    required File file,
    required Map<String, String> headers,
    required CancelToken cancel,
    required int attempts,
  }) async {
    final part = File(DownloadLayout.partOf(file.path));
    Object? lastError;
    for (var attempt = 0; attempt < attempts; attempt++) {
      if (cancel.isCancelled) return;
      try {
        final response = await _dio.get<List<int>>(
          url,
          cancelToken: cancel,
          options: Options(
            headers: headers,
            responseType: ResponseType.bytes,
          ),
        );
        _rejectNonMedia(response.headers.value('content-type'));
        final bytes = response.data;
        if (bytes == null || bytes.isEmpty) {
          throw const _NotMediaException('empty part');
        }
        await part.writeAsBytes(bytes, flush: true);
        if (await file.exists()) await file.delete();
        await part.rename(file.path);
        return;
      } on _NotMediaException {
        rethrow;
      } catch (e) {
        lastError = e;
        // A cancel is not a failure to retry; it is the viewer asking to stop.
        if (e is DioException && CancelToken.isCancel(e)) return;
        // 400ms, 800ms, 1600ms. Long enough to ride out a blip, short enough
        // that a thousand-segment episode does not stall for minutes on a
        // host that is genuinely gone.
        await Future<void>.delayed(
          Duration(milliseconds: 400 * (1 << attempt)),
        );
      }
    }
    throw lastError ?? Exception('could not fetch $url');
  }

  Future<String> _text(
    String url,
    Map<String, String> headers,
    CancelToken cancel,
  ) async {
    final response = await _dio.get<String>(
      url,
      cancelToken: cancel,
      options: Options(headers: headers, responseType: ResponseType.plain),
    );
    return response.data ?? '';
  }

  /// A playlist and its segments describe how many parts there are; a manifest
  /// records that so a later launch can check.
  Future<void> _writeManifest({
    required String dirPath,
    required DownloadKind kind,
    required int parts,
    required int bytes,
  }) async {
    final file = File('$dirPath/${DownloadLayout.manifestName}');
    await file.writeAsString(jsonEncode({
      'kind': kind.id,
      'parts': parts,
      'bytes': bytes,
      'writtenAt': DateTime.now().millisecondsSinceEpoch,
    }));
  }

  void _rejectNonMedia(String? contentType) {
    final type = contentType?.toLowerCase() ?? '';
    if (type.isEmpty) return;
    for (final bad in _nonMediaTypes) {
      if (type.startsWith(bad)) {
        throw _NotMediaException('the server answered with $type');
      }
    }
  }

  int _contentLength(Headers headers) {
    // A ranged response reports the WHOLE size in Content-Range; only the
    // remainder in Content-Length. Reading the wrong one is how a resumed
    // download reports 40% for a file that is nearly finished.
    final range = headers.value('content-range');
    if (range != null) {
      final total = RegExp(r'/(\d+)$').firstMatch(range.trim())?.group(1);
      final parsed = int.tryParse(total ?? '');
      if (parsed != null && parsed > 0) return parsed;
    }
    return int.tryParse(headers.value('content-length') ?? '') ?? 0;
  }

  String _baseOf(String url) {
    final at = url.lastIndexOf('/');
    return at > 0 ? url.substring(0, at + 1) : url;
  }

  String _resolve(String path, String base) {
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    try {
      return Uri.parse(base).resolve(path).toString();
    } catch (_) {
      return '$base$path';
    }
  }

  String? _pickVariant(String playlist, String base) {
    final lines = playlist.split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (!lines[i].startsWith('#EXT-X-STREAM-INF')) continue;
      for (var j = i + 1; j < lines.length; j++) {
        final line = lines[j].trim();
        if (line.isEmpty || line.startsWith('#')) continue;
        return _resolve(line, base);
      }
    }
    return null;
  }

  List<String> _segmentUrls(String playlist, String base) => [
        for (final line in playlist.split('\n'))
          if (line.trim().isNotEmpty && !line.trim().startsWith('#'))
            _resolve(line.trim(), base),
      ];

  String _localPlaylist(String original) {
    var index = 0;
    final out = StringBuffer();
    for (final line in original.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) {
        out.writeln(trimmed);
      } else {
        out.writeln(DownloadLayout.segmentName(index++));
      }
    }
    return out.toString();
  }

  void dispose() => _dio.close(force: true);
}

/// Kept out of the class so `debugPrint` has somewhere to live without pulling
/// Flutter into the transfer path's signatures.
void logTransfer(String message) => debugPrint('[downloads] $message');
