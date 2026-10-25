import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:soplay/core/network/web_page_sniff.dart';
import 'package:soplay/features/detail/domain/entities/media_resolve_entity.dart';

/// What the first 2 KB of a download candidate said.
enum MediaProbeVerdict {
  /// The playlist or a container the downloader can save.
  media,

  /// Markup where the media should be: a challenge, an error or a home page
  /// served with a success status.
  webPage,

  /// An answer that is no good for another reason: an error status, or bytes
  /// that are neither the playlist nor a container this probe knows.
  rejected,

  /// No answer in time, or no connection. That says nothing about the file,
  /// so it must not be read as a no.
  noAnswer,
}

/// Checks download candidates before one is enqueued. Reads only a prefix,
/// never the movie.
class DownloadMediaProbe {
  DownloadMediaProbe(this.dio, {this.timeout = const Duration(seconds: 8)});
  final Dio dio;
  final Duration timeout;

  /// For mixed mirror results: only a candidate that proved itself is taken,
  /// since the next mirror is right there to try instead.
  Future<bool> accepts(MediaResolveEntity media) async =>
      await verdict(media) == MediaProbeVerdict.media;

  /// For a plain direct result, at tap time: true only for a definite web
  /// page. A slow host, an odd container or an error status still queue as
  /// they always did; only a page fails here instead of minutes later in the
  /// list, under a message that says what it is.
  Future<bool> servesWebPage(MediaResolveEntity media) async =>
      await verdict(media) == MediaProbeVerdict.webPage;

  Future<MediaProbeVerdict> verdict(MediaResolveEntity media) async {
    final cancel = CancelToken();
    try {
      final response = await dio
          .get<ResponseBody>(
            media.videoUrl,
            cancelToken: cancel,
            options: Options(
              headers: {...media.headers, 'Range': 'bytes=0-2047'},
              responseType: ResponseType.stream,
              sendTimeout: timeout,
              receiveTimeout: timeout,
              validateStatus: (_) => true,
            ),
          )
          .timeout(timeout);
      if ((response.statusCode ?? 500) >= 400 || response.data == null) {
        return MediaProbeVerdict.rejected;
      }
      final bytes = <int>[];
      await for (final chunk in response.data!.stream.timeout(timeout)) {
        bytes.addAll(chunk.take(2048 - bytes.length));
        if (bytes.length >= webPageSniffBytes) break;
      }
      return classifyPrefix(media, bytes);
    } on TimeoutException {
      return MediaProbeVerdict.noAnswer;
    } on DioException catch (e) {
      // An answer with a status was handled above; without one the request
      // never got that far.
      return e.response == null
          ? MediaProbeVerdict.noAnswer
          : MediaProbeVerdict.rejected;
    } catch (_) {
      return MediaProbeVerdict.noAnswer;
    } finally {
      cancel.cancel('Media prefix checked');
    }
  }

  /// The verdict on the first bytes of [media]'s body.
  static MediaProbeVerdict classifyPrefix(
    MediaResolveEntity media,
    List<int> bytes,
  ) {
    if (looksLikeWebPage(bytes)) return MediaProbeVerdict.webPage;
    final text = utf8.decode(bytes, allowMalformed: true).trimLeft();
    if (media.type == 'hls' || media.videoUrl.contains('.m3u8')) {
      return text.startsWith('#EXTM3U')
          ? MediaProbeVerdict.media
          : MediaProbeVerdict.rejected;
    }
    if (media.type == 'dash' || media.videoUrl.contains('.mpd')) {
      return RegExp(r'<MPD(?:\s|>)').hasMatch(text)
          ? MediaProbeVerdict.media
          : MediaProbeVerdict.rejected;
    }
    return _isContainer(bytes) || text.startsWith('#EXTM3U')
        ? MediaProbeVerdict.media
        : MediaProbeVerdict.rejected;
  }

  /// A file the downloader can keep, by its magic. MP4 and QuickTime were
  /// only taken with `ftyp` first, and a QuickTime file may open with `wide`,
  /// `mdat` or `moov`; AVI and FLV were not taken at all.
  static bool _isContainer(List<int> bytes) {
    if (bytes.isEmpty) return false;
    if (bytes[0] == 0x47) return true; // MPEG-TS sync byte.
    if (bytes.length < 4) return false;
    if (bytes[0] == 0x1a &&
        bytes[1] == 0x45 &&
        bytes[2] == 0xdf &&
        bytes[3] == 0xa3) {
      return true; // EBML: Matroska, WebM.
    }
    final lead = String.fromCharCodes(bytes.sublist(0, 4));
    if (lead == 'RIFF') return true; // AVI.
    if (lead.startsWith('FLV')) return true;
    if (bytes.length < 8) return false;
    const boxes = {'ftyp', 'moov', 'mdat', 'wide', 'free', 'skip', 'styp'};
    return boxes.contains(String.fromCharCodes(bytes.sublist(4, 8)));
  }
}
