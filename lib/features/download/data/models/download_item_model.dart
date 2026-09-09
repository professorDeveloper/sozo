import 'package:soplay/features/download/domain/download_layout.dart';
import 'package:soplay/features/download/domain/entities/download_failure.dart';
import 'package:soplay/features/download/domain/entities/download_item.dart';
import 'package:soplay/features/download/domain/entities/download_kind.dart';
import 'package:soplay/features/download/domain/entities/download_status.dart';

/// [DownloadItem] on the wire, and the migration off the old shape.
///
/// ## What changed, and why every install has to survive it
///
/// The previous row stored an ABSOLUTE `localPath`, a `status` as an enum
/// INDEX, a `kind` of `'video'`/`'manga'` with HLS re-sniffed from the url,
/// and one pair of counters that meant bytes for a direct download and
/// segments for a playlist. Every one of those is fixed here, and every one of
/// them exists on somebody's phone right now — so [fromJson] reads both
/// shapes and [toJson] only ever writes the new one.
abstract final class DownloadItemModel {
  static Map<String, dynamic> toJson(DownloadItem item) => {
        'v': 2,
        'id': item.id,
        'contentUrl': item.contentUrl,
        'provider': item.provider,
        'title': item.title,
        'sourceUrl': item.sourceUrl,
        'kind': item.kind.id,
        'relativePath': item.relativePath,
        'thumbnailUrl': item.thumbnailUrl,
        'thumbnailRelativePath': item.thumbnailRelativePath,
        'headers': item.headers,
        'status': item.status.id,
        'unit': item.unit.id,
        'completedUnits': item.completedUnits,
        'totalUnits': item.totalUnits,
        'sizeBytes': item.sizeBytes,
        'createdAt': item.createdAt,
        'updatedAt': item.updatedAt,
        'isSerial': item.isSerial,
        'episodeNumber': item.episodeNumber,
        'episodeLabel': item.episodeLabel,
        'pageUrls': item.pageUrls,
        'chapterRef': item.chapterRef,
        'chapterIndex': item.chapterIndex,
        'failure': item.failure?.id,
        'failureDetail': item.failureDetail,
        'attempts': item.attempts,
      };

  static DownloadItem fromJson(Map<String, dynamic> json) {
    final id = _string(json['id']);
    final legacy = json['v'] == null;

    final sourceUrl =
        _string(json['sourceUrl']).ifEmpty(() => _string(json['videoUrl']));

    final kind = legacy
        ? DownloadKind.fromLegacy(_stringOrNull(json['kind']), sourceUrl)
        : DownloadKind.fromId(_stringOrNull(json['kind']));

    // The whole point of the migration. An absolute path is stripped back to
    // the part that does not depend on the device; anything unrecognisable
    // falls back to the deterministic layout, and the integrity sweep repairs
    // the extension by looking in the folder.
    final relativePath = DownloadLayout.relativeFromLegacy(
          _stringOrNull(json['relativePath']) ??
              _stringOrNull(json['localPath']),
        ) ??
        DownloadLayout.artefactFor(
          id,
          kind: kind,
          extension: DownloadLayout.videoExtensionFor(sourceUrl),
        );

    final thumbnailRelative = DownloadLayout.relativeFromLegacy(
      _stringOrNull(json['thumbnailRelativePath']) ??
          _stringOrNull(json['localThumbnailPath']),
    );

    final status = legacy
        ? DownloadStatus.fromLegacyIndex(_int(json['status']))
        : DownloadStatus.fromId(_stringOrNull(json['status']));

    final unit = legacy
        ? DownloadUnit.forKind(kind)
        : DownloadUnit.fromId(_stringOrNull(json['unit']));

    // Legacy rows overloaded `totalBytes`, and the overload flipped MEANING at
    // the finish line: for a playlist or a chapter it held a part COUNT while
    // the transfer ran, and the old service rewrote it to BYTES on completion.
    // Reading it as one or the other unconditionally is how the list came to
    // print "648 B" for a 214 MB episode.
    //
    // So: a finished multi-part row's number is bytes and its part count is
    // simply unknown — the sweep re-measures the size from disk either way.
    final legacyTotal = _int(json['totalBytes']);
    final legacyDone = _int(json['downloadedBytes']);
    final legacyMultiPartDone =
        legacy && kind.isMultiPart && status == DownloadStatus.completed;

    return DownloadItem(
      id: id,
      contentUrl: _string(json['contentUrl']),
      provider: _string(json['provider']),
      title: _string(json['title']),
      sourceUrl: sourceUrl,
      kind: kind,
      relativePath: relativePath,
      thumbnailUrl: _stringOrNull(json['thumbnailUrl']) ??
          _stringOrNull(json['thumbnail']),
      thumbnailRelativePath: thumbnailRelative,
      headers: _headers(json['headers']),
      status: status,
      unit: unit,
      completedUnits: legacy
          ? (legacyMultiPartDone ? 0 : legacyDone)
          : _int(json['completedUnits']),
      totalUnits: legacy
          ? (legacyMultiPartDone ? 0 : legacyTotal)
          : _int(json['totalUnits']),
      sizeBytes: legacy
          ? (unit == DownloadUnit.bytes || legacyMultiPartDone ? legacyTotal : 0)
          : _int(json['sizeBytes']),
      createdAt: _int(json['createdAt']),
      updatedAt: _int(json['updatedAt']),
      isSerial: json['isSerial'] == true,
      episodeNumber: _intOrNull(json['episodeNumber']),
      episodeLabel: _stringOrNull(json['episodeLabel']),
      pageUrls: (json['pageUrls'] as List?)
              ?.map((e) => e.toString())
              .where((e) => e.isNotEmpty)
              .toList() ??
          const [],
      chapterRef: _stringOrNull(json['chapterRef']),
      chapterIndex: _intOrNull(json['chapterIndex']),
      failure: json['failure'] == null
          ? null
          : DownloadFailureKind.fromId(_stringOrNull(json['failure'])),
      failureDetail: _string(json['failureDetail']),
      attempts: _int(json['attempts']),
    );
  }

  static Map<String, String> _headers(Object? raw) {
    if (raw is! Map) return const {};
    return {
      for (final e in raw.entries)
        if (e.value != null) e.key.toString(): e.value.toString(),
    };
  }

  static String _string(Object? raw) => raw is String ? raw : '';

  static String? _stringOrNull(Object? raw) {
    final value = raw is String ? raw.trim() : null;
    return (value == null || value.isEmpty) ? null : value;
  }

  static int _int(Object? raw) => switch (raw) {
        int value => value,
        num value => value.toInt(),
        String value => int.tryParse(value) ?? 0,
        _ => 0,
      };

  static int? _intOrNull(Object? raw) => switch (raw) {
        int value => value,
        num value => value.toInt(),
        String value => int.tryParse(value),
        _ => null,
      };
}

extension on String {
  String ifEmpty(String Function() other) => isEmpty ? other() : this;
}
