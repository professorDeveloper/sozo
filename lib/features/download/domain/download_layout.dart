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
  }) =>
      switch (kind) {
        DownloadKind.manga => dirFor(id),
        DownloadKind.hls => '${dirFor(id)}/$hlsIndexName',
        DownloadKind.video =>
          '${dirFor(id)}/$videoStemName${extension ?? '.mp4'}',
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

  static String segmentName(int index) => 'seg_$index.ts';

  static String pageName(int index, String extension) =>
      'p_${index.toString().padLeft(3, '0')}$extension';

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
