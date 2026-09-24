/// A serial the user follows to get notified when new episodes appear.
///
/// Stored per profile as JSON, and the same shape (minus the device-only
/// fields) travels to `/follows`. Every field added after the first version is
/// optional in [FollowedTitle.fromJson], so a list written by an older build
/// still reads.
class FollowedTitle {
  const FollowedTitle({
    required this.contentUrl,
    required this.provider,
    required this.title,
    required this.thumbnail,
    this.year,
    this.lastEpisodeCount = 0,
    this.lastEpisodeLabel,
    this.addedAt = 0,
    this.updatedAt = 0,
    this.lastCheckedAt,
    this.autoDownload = false,
    this.autoDownloadFrom = 0,
    this.mode = 'video',
    this.notify = true,
    this.anilistId,
    this.malId,
    this.tmdbId,
    this.tmdbKind,
    this.nextAiringAt,
    this.nextAiringEpisode,
  });

  final String contentUrl;
  final String provider;
  final String title;
  final String thumbnail;
  final int? year;

  /// Episode count at the last successful check. 0 = not yet checked (a first
  /// check only seeds this, it never notifies).
  final int lastEpisodeCount;
  final String? lastEpisodeLabel;
  final int addedAt;

  /// Last change to anything the server keeps, for its merge.
  final int updatedAt;
  final int? lastCheckedAt;

  /// Download new episodes by themselves (see AutoDownloadService).
  final bool autoDownload;

  /// Only episodes above this number are downloaded automatically: turning
  /// the switch on for a long-running show must not fetch its back catalogue.
  /// 0 until the title has been checked once.
  final int autoDownloadFrom;

  /// `video`, `manga` or `novel` — decides "episode" or "chapter" in copy.
  final String mode;

  /// Muted titles are still followed and still counted, just not announced.
  final bool notify;

  final int? anilistId;
  final int? malId;
  final int? tmdbId;

  /// `tv` or `movie`, as TMDB files it.
  final String? tmdbKind;

  /// Milliseconds since epoch.
  final int? nextAiringAt;
  final int? nextAiringEpisode;

  bool get isReading => mode == 'manga' || mode == 'novel';

  String get key => keyOf(provider, contentUrl);

  static String keyOf(String provider, String contentUrl) =>
      '${provider.trim()}|${contentUrl.trim()}';

  FollowedTitle copyWith({
    String? title,
    String? thumbnail,
    int? lastEpisodeCount,
    String? lastEpisodeLabel,
    int? updatedAt,
    int? lastCheckedAt,
    bool? autoDownload,
    int? autoDownloadFrom,
    String? mode,
    bool? notify,
    int? anilistId,
    int? malId,
    int? tmdbId,
    String? tmdbKind,
    int? nextAiringAt,
    int? nextAiringEpisode,
  }) => FollowedTitle(
    contentUrl: contentUrl,
    provider: provider,
    title: title ?? this.title,
    thumbnail: thumbnail ?? this.thumbnail,
    year: year,
    lastEpisodeCount: lastEpisodeCount ?? this.lastEpisodeCount,
    lastEpisodeLabel: lastEpisodeLabel ?? this.lastEpisodeLabel,
    addedAt: addedAt,
    updatedAt: updatedAt ?? this.updatedAt,
    lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
    autoDownload: autoDownload ?? this.autoDownload,
    autoDownloadFrom: autoDownloadFrom ?? this.autoDownloadFrom,
    mode: mode ?? this.mode,
    notify: notify ?? this.notify,
    anilistId: anilistId ?? this.anilistId,
    malId: malId ?? this.malId,
    tmdbId: tmdbId ?? this.tmdbId,
    tmdbKind: tmdbKind ?? this.tmdbKind,
    nextAiringAt: nextAiringAt ?? this.nextAiringAt,
    nextAiringEpisode: nextAiringEpisode ?? this.nextAiringEpisode,
  );

