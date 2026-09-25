import 'package:soplay/features/download/domain/entities/download_kind.dart';

/// Where a download lives, expressed WITHOUT the device.
///
/// ## The bug this exists to end
///
/// Every download used to store an absolute path:
///
/// ```
/// /data/user/0/com.soplay.sozo/app_flutter/downloads/g8vhps/index.m3u8
/// ```
///
/// That string is not a property of the download. The `0` is the Android user
/// id, so the same install reached from a work profile or a secondary user
/// resolves its documents directory to `/data/user/10/…`; a restore onto
/// another device, and Android's own `/data/data/…` alias for the same
/// directory, produce a third and a fourth spelling. Any of them makes
/// `File(localPath).existsSync()` false for a file that is sitting right
/// there — and the row still said "Downloaded", because the status came from
/// Hive and the bytes came from the filesystem and nothing compared the two.
///
/// So nothing persisted is ever absolute. What is stored is the layout below,
/// which is derived from the download's own id and kind, and the root is
/// resolved fresh on every launch.
///
/// Pure by construction: no `dart:io`, no plugins, no clock. A test keeps it
/// that way.
abstract final class DownloadLayout {
  /// The single folder every download lives under, relative to the app's
  /// documents directory.
  static const String root = 'downloads';

  /// This item's own folder, relative to [root]'s parent.
  static String dirFor(String id) => '$root/$id';

  /// The artefact a viewer opens, relative to [root]'s parent.
  ///
  /// For [DownloadKind.manga] that is the FOLDER — a chapter is its pages, and
  /// there is no single file to name.
  static String artefactFor(
    String id, {
    required DownloadKind kind,
    String? extension,
  }) => switch (kind) {
    DownloadKind.manga => dirFor(id),
    DownloadKind.hls => '${dirFor(id)}/$hlsIndexName',
    DownloadKind.video => '${dirFor(id)}/$videoStemName${extension ?? '.mp4'}',
  };

  /// The playlist rewritten to point at local segments.
  static const String hlsIndexName = 'index.m3u8';

  /// Base name of a single-file video, so the extension can vary without the
  /// rest of the app having to guess at it.
  static const String videoStemName = 'video';

  /// The cached poster, so the list still draws while offline.
  static String thumbnailFor(String id, String extension) =>
      '${dirFor(id)}/thumbnail$extension';

  /// Where a transfer writes before it is finished.
  ///
  /// Nothing is ever written straight to its final name. A process killed
  /// mid-transfer used to leave a partial `video.mp4` that the next launch
  /// could not tell from a complete one — it existed, it was non-empty, and
  /// the verifier had nothing else to go on. Writing to `.part` and renaming
  /// on success makes the final name mean "this finished".
  static String partOf(String path) => '$path.part';

  /// The record a multi-part download leaves so it can be verified later.
  ///
  /// An HLS download is a playlist and N segments; a manga chapter is N
  /// pages. Without knowing N, "is this complete" cannot be answered after the
  /// fact — which is how a half-downloaded episode came back as `completed`.
  static String manifestFor(String id) => '${dirFor(id)}/$manifestName';

  /// File name of that record, for code that already has the folder.
  static const String manifestName = 'manifest.json';

  /// The row, written beside a finished download so the folder can describe
  /// itself without the Hive box.
  static const String sidecarName = 'item.json';

  /// [relative] moved from download [fromId]'s folder to [toId]'s. Anything not
  /// under [fromId]'s folder is returned unchanged.
  static String rekeyed(String relative, String fromId, String toId) {
    final from = dirFor(fromId);
    if (relative == from) return dirFor(toId);
    if (relative.startsWith('$from/')) {
      return '${dirFor(toId)}${relative.substring(from.length)}';
    }
    return relative;
  }

  static String segmentName(int index) => 'seg_$index.ts';

  /// A decryption key an HLS playlist points at (`#EXT-X-KEY`).
  static String hlsKeyName(int index) => 'key_$index.bin';

  /// An initialisation segment an HLS playlist points at (`#EXT-X-MAP`) —
  /// what fMP4 streams need before the first media segment can be decoded.
  static String hlsMapName(int index, String extension) =>
      'init_$index$extension';

  /// A stream whose audio is a rendition of its own (`#EXT-X-MEDIA`) is saved
  /// as two playlists under a small master at [hlsIndexName]: the video one
  /// here, the audio one at [hlsAudioPlaylistName]. Audio files carry an
  /// `aud_` prefix so the `seg_` count the verifier checks is the video's.
  static const String hlsVideoPlaylistName = 'video.m3u8';
  static const String hlsAudioPlaylistName = 'audio.m3u8';
  static String audioSegmentName(int index) => 'aud_$index.ts';
  static String hlsAudioKeyName(int index) => 'aud_key_$index.bin';
  static String hlsAudioMapName(int index, String extension) =>
      'aud_init_$index$extension';

  static String pageName(int index, String extension) =>
      'p_${index.toString().padLeft(3, '0')}$extension';

  /// A novel chapter's prose.
  ///
  /// A comic chapter is a folder of `p_*` images; a novel chapter is one HTML
  /// document, and it used to be neither — [DownloadTransferDataSource] was
  /// handed an empty page list and failed the whole download with "the chapter
  /// has no pages", so a novel could not be saved for offline at all.
  ///
  /// The images a chapter's prose references are written beside it under
  /// [pageName], and the document that lands here has its `src` attributes
  /// rewritten to those names — so the folder is self-contained and deleting it
  /// takes the pictures with the words.
  static const String chapterHtmlName = 'chapter.html';

  static String chapterHtmlFor(String id) => '${dirFor(id)}/$chapterHtmlName';

  /// Recovers a relative path from whatever an older build stored.
  ///
  /// Returns null when the string carries nothing usable, in which case the
  /// caller rebuilds the path from the id — the layout is deterministic, so
  /// the id is enough.
  static String? relativeFromLegacy(String? stored) {
    final value = stored?.trim();
    if (value == null || value.isEmpty) return null;

    // Already relative.
    if (value.startsWith('$root/')) return value;

    // Absolute: keep everything from the last `/downloads/` onward, which is
    // exactly the part that does not depend on the device.
    final marker = '/$root/';
    final at = value.lastIndexOf(marker);
    if (at >= 0) return '$root/${value.substring(at + marker.length)}';

    return null;
  }

  /// The extension a single-file video should be saved under.
  ///
  /// Read from the url's PATH, never the query string — plenty of these links
  /// carry `?file=x.mp4` on top of a url whose own path is an opaque token.
  static String videoExtensionFor(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
    for (final ext in const ['.mp4', '.mkv', '.webm', '.m4v', '.ts']) {
      if (path.endsWith(ext)) return ext;
    }
    return '.mp4';
  }

  static String imageExtensionFor(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
    for (final ext in const ['.png', '.webp', '.gif', '.jpeg']) {
      if (path.endsWith(ext)) return ext;
    }
    return '.jpg';
  }
}
