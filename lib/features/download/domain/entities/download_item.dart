import 'package:soplay/features/download/domain/download_layout.dart';
import 'package:soplay/features/download/domain/entities/download_failure.dart';
import 'package:soplay/features/download/domain/entities/download_kind.dart';
import 'package:soplay/features/download/domain/entities/download_status.dart';

/// One thing the viewer asked to keep.
///
/// Pure data: no `dart:io`, no paths that mention this device, no plugin. What
/// it knows about storage is [relativePath], which is device-independent by
/// construction — see [DownloadLayout]. Turning that into something openable
/// is the repository's job, because only the repository knows where the root
/// is on this launch.
class DownloadItem {
  const DownloadItem({
    required this.id,
    required this.contentUrl,
    required this.provider,
    required this.title,
    required this.sourceUrl,
    required this.relativePath,
    required this.createdAt,
    this.kind = DownloadKind.video,
    this.thumbnailUrl,
    this.thumbnailRelativePath,
    this.headers = const {},
    this.status = DownloadStatus.pending,
    this.unit = DownloadUnit.bytes,
    this.completedUnits = 0,
    this.totalUnits = 0,
    this.sizeBytes = 0,
    this.isSerial = false,
    this.episodeNumber,
    this.episodeLabel,
    this.pageUrls = const [],
    this.chapterRef,
    this.chapterIndex,
    this.failure,
    this.failureDetail = '',
    this.attempts = 0,
    this.updatedAt = 0,
  });

  final String id;

  /// The title's page, so the download can be grouped with its siblings and
  /// opened in the app.
  final String contentUrl;

  final String provider;
  final String title;

  /// Where the bytes came from. Kept for retrying, and for nothing else — it
  /// is never used to decide what kind of download this is (see [kind]) and
  /// never used to build a local path.
  final String sourceUrl;

  final DownloadKind kind;

  /// The artefact, relative to the app's documents directory:
  /// `downloads/<id>/index.m3u8`, `downloads/<id>/video.mkv`, or for a manga
  /// chapter the folder `downloads/<id>`.
  ///
  /// Never absolute. See [DownloadLayout] for the whole reason this type
  /// exists.
  final String relativePath;

  final String? thumbnailUrl;

  /// The cached poster, relative like everything else here.
  final String? thumbnailRelativePath;

  /// What the mirror needs to serve these bytes. A sibling host's headers are
  /// a 403, so they travel with the item rather than being taken from whatever
  /// happens to be playing.
  final Map<String, String> headers;

  final DownloadStatus status;

  /// What [completedUnits] and [totalUnits] are counting.
  final DownloadUnit unit;

  final int completedUnits;
  final int totalUnits;

  /// Real bytes on disk, always, whatever [unit] is.
  ///
  /// Separate from the counters because an HLS download counts segments while
  /// it runs and has a byte size only when it is done — one pair of fields
  /// could not carry both, and the list ended up printing "648 B" for a 214 MB
  /// episode.
  final int sizeBytes;

  final int createdAt;

  /// When the row last changed, for sorting and for the integrity sweep.
  final int updatedAt;

  final bool isSerial;
  final int? episodeNumber;
  final String? episodeLabel;

  /// Manga only: the pages to fetch. Empty until resolved.
  final List<String> pageUrls;
  final String? chapterRef;
  final int? chapterIndex;

  /// Why it stopped, when it did.
  final DownloadFailureKind? failure;

  /// The engine's own words, kept so a bug report can quote them. Never the
  /// whole message shown to a viewer unless the kind is `unknown`.
  final String failureDetail;

  /// Automatic retries already spent. Reset by an explicit retry, so a viewer
  /// pressing the button is never told the budget is gone.
  final int attempts;

  bool get isManga => kind == DownloadKind.manga;
  bool get isHls => kind == DownloadKind.hls;

  /// A folder rather than a file — a manga chapter.
  bool get artefactIsDirectory => kind == DownloadKind.manga;

  /// 0..1, or null while nothing is known about the size.
  ///
  /// Null rather than 0 so a bar can be indeterminate instead of pretending to
  /// be at the very start of a transfer whose length the server never stated.
  double? get progress {
    if (status == DownloadStatus.completed) return 1;
    if (totalUnits <= 0) return null;
    return (completedUnits / totalUnits).clamp(0.0, 1.0);
  }

  /// The poster to draw: the cached copy when there is one, else the remote.
  ///
  /// Returns the RELATIVE path for the local copy; the widget layer resolves
  /// it through the repository, for the same reason nothing else here is
  /// absolute.
  String? get remoteThumbnail => thumbnailUrl;

  /// Whether this download can be opened right now.
  bool get isPlayable => status.isPlayable;

  /// Whether an automatic retry is still allowed.
  ///
  /// Three, then it stops and waits to be asked. A link that has expired fails
  /// identically every time, and a queue that retries it forever is a queue
  /// that never gets to the next episode.
  static const int maxAutoAttempts = 3;

  bool get canAutoRetry =>
      status == DownloadStatus.failed &&
      (failure?.retryable ?? true) &&
      attempts < maxAutoAttempts;

  /// The key episodes of one title group under.
  String get groupKey => contentUrl.isEmpty ? id : contentUrl;

  DownloadItem copyWith({
    String? relativePath,
    String? thumbnailRelativePath,
    Map<String, String>? headers,
    DownloadStatus? status,
    DownloadKind? kind,
    DownloadUnit? unit,
    int? completedUnits,
    int? totalUnits,
    int? sizeBytes,
    List<String>? pageUrls,
    Object? failure = _unset,
    String? failureDetail,
    int? attempts,
    int? updatedAt,
  }) =>
      DownloadItem(
        id: id,
        contentUrl: contentUrl,
        provider: provider,
        title: title,
        sourceUrl: sourceUrl,
        kind: kind ?? this.kind,
        relativePath: relativePath ?? this.relativePath,
        thumbnailUrl: thumbnailUrl,
        thumbnailRelativePath:
            thumbnailRelativePath ?? this.thumbnailRelativePath,
        headers: headers ?? this.headers,
        status: status ?? this.status,
        unit: unit ?? this.unit,
        completedUnits: completedUnits ?? this.completedUnits,
        totalUnits: totalUnits ?? this.totalUnits,
        sizeBytes: sizeBytes ?? this.sizeBytes,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        isSerial: isSerial,
        episodeNumber: episodeNumber,
        episodeLabel: episodeLabel,
        pageUrls: pageUrls ?? this.pageUrls,
        chapterRef: chapterRef,
        chapterIndex: chapterIndex,
        // `null` is a real value here — clearing the failure is what a retry
        // does — so an unset sentinel is the only way to tell "leave it" from
        // "remove it".
        failure: identical(failure, _unset)
            ? this.failure
            : failure as DownloadFailureKind?,
        failureDetail: failureDetail ?? this.failureDetail,
        attempts: attempts ?? this.attempts,
      );

  static const Object _unset = Object();
}
