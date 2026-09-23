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

  Map<String, dynamic> toJson() => {
    'contentUrl': contentUrl,
    'provider': provider,
    'title': title,
    'thumbnail': thumbnail,
    if (year != null) 'year': year,
    'lastEpisodeCount': lastEpisodeCount,
    'addedAt': addedAt,
    if (lastCheckedAt != null) 'lastCheckedAt': lastCheckedAt,
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
  );
}
