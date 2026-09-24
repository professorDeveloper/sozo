import 'package:dio/dio.dart';

/// One history row on the wire.
///
/// The field names are the server's contract and are shared verbatim with the
/// Android TV client. Renaming one here does not break a build — it silently
/// splits the same episode into two rows that never reconcile, so treat this
/// shape as fixed unless the server and the TV move with it.
class HistorySyncItem {
  const HistorySyncItem({
    required this.provider,
    this.key,
    this.contentUrl,
    this.contentId,
    this.title,
    this.thumbnail,
    this.isSerial = false,
    this.episodeIndex,
    this.episodeNumber,
    this.episodeLabel,
    this.positionMs = 0,
    this.durationMs = 0,
    this.extra,
    this.watchedAt,
    this.deletedAt,
  });

  final String provider;

  /// Server-assigned identity. Echoed back as-is; the client never invents one
  /// except for a tombstone, which has no row left to read it from.
  final String? key;
  final String? contentUrl;
  final String? contentId;
  final String? title;
  final String? thumbnail;
  final bool isSerial;
  final int? episodeIndex;
  final int? episodeNumber;
  final String? episodeLabel;
  final int positionMs;
  final int durationMs;

  /// Whatever the originating platform stores beyond the shared shape. The TV
  /// puts its whole Room row here; this client passes it through untouched so a
  /// round trip through the phone does not strip a TV row of what makes it
  /// playable.
  final Map<String, dynamic>? extra;

  final String? watchedAt;
  final String? deletedAt;

  bool get isDeleted => deletedAt != null;

  /// A row from another platform. This app's own rows carry at most a media
  /// type in [extra]; the TV puts its whole Room row there.
  bool get isForeign =>
      extra != null && extra!.keys.any((k) => k != 'mediaType');

  String? get mediaType {
    final t = extra?['mediaType'];
    return t is String && t.isNotEmpty ? t : null;
  }

  Map<String, dynamic> toJson() => {
    'provider': provider,
    if (key != null) 'key': key,
    if (contentUrl != null) 'contentUrl': contentUrl,
    if (contentId != null) 'contentId': contentId,
    if (title != null) 'title': title,
    if (thumbnail != null) 'thumbnail': thumbnail,
    'isSerial': isSerial,
    if (episodeIndex != null) 'episodeIndex': episodeIndex,
    if (episodeNumber != null) 'episodeNumber': episodeNumber,
    if (episodeLabel != null) 'episodeLabel': episodeLabel,
    'positionMs': positionMs,
    'durationMs': durationMs,
    if (extra != null) 'extra': extra,
    if (watchedAt != null) 'watchedAt': watchedAt,
    if (deletedAt != null) 'deletedAt': deletedAt,
  };

  factory HistorySyncItem.fromJson(Map<String, dynamic> json) =>
      HistorySyncItem(
        provider: json['provider'] as String? ?? '',
        key: json['key'] as String?,
        contentUrl: json['contentUrl'] as String?,
        contentId: json['contentId'] as String?,
        title: json['title'] as String?,
        thumbnail: json['thumbnail'] as String?,
        isSerial: json['isSerial'] as bool? ?? false,
        episodeIndex: (json['episodeIndex'] as num?)?.toInt(),
        episodeNumber: (json['episodeNumber'] as num?)?.toInt(),
        episodeLabel: json['episodeLabel'] as String?,
        positionMs: (json['positionMs'] as num?)?.toInt() ?? 0,
        durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
        extra: (json['extra'] as Map?)?.cast<String, dynamic>(),
        watchedAt: json['watchedAt'] as String?,
        deletedAt: json['deletedAt'] as String?,
      );
}

class HistorySyncResult {
  const HistorySyncResult({required this.items, this.serverTime});

  final List<HistorySyncItem> items;

  /// The server's clock. Becomes the next request's `since`, so a phone with a
  /// wrong clock still pages correctly.
  final String? serverTime;
}

/// Transport for `/auth/history/sync`.
///
/// Uses the app's authenticated [Dio], so the bearer token and its silent
/// refresh come from the existing interceptor rather than being re-implemented.
class HistorySyncRemoteDataSource {
  const HistorySyncRemoteDataSource({required this.dio});

  final Dio dio;

  /// Pushes [items] and returns everything changed elsewhere since [since].
  ///
  /// An empty [items] is an ordinary pull, not a special case: a phone with no
  /// local changes still wants the TV's progress.
  Future<HistorySyncResult> sync({
    required List<HistorySyncItem> items,
    String? since,
  }) async {
    final response = await dio.post(
      '/auth/history/sync',
      data: {
        'items': items.map((e) => e.toJson()).toList(growable: false),
        'since': ?since,
      },
    );

    final data = response.data;
    final raw = data is Map ? data['items'] : null;
    return HistorySyncResult(
      items: raw is List
          ? raw
                .whereType<Map>()
                .map(
                  (e) => HistorySyncItem.fromJson(e.cast<String, dynamic>()),
                )
                .toList(growable: false)
          : const [],
      serverTime: data is Map ? data['serverTime'] as String? : null,
    );
  }
}