  /// The local record. Defaults are left out so an old reader sees the shape
  /// it always saw.
  Map<String, dynamic> toJson() => {
    'contentUrl': contentUrl,
    'provider': provider,
    'title': title,
    'thumbnail': thumbnail,
    if (year != null) 'year': year,
    'lastEpisodeCount': lastEpisodeCount,
    if (lastEpisodeLabel != null) 'lastEpisodeLabel': lastEpisodeLabel,
    'addedAt': addedAt,
    if (updatedAt > 0) 'updatedAt': updatedAt,
    if (lastCheckedAt != null) 'lastCheckedAt': lastCheckedAt,
    if (autoDownload) 'autoDownload': true,
    if (autoDownloadFrom > 0) 'autoDownloadFrom': autoDownloadFrom,
    if (mode != 'video') 'mode': mode,
    if (!notify) 'notify': false,
    if (anilistId != null) 'anilistId': anilistId,
    if (malId != null) 'malId': malId,
    if (tmdbId != null) 'tmdbId': tmdbId,
    if (tmdbKind != null) 'tmdbKind': tmdbKind,
    if (nextAiringAt != null) 'nextAiringAt': nextAiringAt,
    if (nextAiringEpisode != null) 'nextAiringEpisode': nextAiringEpisode,
  };

  /// The `/follows` item. Device-only fields (auto-download, last check) stay
  /// on the device, and `knownCount` is the server's own to fill.
  Map<String, dynamic> toRemote() => {
    'provider': provider,
    'contentUrl': contentUrl,
    'title': title,
    'thumbnail': thumbnail.startsWith('http') ? thumbnail : null,
    'year': year,
    'mode': mode,
    'lastEpisodeCount': lastEpisodeCount,
    'lastEpisodeLabel': lastEpisodeLabel,
    'notify': notify,
    'anilistId': anilistId,
    'malId': malId,
    'tmdbId': tmdbId,
    'tmdbKind': tmdbKind,
    'addedAt': _iso(addedAt),
    'updatedAt': _iso(updatedAt > 0 ? updatedAt : addedAt),
    'nextAiringAt': _iso(nextAiringAt),
    'nextAiringEpisode': nextAiringEpisode,
  };

  static String? _iso(int? ms) => ms == null || ms <= 0
      ? null
      : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String();

  factory FollowedTitle.fromJson(Map<String, dynamic> j) {
    final mode = (j['mode'] ?? '').toString();
    return FollowedTitle(
      contentUrl: (j['contentUrl'] ?? '').toString(),
      provider: (j['provider'] ?? '').toString(),
      title: (j['title'] ?? '').toString(),
      thumbnail: (j['thumbnail'] ?? '').toString(),
      year: _int(j['year']),
      lastEpisodeCount: _int(j['lastEpisodeCount']) ?? 0,
      lastEpisodeLabel: _string(j['lastEpisodeLabel']),
      addedAt: _time(j['addedAt']) ?? 0,
      updatedAt: _time(j['updatedAt']) ?? 0,
      lastCheckedAt: _time(j['lastCheckedAt']),
      autoDownload: j['autoDownload'] == true,
      autoDownloadFrom: _int(j['autoDownloadFrom']) ?? 0,
      mode: const {'video', 'manga', 'novel'}.contains(mode) ? mode : 'video',
      notify: j['notify'] != false,
      anilistId: _int(j['anilistId']),
      malId: _int(j['malId']),
      tmdbId: _int(j['tmdbId']),
      tmdbKind: _string(j['tmdbKind']),
      nextAiringAt: _time(j['nextAiringAt']),
      nextAiringEpisode: _int(j['nextAiringEpisode']),
    );
  }

  static int? _int(Object? v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  static String? _string(Object? v) {
    if (v == null) return null;
    final s = v.toString();
    return s.isEmpty ? null : s;
  }

  /// Epoch milliseconds, or an ISO string from the server.
  static int? _time(Object? v) {
    if (v is num) return v.toInt();
    if (v is String && v.isNotEmpty) {
      return int.tryParse(v) ?? DateTime.tryParse(v)?.millisecondsSinceEpoch;
    }
    return null;
  }
}
