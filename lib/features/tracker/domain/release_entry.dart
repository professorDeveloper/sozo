/// One followed title that grew: the row behind the New releases feed, the
/// Home rail and the NEW badges.
///
/// One entry per title rather than per episode. Three episodes landing while
/// the phone was in a drawer are one piece of news — "EP 10–12" — not three
/// cards that each lead to the same list.
class ReleaseEntry {
  const ReleaseEntry({
    required this.provider,
    required this.contentUrl,
    required this.title,
    required this.thumbnail,
    required this.mode,
    required this.episode,
    required this.fromEpisode,
    required this.at,
    this.label,
    this.seen = false,
  });

  final String provider;
  final String contentUrl;
  final String title;
  final String thumbnail;

  /// `video`, `manga` or `novel`.
  final String mode;

  /// The newest episode or chapter number.
  final int episode;

  /// The first one not yet seen; equal to [episode] for a single release.
  final int fromEpisode;
  final String? label;

  /// Milliseconds since epoch.
  final int at;
  final bool seen;

  String get key => '${provider.trim()}|${contentUrl.trim()}';
  bool get isReading => mode == 'manga' || mode == 'novel';
  int get newCount => episode - fromEpisode + 1;
  DateTime get time => DateTime.fromMillisecondsSinceEpoch(at);

  ReleaseEntry copyWith({
    String? title,
    String? thumbnail,
    int? episode,
    int? fromEpisode,
    String? label,
    int? at,
    bool? seen,
  }) => ReleaseEntry(
    provider: provider,
    contentUrl: contentUrl,
    title: title ?? this.title,
    thumbnail: thumbnail ?? this.thumbnail,
    mode: mode,
    episode: episode ?? this.episode,
    fromEpisode: fromEpisode ?? this.fromEpisode,
    label: label ?? this.label,
    at: at ?? this.at,
    seen: seen ?? this.seen,
  );

  /// Folds a newer release of the same title into this one.
  ///
  /// An episode already known is ignored — a push and the device's own check
  /// both report the same episode, and the second must not bump it back to
  /// the top. Unseen releases keep their starting point, so "10–12" grows to
  /// "10–13"; a seen one starts over at the first episode after it.
  ReleaseEntry absorb(ReleaseEntry next) {
    if (next.episode <= episode) {
      return thumbnail.isEmpty && next.thumbnail.isNotEmpty
          ? copyWith(thumbnail: next.thumbnail)
          : this;
    }
    final start = seen
        ? (next.fromEpisode > episode ? next.fromEpisode : episode + 1)
        : fromEpisode;
    return next.copyWith(
      fromEpisode: start,
      title: next.title.isEmpty ? title : next.title,
      thumbnail: next.thumbnail.isEmpty ? thumbnail : next.thumbnail,
      seen: false,
    );
  }

  Map<String, dynamic> toJson() => {
    'provider': provider,
    'contentUrl': contentUrl,
    'title': title,
    'thumbnail': thumbnail,
    'mode': mode,
    'episode': episode,
    'from': fromEpisode,
    if (label != null) 'label': label,
    'at': at,
    if (seen) 'seen': true,
  };

  static ReleaseEntry? fromJson(Map<String, dynamic> j) {
    final url = (j['contentUrl'] ?? '').toString();
    final episode = (j['episode'] as num?)?.toInt() ?? 0;
    if (url.isEmpty || episode <= 0) return null;
    final from = (j['from'] as num?)?.toInt() ?? episode;
    return ReleaseEntry(
      provider: (j['provider'] ?? '').toString(),
      contentUrl: url,
      title: (j['title'] ?? '').toString(),
      thumbnail: (j['thumbnail'] ?? '').toString(),
      mode: (j['mode'] ?? 'video').toString(),
      episode: episode,
      fromEpisode: from.clamp(1, episode),
      label: j['label']?.toString(),
      at: (j['at'] as num?)?.toInt() ?? 0,
      seen: j['seen'] == true,
    );
  }
}

enum ReleaseBucket { today, yesterday, thisWeek, earlier }

/// The feed's sections, newest first, empty ones left out.
///
/// Calendar days in local time, not 24-hour windows: something from 23:50
/// last night is "Yesterday" at 00:10, which is how people say it.
List<(ReleaseBucket, List<ReleaseEntry>)> groupReleases(
  Iterable<ReleaseEntry> entries,
  DateTime now,
) {
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final weekStart = today.subtract(const Duration(days: 6));

  ReleaseBucket bucketOf(ReleaseEntry e) {
    final t = e.time;
    final day = DateTime(t.year, t.month, t.day);
    if (!day.isBefore(today)) return ReleaseBucket.today;
    if (!day.isBefore(yesterday)) return ReleaseBucket.yesterday;
    if (!day.isBefore(weekStart)) return ReleaseBucket.thisWeek;
    return ReleaseBucket.earlier;
  }

  final sorted = entries.toList()..sort((a, b) => b.at.compareTo(a.at));
  final out = <ReleaseBucket, List<ReleaseEntry>>{};
  for (final e in sorted) {
    out.putIfAbsent(bucketOf(e), () => []).add(e);
  }
  return [
    for (final b in ReleaseBucket.values)
      if (out[b] != null) (b, out[b]!),
  ];
}
