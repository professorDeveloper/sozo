/// The list statuses MAL accepts on a write.
///
/// Deliberately plain strings — MAL identifies them by the wire value, and a
/// second representation would only need mapping back at every edge. Note there
/// is no "rewatching" member: MAL expresses that as a FLAG on a completed entry
/// (`is_rewatching`), which is read but never sent.
class MalStatus {
  const MalStatus._();

  static const String watching = 'watching';
  static const String completed = 'completed';
  static const String onHold = 'on_hold';
  static const String dropped = 'dropped';
  static const String planToWatch = 'plan_to_watch';
}

/// The signed-in MyAnimeList account.
class MalViewer {
  const MalViewer({required this.id, required this.name, this.avatarUrl});

  final int id;
  final String name;
  final String? avatarUrl;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'avatarUrl': avatarUrl,
      };

  factory MalViewer.fromJson(Map<String, dynamic> j) => MalViewer(
        id: (j['id'] as num?)?.toInt() ?? 0,
        name: (j['name'] ?? '').toString(),
        avatarUrl: j['avatarUrl'] as String?,
      );
}

/// Where the account currently stands on one anime.
///
/// [totalEpisodes] comes from the anime itself rather than from the list entry,
/// and is what lets the tracker decide that an episode finishes a show.
class MalEntryState {
  const MalEntryState({
    required this.watchedEpisodes,
    this.status,
    this.totalEpisodes,
    this.isRewatching = false,
    this.score,
  });

  /// `my_list_status.num_episodes_watched`.
  final int watchedEpisodes;

  /// `my_list_status.score`, out of 10. Null or 0 when unscored.
  final int? score;

  /// One of [MalStatus]. Null when the anime is not on the list at all.
  final String? status;

  final int? totalEpisodes;

  /// MAL models a rewatch as a FLAG on a completed entry, not as a status of
  /// its own — so it is read here and never written back. Sending a status
  /// during a rewatch would knock the entry out of `completed`.
  final bool isRewatching;

  /// True when the entry is not on the list yet.
  bool get isNew => status == null;

  factory MalEntryState.fromAnime(Map<String, dynamic> anime) {
    final listStatus =
        (anime['my_list_status'] as Map?)?.cast<String, dynamic>();
    final total = (anime['num_episodes'] as num?)?.toInt();
    return MalEntryState(
      watchedEpisodes:
          (listStatus?['num_episodes_watched'] as num?)?.toInt() ?? 0,
      status: listStatus?['status'] as String?,
      totalEpisodes: (total != null && total > 0) ? total : null,
      isRewatching: listStatus?['is_rewatching'] == true,
      score: (listStatus?['score'] as num?)?.toInt(),
    );
  }
}

/// One search hit, reduced to what a match needs.
class MalAnime {
  const MalAnime({
    required this.id,
    required this.title,
    this.alternativeTitles = const [],
    this.picture,
    this.episodes,
  });

  final int id;
  final String title;
  final List<String> alternativeTitles;
  final String? picture;
  final int? episodes;

  /// Every name worth matching against a source title, best guess first and no
  /// blanks or duplicates.
  List<String> get searchTitles {
    final out = <String>[];
    for (final t in [title, ...alternativeTitles]) {
      final v = t.trim();
      if (v.isNotEmpty && !out.contains(v)) out.add(v);
    }
    return out;
  }

  factory MalAnime.fromJson(Map<String, dynamic> j) {
    final alt = (j['alternative_titles'] as Map?)?.cast<String, dynamic>();
    final synonyms = (alt?['synonyms'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const <String>[];
    final episodes = (j['num_episodes'] as num?)?.toInt();
    return MalAnime(
      id: (j['id'] as num?)?.toInt() ?? 0,
      title: (j['title'] ?? '').toString(),
      alternativeTitles: [
        if (alt?['en'] is String) alt!['en'] as String,
        if (alt?['ja'] is String) alt!['ja'] as String,
        ...synonyms,
      ],
      picture: (j['main_picture'] as Map?)?['medium'] as String? ??
          (j['main_picture'] as Map?)?['large'] as String?,
      episodes: (episodes != null && episodes > 0) ? episodes : null,
    );
  }
}

/// One row of the viewer's MyAnimeList.
class MalListEntry {
  const MalListEntry({
    required this.anime,
    required this.status,
    this.progress = 0,
    this.score = 0,
    this.isRewatching = false,
    this.updatedAt,
  });

  final MalAnime anime;

  /// One of [MalStatus]. MAL never returns a row without one.
  final String status;

  final int progress;

  /// 0-10, where 0 means "not scored". MAL has no half points.
  final int score;

  final bool isRewatching;

  /// Server clock, for sorting most-recently-touched first.
  final DateTime? updatedAt;

  /// Episodes left to watch, or null when the total is unknown (still airing).
  int? get remaining {
    final total = anime.episodes;
    if (total == null || total <= 0) return null;
    final left = total - progress;
    return left > 0 ? left : 0;
  }

  double get fraction {
    final total = anime.episodes;
    if (total == null || total <= 0) return 0;
    return (progress / total).clamp(0.0, 1.0);
  }

  MalListEntry copyWith({
    String? status,
    int? progress,
    int? score,
    bool? isRewatching,
  }) => MalListEntry(
        anime: anime,
        status: status ?? this.status,
        progress: progress ?? this.progress,
        score: score ?? this.score,
        isRewatching: isRewatching ?? this.isRewatching,
        updatedAt: updatedAt,
      );

  /// Parses one `{ node, list_status }` pair from `/users/@me/animelist`.
  static MalListEntry? fromJson(Map<String, dynamic> row) {
    final node = (row['node'] as Map?)?.cast<String, dynamic>();
    final listStatus = (row['list_status'] as Map?)?.cast<String, dynamic>();
    if (node == null || listStatus == null) return null;
    final anime = MalAnime.fromJson(node);
    if (anime.id <= 0) return null;
    return MalListEntry(
      anime: anime,
      status: (listStatus['status'] ?? MalStatus.watching).toString(),
      progress: (listStatus['num_episodes_watched'] as num?)?.toInt() ?? 0,
      score: (listStatus['score'] as num?)?.toInt() ?? 0,
      isRewatching: listStatus['is_rewatching'] == true,
      updatedAt: DateTime.tryParse('${listStatus['updated_at']}'),
    );
  }
}

/// The statuses a library screen shows, in the order people expect them.
///
/// A plain list rather than an enum: MAL identifies them by the wire string,
/// and a second representation would only need mapping back at every edge.
const List<String> kMalLibraryStatuses = [
  MalStatus.watching,
  MalStatus.completed,
  MalStatus.onHold,
  MalStatus.dropped,
  MalStatus.planToWatch,
];

