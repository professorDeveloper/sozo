import 'package:soplay/features/download/domain/entities/download_kind.dart';

/// Everything needed to queue one download, and nothing about where it will
/// live.
///
/// A separate type from [DownloadItem] because the two answer different
/// questions. A request is what a caller knows — a title, a url, some headers;
/// an item is what the system knows — a path, a status, bytes on disk, a
/// failure. Letting call sites build items directly is how the old code ended
/// up with five places each inventing their own `localPath`, and how one of
/// them could invent a different id for the same episode than another.
class DownloadRequest {
  const DownloadRequest({
    required this.id,
    required this.contentUrl,
    required this.provider,
    required this.title,
    required this.sourceUrl,
    this.kind,
    this.thumbnailUrl,
    this.headers = const {},
    this.isSerial = false,
    this.episodeNumber,
    this.episodeLabel,
    this.pageUrls = const [],
    this.chapterRef,
    this.chapterIndex,
  });

  /// A movie or one episode of a series.
  ///
  /// The id is built here rather than by the caller so the player, the episode
  /// list and the detail page cannot disagree about it — when they did, the
  /// list showed no progress for a download the player had started, and
  /// starting it from the other screen downloaded the same file twice.
  factory DownloadRequest.video({
    required String contentUrl,
    required String provider,
    required String title,
    required String sourceUrl,
    String? thumbnailUrl,
    Map<String, String> headers = const {},
    bool isSerial = false,
    int? episodeNumber,
    String? episodeLabel,
  }) =>
      DownloadRequest(
        id: videoId(contentUrl: contentUrl, episodeNumber: episodeNumber),
        contentUrl: contentUrl,
        provider: provider,
        title: title,
        sourceUrl: sourceUrl,
        kind: DownloadKind.fromLegacy('video', sourceUrl),
        thumbnailUrl: thumbnailUrl,
        headers: headers,
        isSerial: isSerial,
        episodeNumber: episodeNumber,
        episodeLabel: episodeLabel,
      );

  /// One manga / manhwa / novel chapter.
  factory DownloadRequest.mangaChapter({
    required String contentUrl,
    required String provider,
    required String title,
    String? thumbnailUrl,
    Map<String, String> headers = const {},
    List<String> pageUrls = const [],
    required String chapterRef,
    int? chapterIndex,
    int? episodeNumber,
    String? episodeLabel,
  }) =>
      DownloadRequest(
        id: mangaChapterId(
          contentUrl: contentUrl,
          provider: provider,
          chapterRef: chapterRef,
        ),
        contentUrl: contentUrl,
        provider: provider,
        title: title,
        sourceUrl: '',
        kind: DownloadKind.manga,
        thumbnailUrl: thumbnailUrl,
        headers: headers,
        isSerial: true,
        episodeNumber: episodeNumber,
        episodeLabel: episodeLabel,
        pageUrls: pageUrls,
        chapterRef: chapterRef,
        chapterIndex: chapterIndex,
      );

  final String id;
  final String contentUrl;
  final String provider;
  final String title;
  final String sourceUrl;

  /// Null lets the repository decide from [sourceUrl]. Passed explicitly only
  /// where the caller genuinely knows better.
  final DownloadKind? kind;

  final String? thumbnailUrl;
  final Map<String, String> headers;
  final bool isSerial;
  final int? episodeNumber;
  final String? episodeLabel;
  final List<String> pageUrls;
  final String? chapterRef;
  final int? chapterIndex;

  /// FNV-1a, because `String.hashCode` is not stable across Dart runs and a
  /// download id that changes between launches is a download nobody can find
  /// again.
  static String _fnv(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(36);
  }

  /// Id for an episode, or for a movie when [episodeNumber] is null.
  ///
  /// Byte-identical to what the old `DownloadService.videoId` produced, so an
  /// install upgrading keeps every download it already had.
  static String videoId({
    required String contentUrl,
    int? episodeNumber,
  }) =>
      _fnv(
        episodeNumber == null ? contentUrl : '${contentUrl}_ep$episodeNumber',
      );

  static String mangaChapterId({
    required String contentUrl,
    required String provider,
    required String chapterRef,
  }) =>
      _fnv('manga|$contentUrl|$provider|$chapterRef');
}
