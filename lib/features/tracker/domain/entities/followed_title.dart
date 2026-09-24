/// A serial the user follows to get notified when new episodes appear.
class FollowedTitle {
  const FollowedTitle({
    required this.contentUrl,
    required this.provider,
    required this.title,
    required this.thumbnail,
    this.year,
    this.lastEpisodeCount = 0,
    this.addedAt = 0,
    this.lastCheckedAt,
    this.autoDownload = false,
    this.autoDownloadFrom = 0,
  });

  final String contentUrl;
  final String provider;
  final String title;
  final String thumbnail;
  final int? year;

  /// Episode count at the last successful check. 0 = not yet checked (a first
  /// check only seeds this, it never notifies).
  final int lastEpisodeCount;
  final int addedAt;
  final int? lastCheckedAt;

  /// Download new episodes by themselves (see AutoDownloadService).
  final bool autoDownload;

  /// Only episodes above this number are downloaded automatically: turning
  /// the switch on for a long-running show must not fetch its back catalogue.
  /// 0 until the title has been checked once.
  final int autoDownloadFrom;

  FollowedTitle copyWith({bool? autoDownload, int? autoDownloadFrom}) =>
      FollowedTitle(
        contentUrl: contentUrl,
        provider: provider,
        title: title,
        thumbnail: thumbnail,
        year: year,
        lastEpisodeCount: lastEpisodeCount,
        addedAt: addedAt,
        lastCheckedAt: lastCheckedAt,
        autoDownload: autoDownload ?? this.autoDownload,
        autoDownloadFrom: autoDownloadFrom ?? this.autoDownloadFrom,
      );

  Map<String, dynamic> toJson() => {
    'contentUrl': contentUrl,
    'provider': provider,
    'title': title,
    'thumbnail': thumbnail,
    if (year != null) 'year': year,
    'lastEpisodeCount': lastEpisodeCount,
    'addedAt': addedAt,
    if (lastCheckedAt != null) 'lastCheckedAt': lastCheckedAt,
    if (autoDownload) 'autoDownload': true,
    if (autoDownloadFrom > 0) 'autoDownloadFrom': autoDownloadFrom,
  };

  factory FollowedTitle.fromJson(Map<String, dynamic> j) => FollowedTitle(
    contentUrl: (j['contentUrl'] ?? '').toString(),
    provider: (j['provider'] ?? '').toString(),
    title: (j['title'] ?? '').toString(),
    thumbnail: (j['thumbnail'] ?? '').toString(),
    year: (j['year'] as num?)?.toInt(),
    lastEpisodeCount: (j['lastEpisodeCount'] as num?)?.toInt() ?? 0,
    addedAt: (j['addedAt'] as num?)?.toInt() ?? 0,
    lastCheckedAt: (j['lastCheckedAt'] as num?)?.toInt(),
    autoDownload: j['autoDownload'] == true,
    autoDownloadFrom: (j['autoDownloadFrom'] as num?)?.toInt() ?? 0,
  );
}
