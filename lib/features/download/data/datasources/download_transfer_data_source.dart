import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:soplay/core/player/hls_variants.dart';
import 'package:soplay/core/network/http_headers.dart';
import 'package:soplay/features/download/domain/download_layout.dart';
import 'package:soplay/features/download/domain/entities/download_failure.dart';
import 'package:soplay/features/download/domain/entities/download_kind.dart';

/// A slice of a larger file, as an HLS `#EXT-X-BYTERANGE` names it.
typedef HlsByteRange = ({int offset, int length});

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
  }) : failure = null,
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
    : _dio =
          dio ??
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

  /// Segments in flight at once. One at a time left most of a connection idle
  /// — each segment is a few hundred KB, so the round trip, not the bandwidth,
  /// set the pace — and a 24-minute episode took as long to save as to watch.
  /// Four keeps a CDN busy without looking like a crawler.
  static const int _segmentWorkers = 4;

  /// Pages and chapter pictures in flight at once. Image hosts are smaller and
  /// quicker to rate-limit than video CDNs.
  static const int _pageWorkers = 3;

  /// A single file whose connection drops midway picks up from the bytes it
  /// has, this many times, before the download is called failed.
  static const int _fileResumes = 3;

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
    String? chapterHtml,
    List<Map<String, String>> imageHeaders = const [],
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
        // One kind, two shapes. A comic chapter is a folder of images; a
        // novel chapter is one document, whose pictures are fetched into the
        // same folder so the words and the illustrations are deleted together.
        DownloadKind.manga => (chapterHtml ?? '').trim().isNotEmpty
            ? await _prose(
                dirPath: dirPath,
                html: chapterHtml!,
                sourceUrl: sourceUrl,
                headers: headers,
                cancel: cancel,
                onProgress: onProgress,
              )
            : await _pages(
                dirPath: dirPath,
                pageUrls: pageUrls,
                imageHeaders: imageHeaders,
                headers: headers,
                cancel: cancel,
                onProgress: onProgress,
              ),
      };
    } on _NotMediaException catch (e) {
      return TransferResult.failed(DownloadFailureKind.notMedia, e.message);
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        return const TransferResult.failed(
          DownloadFailureKind.unknown,
          'cancelled',
        );
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

    var written = 0;
    var total = 0;
    // A dropped connection used to fail the whole file and wait out the
    // queue's retry backoff before a new request resumed it. It resumes here,
    // at once, from the bytes already on disk.
    for (var round = 0; ; round++) {
      try {
        final got = await _directOnce(
          url: url,
          part: part,
          headers: headers,
          cancel: cancel,
          knownTotal: total,
          onProgress: onProgress,
        );
        written = got.written;
        total = got.total;
        if (cancel.isCancelled) {
          return const TransferResult.failed(
            DownloadFailureKind.unknown,
            'cancelled',
          );
        }
        if (total > 0 && written < total && round < _fileResumes) continue;
        break;
      } on DioException catch (e) {
        if (CancelToken.isCancel(e) ||
            !_resumable(e) ||
            round >= _fileResumes) {
          rethrow;
        }
        await Future<void>.delayed(Duration(milliseconds: 800 * (round + 1)));
      } on FileSystemException {
        rethrow;
      } on _NotMediaException {
        rethrow;
      } on SocketException {
        if (round >= _fileResumes) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 800 * (round + 1)));
      } on HttpException {
        if (round >= _fileResumes) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 800 * (round + 1)));
      }
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

  /// One request for the rest of [part]: from the bytes it already holds, or
  /// from the start when the server will not serve a range.
  Future<({int written, int total})> _directOnce({
    required String url,
    required File part,
    required Map<String, String> headers,
    required CancelToken cancel,
    required int knownTotal,
    required void Function(TransferProgress) onProgress,
  }) async {
    final existing = await part.exists() ? await part.length() : 0;
    if (knownTotal > 0 && existing >= knownTotal) {
      return (written: existing, total: knownTotal);
    }

    final response = await _dio.get<ResponseBody>(
      url,
      cancelToken: cancel,
      options: Options(
        headers: {...headers, if (existing > 0) 'Range': 'bytes=$existing-'},
        responseType: ResponseType.stream,
      ),
    );

    _rejectNonMedia(response.headers.value('content-type'));

    // 206 means the server honoured the range; anything else means starting
    // over, and appending to the old bytes would corrupt the file silently.
    final append = existing > 0 && response.statusCode == 206;
    if (!append && await part.exists()) await part.delete();

    final declared = _contentLength(response.headers);
    final total = declared > 0
        ? (append && !_hasContentRange(response.headers)
              ? existing + declared
              : declared)
        : knownTotal;
    var written = append ? existing : 0;

    // Reported every quarter second rather than per chunk: a fast link
    // delivers hundreds of chunks a second, and each report is a row rebuilt
    // on the other side.
    final sinceReport = Stopwatch()..start();
    final sink = part.openWrite(
      mode: append ? FileMode.append : FileMode.write,
    );
    try {
      await for (final chunk in response.data!.stream) {
        if (cancel.isCancelled) break;
        sink.add(chunk);
        written += chunk.length;
        if (sinceReport.elapsedMilliseconds >= 250) {
          sinceReport.reset();
          onProgress(
            TransferProgress(
              completedUnits: written,
              totalUnits: total,
              sizeBytes: written,
            ),
          );
        }
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    onProgress(
      TransferProgress(
        completedUnits: written,
        totalUnits: total,
        sizeBytes: written,
      ),
    );
    return (written: written, total: total);
  }

  /// A failure the bytes already on disk can recover from: the connection,
  /// not the answer.
  static bool _resumable(DioException e) => switch (e.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.connectionError => true,
    DioExceptionType.unknown =>
      e.error is SocketException || e.error is HttpException,
    _ => false,
  };

  static bool _hasContentRange(Headers headers) =>
      (headers.value('content-range') ?? '').contains('/');

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

    final segments = mediaSegments(playlist, _baseOf(playlistUrl));
    if (segments.isEmpty) {
      return const TransferResult.failed(
        DownloadFailureKind.notMedia,
        'no segments in the playlist',
      );
    }

    // Keys and init segments. The playlist used to be saved with their URIs
    // untouched — pointing at the CDN, or relative to a folder that does not
    // exist on the device — so an AES-128 stream downloaded every segment and
    // then could not decrypt one of them offline, and an fMP4 stream had no
    // header to start decoding from. They are fetched like segments and the
    // playlist is rewritten to the local copies.
    final auxNames = <String, String>{};
    final aux = auxiliaryUris(playlist);
    for (var i = 0; i < aux.length; i++) {
      if (cancel.isCancelled) {
        return const TransferResult.failed(
          DownloadFailureKind.unknown,
          'cancelled',
        );
      }
      final entry = aux[i];
      final resolved = _resolve(entry.uri, _baseOf(playlistUrl));
      // A `data:` key is already inline, and an `skd://` one is FairPlay,
      // which no file on disk could stand in for. Both stay as they are.
      if (!resolved.startsWith('http://') && !resolved.startsWith('https://')) {
        continue;
      }
      final name = entry.isMap
          ? DownloadLayout.hlsMapName(i, _mapExtensionFor(resolved))
          : DownloadLayout.hlsKeyName(i);
      final file = File('$dirPath/$name');
      if (!await file.exists() || await file.length() <= 0) {
        await _fetchToFile(
          url: resolved,
          file: file,
          headers: headers,
          cancel: cancel,
          attempts: _segmentAttempts,
          range: entry.range,
          // A key is sixteen raw bytes, and servers label it as anything —
          // text/plain included. The media check would refuse a good key.
          checkMedia: false,
        );
      }
      auxNames[entry.key] = name;
    }

    var bytes = 0;
    var done = 0;
    await _pool(segments.length, _segmentWorkers, cancel, (i) async {
      final file = File('$dirPath/${DownloadLayout.segmentName(i)}');
      // A segment already on disk is only trusted if it is non-empty. The old
      // code trusted any file that existed, so a segment truncated by a killed
      // process was never re-fetched and the episode played to that point and
      // stopped.
      if (!await file.exists() || await file.length() <= 0) {
        await _fetchToFile(
          url: segments[i].url,
          file: file,
          headers: headers,
          cancel: cancel,
          attempts: _segmentAttempts,
          range: segments[i].range,
        );
      }
      if (cancel.isCancelled) return;
      bytes += await file.length();
      done++;
      onProgress(
        TransferProgress(
          completedUnits: done,
          totalUnits: segments.length,
          sizeBytes: bytes,
        ),
      );
    });
    if (cancel.isCancelled) {
      return const TransferResult.failed(
        DownloadFailureKind.unknown,
        'cancelled',
      );
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
    await File(
      '$dirPath/${DownloadLayout.hlsIndexName}',
    ).writeAsString(localPlaylist(playlist, auxNames));

    return TransferResult.success(
      artefactPath: '$dirPath/${DownloadLayout.hlsIndexName}',
      completedUnits: segments.length,
      totalUnits: segments.length,
      sizeBytes: bytes,
    );
  }

  // --- prose ---------------------------------------------------------------

  /// Every `src` an `<img>` in [html] points at, in the order they appear.
  ///
  /// A regex rather than a parser. The app does not carry an HTML parser for
  /// this, the shape being matched is one attribute on one tag, and a source
  /// that writes something this cannot see loses a picture rather than the
  /// chapter — which is the right way round for a fallback.
  ///
  /// Data URIs are skipped: the bytes are already in the document, so fetching
  /// them would write the same image to disk twice.
  static List<String> imageSources(String html) {
    final out = <String>[];
    for (final m in _imgSrc.allMatches(html)) {
      final raw = (m.group(3) ?? m.group(4) ?? m.group(5) ?? '').trim();
      if (raw.isEmpty) continue;
      if (raw.startsWith('data:')) continue;
      if (out.contains(raw)) continue;
      out.add(raw);
    }
    return out;
  }

  /// `<img ... src=` and the value after it, quoted or bare.
  static final RegExp _imgSrc = RegExp(
    r'''(<img\b[^>]*?\bsrc\s*=\s*)("([^"]*)"|'([^']*)'|([^\s>]+))''',
    caseSensitive: false,
    dotAll: true,
  );

  /// Rewrites each `src` in [replacements] to the file written beside the
  /// document.
  ///
  /// Whole-attribute replacement, not a bare string swap: a url that also
  /// appears in an `href` or in the prose itself must keep pointing where it
  /// pointed, and one url that is a prefix of another must not eat it.
  ///
  /// Used twice: once on the way to disk, to point the document at the files
  /// written beside it, and once on the way back out, to turn those names into
  /// the absolute paths the reader can actually open. One rule, so the two
  /// directions cannot disagree about what counts as a `src`.
  static String rewriteImageSources(
    String html,
    Map<String, String> replacements,
  ) {
    if (replacements.isEmpty) return html;
    return html.replaceAllMapped(_imgSrc, (m) {
      final raw = (m.group(3) ?? m.group(4) ?? m.group(5) ?? '').trim();
      final local = replacements[raw];
      if (local == null) return m.group(0)!;
      return '${m.group(1)}"$local"';
    });
  }

  /// A novel chapter: the document, and the pictures it points at.
  ///
  /// The images are fetched into the same folder and the document rewritten to
  /// name them, so what lands on disk is self-contained. That is what makes
  /// deleting the chapter delete its pictures as well — a folder goes as one
  /// thing, where an html file and a pile of images beside it would not.
  ///
  /// An image that will not fetch is left pointing at its original url rather
  /// than failing the chapter. The prose is what was asked for, and a picture
  /// that loads when there is signal and shows a gap when there is not is a far
  /// better answer than no chapter at all.
  Future<TransferResult> _prose({
    required String dirPath,
    required String html,
    required String sourceUrl,
    required Map<String, String> headers,
    required CancelToken cancel,
    required void Function(TransferProgress) onProgress,
  }) async {
    final sources = imageSources(html);
    final base = Uri.tryParse(sourceUrl);
    final replacements = <String, String>{};
    var bytes = 0;
    var done = 0;

    await _pool(sources.length, _pageWorkers, cancel, (i) async {
      final resolved = _absolute(sources[i], base);
      if (resolved == null) return;
      final name = DownloadLayout.pageName(
        i,
        DownloadLayout.imageExtensionFor(resolved),
      );
      final file = File('$dirPath/$name');
      try {
        if (!await file.exists() || await file.length() <= 0) {
          await _fetchToFile(
            url: resolved,
            file: file,
            headers: headers,
            cancel: cancel,
            attempts: _segmentAttempts,
          );
        }
        bytes += await file.length();
        replacements[sources[i]] = name;
      } catch (e) {
        if (cancel.isCancelled) return;
        debugPrint('[downloads] chapter image ${sources[i]} failed: $e');
      }
      done++;
      onProgress(
        TransferProgress(
          completedUnits: done,
          totalUnits: sources.length + 1,
          sizeBytes: bytes,
        ),
      );
    });
    if (cancel.isCancelled) {
      return const TransferResult.failed(
        DownloadFailureKind.unknown,
        'cancelled',
      );
    }

    final document = rewriteImageSources(html, replacements);
    final file = File('$dirPath/${DownloadLayout.chapterHtmlName}');
    await file.writeAsString(document, flush: true);
    bytes += await file.length();

    await _writeManifest(
      dirPath: dirPath,
      kind: DownloadKind.manga,
      parts: replacements.length + 1,
      bytes: bytes,
    );

    return TransferResult.success(
      artefactPath: dirPath,
      completedUnits: sources.length + 1,
      totalUnits: sources.length + 1,
      sizeBytes: bytes,
    );
  }

  /// A page-relative `src` against the chapter's own url.
  ///
  /// Null when there is nothing fetchable — a relative path with no base to
  /// resolve against, or a scheme that is not http(s). The caller leaves the
  /// original `src` alone then, so the picture still loads online.
  static String? _absolute(String src, Uri? base) {
    final uri = Uri.tryParse(src);
    if (uri == null) return null;
    final resolved = uri.hasScheme ? uri : base?.resolveUri(uri);
    if (resolved == null) return null;
    if (resolved.scheme != 'http' && resolved.scheme != 'https') return null;
    return resolved.toString();
  }

  // --- pages ---------------------------------------------------------------

  Future<TransferResult> _pages({
    required String dirPath,
    required List<String> pageUrls,
    List<Map<String, String>> imageHeaders = const [],
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
    var done = 0;
    await _pool(pageUrls.length, _pageWorkers, cancel, (i) async {
      final name = DownloadLayout.pageName(
        i,
        DownloadLayout.imageExtensionFor(pageUrls[i]),
      );
      final file = File('$dirPath/$name');
      if (!await file.exists() || await file.length() <= 0) {
        await _fetchToFile(
          url: pageUrls[i],
          file: file,
          headers: mergeHttpHeaders([
            headers,
            if (i < imageHeaders.length) imageHeaders[i],
          ]),
          cancel: cancel,
          attempts: _segmentAttempts,
        );
      }
      if (cancel.isCancelled) return;
      bytes += await file.length();
      done++;
      onProgress(
        TransferProgress(
          completedUnits: done,
          totalUnits: pageUrls.length,
          sizeBytes: bytes,
        ),
      );
    });
    if (cancel.isCancelled) {
      return const TransferResult.failed(
        DownloadFailureKind.unknown,
        'cancelled',
      );
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
  ///
  /// Streamed to the `.part` file as it arrives. It used to be read whole into
  /// memory first — every segment and every page a full byte array on the
  /// heap before a single byte reached the disk, which on a 4K segment is tens
  /// of megabytes held for nothing.
  Future<void> _fetchToFile({
    required String url,
    required File file,
    required Map<String, String> headers,
    required CancelToken cancel,
    required int attempts,
    HlsByteRange? range,
    bool checkMedia = true,
  }) async {
    final part = File(DownloadLayout.partOf(file.path));
    Object? lastError;
    for (var attempt = 0; attempt < attempts; attempt++) {
      if (cancel.isCancelled) return;
      try {
        final response = await _dio.get<ResponseBody>(
          url,
          cancelToken: cancel,
          options: Options(
            headers: {
              ...headers,
              if (range != null)
                'Range':
                    'bytes=${range.offset}-${range.offset + range.length - 1}',
            },
            responseType: ResponseType.stream,
          ),
        );
        if (checkMedia) {
          _rejectNonMedia(response.headers.value('content-type'));
        }
        // A server that ignores the Range header sends the whole file. The
        // slice is cut out of it rather than saving every segment as a full
        // copy of the one file they all live in.
        var skip = range != null && response.statusCode != 206
            ? range.offset
            : 0;
        var want = range?.length ?? -1;
        var written = 0;
        final sink = part.openWrite();
        try {
          await for (var chunk in response.data!.stream) {
            if (cancel.isCancelled) break;
            if (skip > 0) {
              if (chunk.length <= skip) {
                skip -= chunk.length;
                continue;
              }
              chunk = Uint8List.sublistView(chunk, skip);
              skip = 0;
            }
            if (want >= 0 && chunk.length > want - written) {
              chunk = Uint8List.sublistView(chunk, 0, want - written);
            }
            sink.add(chunk);
            written += chunk.length;
            if (want >= 0 && written >= want) break;
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
        if (cancel.isCancelled) {
          if (await part.exists()) await part.delete();
          return;
        }
        if (written <= 0) {
          throw const _NotMediaException('empty part');
        }
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
    await file.writeAsString(
      jsonEncode({
        'kind': kind.id,
        'parts': parts,
        'bytes': bytes,
        'writtenAt': DateTime.now().millisecondsSinceEpoch,
      }),
    );
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

  String _resolve(String path, String base) => _resolveStatic(path, base);

  static String _resolveStatic(String path, String base) {
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    try {
      return Uri.parse(base).resolve(path).toString();
    } catch (_) {
      return '$base$path';
    }
  }

  /// Runs [task] for every index below [count], [workers] at a time.
  ///
  /// The first failure stops new work from being handed out; the parts in
  /// flight finish (or fail) and then it is rethrown. A cancel stops the
  /// hand-out the same way and returns quietly — the caller asks the token.
  static Future<void> _pool(
    int count,
    int workers,
    CancelToken cancel,
    Future<void> Function(int index) task,
  ) async {
    var next = 0;
    Object? error;
    StackTrace? trace;
    Future<void> worker() async {
      while (error == null && !cancel.isCancelled) {
        final i = next++;
        if (i >= count) return;
        try {
          await task(i);
        } catch (e, st) {
          error ??= e;
          trace ??= st;
          return;
        }
      }
    }

    await Future.wait([
      for (var w = 0; w < (count < workers ? count : workers); w++) worker(),
    ]);
    if (error != null) Error.throwWithStackTrace(error!, trace!);
  }

  /// The rendition to save out of a master playlist: the best one.
  ///
  /// This used to return whichever variant was listed first. Packagers commonly
  /// order a master lowest-bitrate-first — a client is supposed to start
  /// conservatively and adapt upward — so "first" meant the file on disk was
  /// the 480p rendition of a stream the player had been showing at 1080p. The
  /// download completed, sat in the list, and looked blurry, with nothing on
  /// screen to suggest a quality had been chosen at all.
  ///
  /// Nobody downloads a film in order to watch the smallest copy of it, so the
  /// best rendition is the answer rather than a setting.
  String? _pickVariant(String playlist, String base) {
    final uri = Uri.tryParse(base);
    if (uri == null) return null;
    final variants = parseHlsVariants(playlist, uri);
    if (variants.isNotEmpty) return variants.first.url;

    // A master whose variants state neither a name nor a RESOLUTION: the
    // highest bitrate that carries a picture. "First" was the smallest here
    // too — Apple's own sample lists 232 kbps ahead of 1.9 Mbps.
    final best = bestByBandwidth(playlist, base);
    if (best != null) return best;
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

  /// Every media segment in [playlist], resolved against [base], with the
  /// slice of its file when the playlist says `#EXT-X-BYTERANGE`.
  ///
  /// A byte-range playlist names one file for every segment. Read as plain
  /// urls it downloaded that whole file once per segment — a 1 GB episode
  /// became hundreds of gigabytes, or a full disk.
  @visibleForTesting
  static List<({String url, HlsByteRange? range})> mediaSegments(
    String playlist,
    String base,
  ) {
    final out = <({String url, HlsByteRange? range})>[];
    // Where the previous slice of each file ended: a BYTERANGE with no offset
    // continues from there.
    final ends = <String, int>{};
    ({int length, int? offset})? pending;
    for (final raw in playlist.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#EXT-X-BYTERANGE:')) {
        pending = _byteRange(line.substring('#EXT-X-BYTERANGE:'.length));
        continue;
      }
      if (line.startsWith('#')) continue;
      final url = _resolveStatic(line, base);
      HlsByteRange? range;
      final p = pending;
      if (p != null) {
        final offset = p.offset ?? ends[url] ?? 0;
        range = (offset: offset, length: p.length);
        ends[url] = offset + p.length;
      }
      pending = null;
      out.add((url: url, range: range));
    }
    return out;
  }

  /// `length[@offset]`, as `#EXT-X-BYTERANGE` and `BYTERANGE=` write it.
  static ({int length, int? offset})? _byteRange(String raw) {
    final m = RegExp(r'^\s*"?(\d+)(?:@(\d+))?"?').firstMatch(raw);
    final length = int.tryParse(m?.group(1) ?? '');
    if (length == null || length <= 0) return null;
    return (length: length, offset: int.tryParse(m?.group(2) ?? ''));
  }

  static final RegExp _bandwidth = RegExp(r'[^-]BANDWIDTH=(\d+)');
  static final RegExp _codecs = RegExp(r'CODECS="([^"]*)"');

  /// The variant with the highest BANDWIDTH, leaving out audio-only ones.
  @visibleForTesting
  static String? bestByBandwidth(String playlist, String base) {
    final lines = playlist.split(RegExp(r'\r?\n'));
    String? best;
    var bestBandwidth = 0;
    for (var i = 0; i < lines.length; i++) {
      final tag = lines[i].trim();
      if (!tag.startsWith('#EXT-X-STREAM-INF')) continue;
      final codecs = _codecs.firstMatch(tag)?.group(1)?.toLowerCase();
      if (codecs != null && _audioOnly(codecs)) continue;
      final bw = int.tryParse(_bandwidth.firstMatch(tag)?.group(1) ?? '') ?? 0;
      String? uri;
      for (var j = i + 1; j < lines.length; j++) {
        final line = lines[j].trim();
        if (line.isEmpty || line.startsWith('#')) continue;
        uri = line;
        break;
      }
      if (uri == null || bw <= bestBandwidth) continue;
      best = _resolveStatic(uri, base);
      bestBandwidth = bw;
    }
    return best;
  }

  static bool _audioOnly(String codecs) => codecs
      .split(',')
      .map((c) => c.trim())
      .where((c) => c.isNotEmpty)
      .every(
        (c) =>
            c.startsWith('mp4a') ||
            c.startsWith('ac-3') ||
            c.startsWith('ec-3') ||
            c.startsWith('opus') ||
            c.startsWith('flac'),
      );

  static final RegExp _uriAttribute = RegExp(r'URI="([^"]*)"');
  static final RegExp _byteRangeAttribute = RegExp(r',?BYTERANGE="([^"]*)"');

  /// How one key or init-segment line is told apart from another: its URI,
  /// and for an init segment cut from a larger file, the slice.
  static String _auxKey(String uri, String? byteRange) =>
      byteRange == null ? uri : '$uri#$byteRange';

  /// The key and init-segment URIs a media playlist refers to, each once, in
  /// the order they first appear.
  ///
  /// `METHOD=NONE` keys carry no file and are left out.
  @visibleForTesting
  static List<({String uri, bool isMap, String key, HlsByteRange? range})>
  auxiliaryUris(String playlist) {
    final out = <({String uri, bool isMap, String key, HlsByteRange? range})>[];
    final seen = <String>{};
    for (final raw in playlist.split('\n')) {
      final line = raw.trim();
      final isKey = line.startsWith('#EXT-X-KEY:');
      final isMap = line.startsWith('#EXT-X-MAP:');
      if (!isKey && !isMap) continue;
      if (isKey && line.contains('METHOD=NONE')) continue;
      final uri = _uriAttribute.firstMatch(line)?.group(1);
      if (uri == null || uri.isEmpty) continue;
      final rawRange = isMap
          ? _byteRangeAttribute.firstMatch(line)?.group(1)
          : null;
      final key = _auxKey(uri, rawRange);
      if (!seen.add(key)) continue;
      final parsed = rawRange == null ? null : _byteRange(rawRange);
      out.add((
        uri: uri,
        isMap: isMap,
        key: key,
        range: parsed == null
            ? null
            : (offset: parsed.offset ?? 0, length: parsed.length),
      ));
    }
    return out;
  }

  /// [original] pointed at the files on disk: segments by position, and every
  /// key or init-segment URI found in [auxNames] replaced by its local name.
  @visibleForTesting
  static String localPlaylist(
    String original, [
    Map<String, String> auxNames = const {},
  ]) {
    var index = 0;
    final out = StringBuffer();
    for (final line in original.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        out.writeln(trimmed);
      } else if (trimmed.startsWith('#EXT-X-BYTERANGE:')) {
        // Each slice is its own file on disk now; the range would be read
        // against that file and point past its end.
        continue;
      } else if (trimmed.startsWith('#')) {
        if (auxNames.isEmpty) {
          out.writeln(trimmed);
          continue;
        }
        final range = trimmed.startsWith('#EXT-X-MAP:')
            ? _byteRangeAttribute.firstMatch(trimmed)?.group(1)
            : null;
        final uri = _uriAttribute.firstMatch(trimmed)?.group(1);
        final local = uri == null ? null : auxNames[_auxKey(uri, range)];
        if (local == null) {
          out.writeln(trimmed);
          continue;
        }
        var rewritten = trimmed.replaceFirst(_uriAttribute, 'URI="$local"');
        if (range != null) {
          rewritten = rewritten.replaceFirst(_byteRangeAttribute, '');
        }
        out.writeln(rewritten);
      } else {
        out.writeln(DownloadLayout.segmentName(index++));
      }
    }
    return out.toString();
  }

  String _mapExtensionFor(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    for (final ext in const ['.mp4', '.m4s', '.m4v', '.cmfv', '.ts']) {
      if (path.endsWith(ext)) return ext;
    }
    return '.mp4';
  }

  void dispose() => _dio.close(force: true);
}

/// Kept out of the class so `debugPrint` has somewhere to live without pulling
/// Flutter into the transfer path's signatures.
void logTransfer(String message) => debugPrint('[downloads] $message');
