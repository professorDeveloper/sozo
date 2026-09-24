class HistoryItem {
  final String contentUrl;
  final String provider;
  final String title;
  final String? thumbnail;
  final bool isSerial;
  final int? episodeIndex;
  final int? episodeNumber;
  final String? episodeLabel;
  final int positionMs;
  final int durationMs;
  final int watchedAt;

  /// 'manga' or 'novel' for reader rows; null means video. Synced so the
  /// server can tell reading from watching in friends' activity.
  final String? mediaType;

  const HistoryItem({
    required this.contentUrl,
    required this.provider,
    required this.title,
    this.thumbnail,
    this.isSerial = false,
    this.episodeIndex,
    this.episodeNumber,
    this.episodeLabel,
    this.positionMs = 0,
    this.durationMs = 0,
    required this.watchedAt,
    this.mediaType,
  });

  double get progress =>
      durationMs > 0 ? (positionMs / durationMs).clamp(0.0, 1.0) : 0.0;

  String get storageKey => buildStorageKey(
    contentUrl: contentUrl,
    isSerial: isSerial,
    episodeIndex: episodeIndex,
    episodeNumber: episodeNumber,
  );

  static String buildStorageKey({
    required String contentUrl,
    bool isSerial = false,
    int? episodeIndex,
    int? episodeNumber,
  }) {
    if (!isSerial) return contentUrl;
    final episodeKey = episodeNumber ?? episodeIndex;
    if (episodeKey == null) return contentUrl;
    return '$contentUrl::episode::$episodeKey';
  }

  HistoryItem copyWith({
    int? episodeIndex,
    int? episodeNumber,
    String? episodeLabel,
    int? positionMs,
    int? durationMs,
    int? watchedAt,
  }) => HistoryItem(
    contentUrl: contentUrl,
    provider: provider,
    title: title,
    thumbnail: thumbnail,
    isSerial: isSerial,
    episodeIndex: episodeIndex ?? this.episodeIndex,
    episodeNumber: episodeNumber ?? this.episodeNumber,
    episodeLabel: episodeLabel ?? this.episodeLabel,
    positionMs: positionMs ?? this.positionMs,
    durationMs: durationMs ?? this.durationMs,
    watchedAt: watchedAt ?? this.watchedAt,
    mediaType: mediaType,
  );

  Map<String, dynamic> toJson() => {
    'contentUrl': contentUrl,
    'provider': provider,
    'title': title,
    'thumbnail': thumbnail,
    'isSerial': isSerial,
    'episodeIndex': episodeIndex,
    'episodeNumber': episodeNumber,
    'episodeLabel': episodeLabel,
    'positionMs': positionMs,
    'durationMs': durationMs,
    'watchedAt': watchedAt,
    if (mediaType != null) 'mediaType': mediaType,
  };

  factory HistoryItem.fromJson(Map<String, dynamic> json) => HistoryItem(
    contentUrl: json['contentUrl'] as String? ?? '',
    provider: json['provider'] as String? ?? '',
    title: json['title'] as String? ?? '',
    thumbnail: json['thumbnail'] as String?,
    isSerial: json['isSerial'] as bool? ?? false,
    episodeIndex: json['episodeIndex'] as int?,
    episodeNumber: json['episodeNumber'] as int?,
    episodeLabel: json['episodeLabel'] as String?,
    positionMs: json['positionMs'] as int? ?? 0,
    durationMs: json['durationMs'] as int? ?? 0,
    watchedAt: json['watchedAt'] as int? ?? 0,
    mediaType: json['mediaType'] as String?,
  );
}
