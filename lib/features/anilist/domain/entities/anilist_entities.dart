/// The AniList account a stored token belongs to.
class AnilistViewer {
  const AnilistViewer({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.siteUrl,
  });

  final int id;
  final String name;
  final String? avatarUrl;
  final String? siteUrl;

  factory AnilistViewer.fromJson(Map<String, dynamic> json) => AnilistViewer(
    id: (json['id'] as num?)?.toInt() ?? 0,
    name: json['name'] as String? ?? '',
    avatarUrl: (json['avatar'] as Map?)?['large'] as String?,
    siteUrl: json['siteUrl'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'avatarUrl': avatarUrl,
    'siteUrl': siteUrl,
  };
}

/// The next episode AniList expects to air.
///
/// [airingAt] is a UNIX second, not a millisecond — the whole AniList API deals
/// in seconds, and multiplying at the boundary keeps that conversion in exactly
/// one place.
class AnilistAiring {
  const AnilistAiring({required this.episode, required this.airingAt});

  final int episode;
  final int airingAt;

  DateTime get airsAt => DateTime.fromMillisecondsSinceEpoch(
    airingAt * 1000,
    isUtc: true,
  ).toLocal();

  /// Time left, recomputed from the clock on every read.
  ///
  /// AniList also returns `timeUntilAiring`, but that value is frozen at the
  /// moment of the response — a screen left open would count down from a stale
  /// number, or show a negative one.
  Duration get timeLeft => airsAt.difference(DateTime.now());

  bool get hasAired => timeLeft.isNegative;

  static AnilistAiring? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final airingAt = (json['airingAt'] as num?)?.toInt();
    if (airingAt == null || airingAt <= 0) return null;
    return AnilistAiring(
      episode: (json['episode'] as num?)?.toInt() ?? 0,
      airingAt: airingAt,
    );
  }
}

/// One anime on AniList.
/// One episode of one show, at the minute it goes out.
///
/// Distinct from [AnilistAiring], which hangs off a media object and only ever
/// describes that show's NEXT episode. The calendar asks the opposite question
/// — what airs in this window — so the airing is the subject and the media is
/// the detail.
class AnilistScheduledAiring {
  const AnilistScheduledAiring({
    required this.media,
    required this.episode,
    required this.airingAt,
  });

  final AnilistMedia media;
  final int episode;
  final int airingAt;

  DateTime get airsAt => DateTime.fromMillisecondsSinceEpoch(
    airingAt * 1000,
    isUtc: true,
  ).toLocal();

  bool get hasAired => airsAt.isBefore(DateTime.now());

  static AnilistScheduledAiring? fromJson(Map<String, dynamic> json) {
    final rawMedia = json['media'];
    final airingAt = (json['airingAt'] as num?)?.toInt();
    if (rawMedia is! Map || airingAt == null) return null;
    return AnilistScheduledAiring(
      media: AnilistMedia.fromJson(rawMedia.cast<String, dynamic>()),
      episode: (json['episode'] as num?)?.toInt() ?? 0,
      airingAt: airingAt,
    );
  }
}

class AnilistMedia {
  const AnilistMedia({
    required this.id,
    this.idMal,
    this.romajiTitle,
    this.englishTitle,
    this.nativeTitle,
    this.coverImage,
    this.bannerImage,
    this.description,
    this.episodes,
    this.chapters,
    this.volumes,
    this.type,
    this.averageScore,
    this.seasonYear,
    this.format,
    this.status,
    this.siteUrl,
    this.nextAiring,
    this.isAdult = false,
  });

  final int id;

  /// Chapters and volumes for a manga or light novel, null for an anime.
  final int? chapters;
  final int? volumes;

  /// `ANIME` or `MANGA` — AniList's own split, where a light novel is MANGA.
  final String? type;

  bool get isManga => type == 'MANGA';

  /// The same show's id on MyAnimeList, when AniList knows one.
  ///
  /// Carried so that linking a title ONCE serves both trackers: AniList is the
  /// only side that can match a source title to anything, and it happens to
  /// hold MAL's id for the same entry. Without this the MAL tracker would need
  /// its own search and its own link sheet to learn what the user already told
  /// us. Null for entries AniList has no MAL counterpart for.
  final int? idMal;

  final String? romajiTitle;
  final String? englishTitle;
  final String? nativeTitle;
  final String? coverImage;
  final String? bannerImage;
  final String? description;
  final int? episodes;
  final int? averageScore;
  final int? seasonYear;
  final String? format;
  final String? status;
  final String? siteUrl;
  final AnilistAiring? nextAiring;
  final bool isAdult;

  /// What progress on this title is counted in: episodes for an anime,
  /// chapters for a manga or a light novel.
  ///
  /// Chapters and not volumes, even though AniList publishes both. A reader's
  /// position is a chapter number — volumes live in AniList's separate
  /// `progressVolumes`, which nothing here reads or writes — so a volume total
  /// as the denominator would put a reader on chapter 40 of 9.
  int? get totalUnits => episodes ?? chapters;

  /// Units that exist to watch or read right now.
  ///
  /// For an airing show AniList keeps `episodes` at the announced season total
  /// while only `nextAiring.episode - 1` have actually gone out. Offering to
  /// mark an unaired episode watched is nonsense, so callers cap against this.
  ///
  /// A serialising manga has no such announcement to be ahead of: AniList
  /// leaves `chapters` null until it knows the total, so an unknown total stays
  /// unknown here instead of being guessed at.
  int? get availableUnits {
    final next = nextAiring;
    if (next != null && next.episode > 0) return next.episode - 1;
    return totalUnits;
  }

  /// What to show, and what to search sources with.
  ///
  /// English first: source sites are indexed under the title people actually
  /// type, and a romaji-only search misses far more than it finds.
  String get displayTitle => (englishTitle?.trim().isNotEmpty ?? false)
      ? englishTitle!
      : (romajiTitle?.trim().isNotEmpty ?? false)
      ? romajiTitle!
      : (nativeTitle ?? '');

  /// Every title worth trying against a source, best guess first and no blanks
  /// or duplicates. A source that does not carry the English title often
  /// carries the romaji one.
  List<String> get searchTitles {
    final seen = <String>{};
    return [
      for (final t in [englishTitle, romajiTitle, nativeTitle])
        if (t != null && t.trim().isNotEmpty && seen.add(t.trim())) t.trim(),
    ];
  }

  factory AnilistMedia.fromJson(Map<String, dynamic> json) {
    final title = (json['title'] as Map?)?.cast<String, dynamic>();
    return AnilistMedia(
      id: (json['id'] as num?)?.toInt() ?? 0,
      idMal: (json['idMal'] as num?)?.toInt(),
      romajiTitle: title?['romaji'] as String?,
      englishTitle: title?['english'] as String?,
      nativeTitle: title?['native'] as String?,
      coverImage: (json['coverImage'] as Map?)?['large'] as String?,
      bannerImage: json['bannerImage'] as String?,
      description: json['description'] as String?,
      episodes: (json['episodes'] as num?)?.toInt(),
      chapters: (json['chapters'] as num?)?.toInt(),
      volumes: (json['volumes'] as num?)?.toInt(),
      type: json['type'] as String?,
      averageScore: (json['averageScore'] as num?)?.toInt(),
      seasonYear: (json['seasonYear'] as num?)?.toInt(),
      format: json['format'] as String?,
      status: json['status'] as String?,
      siteUrl: json['siteUrl'] as String?,
      nextAiring: AnilistAiring.fromJson(
        (json['nextAiringEpisode'] as Map?)?.cast<String, dynamic>(),
      ),
      isAdult: json['isAdult'] == true,
    );
  }
}

/// One row of the viewer's AniList library.
class AnilistListEntry {
  const AnilistListEntry({
    required this.id,
    required this.media,
    required this.status,
    required this.progress,
    this.score,
    this.updatedAt,
  });

  final int id;
  final AnilistMedia media;

  /// AniList's own status: CURRENT, PLANNING, COMPLETED, DROPPED, PAUSED, REPEATING.
  final String status;

  /// Units FINISHED, not an index — episodes on an anime, chapters on a manga
  /// or a light novel, which is the same field on AniList's side.
  final int progress;
  final double? score;
  final int? updatedAt;

  /// How far through, when the total is known. Null for a title with no
  /// announced total — an airing show or a running serial — where a bar would
  /// be a guess.
  double? get completion {
    final total = media.totalUnits;
    if (total == null || total <= 0) return null;
    return (progress / total).clamp(0.0, 1.0);
  }

  /// The count a row prints: "12 / 48", or a bare "12" when the total is
  /// unknown.
  ///
  /// Numbers with no unit word on purpose. The row is already under the shelf
  /// it belongs to, so "chapters" would only repeat that — and it is one line
  /// beside a cover, which a translated unit word pushes off the end of.
  String get progressLabel {
    final total = media.totalUnits;
    return (total != null && total > 0) ? '$progress / $total' : '$progress';
  }

  /// The next episode to watch or chapter to read, or null when nothing more
  /// is out yet.
  ///
  /// Capped against what actually exists rather than the announced total, so a
  /// weekly show stops offering "+1" once the viewer has caught up.
  int? get nextEpisode {
    final available = media.availableUnits;
    if (available != null && progress >= available) return null;
    return progress + 1;
  }

  /// Episodes aired or chapters out but not yet finished. 0 when caught up or
  /// unknown.
  int get behindBy {
    final available = media.availableUnits;
    if (available == null) return 0;
    final behind = available - progress;
    return behind > 0 ? behind : 0;
  }

  AnilistListEntry copyWith({int? progress, String? status}) =>
      AnilistListEntry(
        id: id,
        media: media,
        status: status ?? this.status,
        progress: progress ?? this.progress,
        score: score,
        updatedAt: updatedAt,
      );

  factory AnilistListEntry.fromJson(Map<String, dynamic> json) =>
      AnilistListEntry(
        id: (json['id'] as num?)?.toInt() ?? 0,
        media: AnilistMedia.fromJson(
          (json['media'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
        status: json['status'] as String? ?? 'CURRENT',
        progress: (json['progress'] as num?)?.toInt() ?? 0,
        score: (json['score'] as num?)?.toDouble(),
        updatedAt: (json['updatedAt'] as num?)?.toInt(),
      );
}

/// The statuses AniList exposes, in the order a library reads best.
///
/// [labelKey] rather than a literal: this list is rendered in three languages,
/// and an English constant baked into the enum would leak into all of them.
enum AnilistStatus {
  current('CURRENT', 'anilist.status_current'),
  repeating('REPEATING', 'anilist.status_repeating'),
  planning('PLANNING', 'anilist.status_planning'),
  completed('COMPLETED', 'anilist.status_completed'),
  paused('PAUSED', 'anilist.status_paused'),
  dropped('DROPPED', 'anilist.status_dropped');

  const AnilistStatus(this.value, this.labelKey);
  final String value;
  final String labelKey;

  static AnilistStatus? fromValue(String? value) {
    for (final s in AnilistStatus.values) {
      if (s.value == value) return s;
    }
    return null;
  }
}

/// The three shelves a library can show, and how each one is asked for.
///
/// Three shelves but only two queries: AniList has no NOVEL media type, so a
/// light novel is MANGA carrying format NOVEL — the same split the catalogue
/// already makes. Keeping [mediaType] and the format test in one place is what
/// stops the two drifting apart, because a picker that asks for a novel
/// collection gets an error and a picker that forgets the format shows every
/// novel on the manga shelf as well.
enum AnilistLibraryKind {
  anime('ANIME', 'anilist.kind_anime'),
  manga('MANGA', 'anilist.kind_manga'),
  novel('MANGA', 'anilist.kind_novel');

  const AnilistLibraryKind(this.mediaType, this.labelKey);

  /// AniList's own MediaType, which is what a list query takes.
  final String mediaType;

  /// A key rather than a word: this is rendered in twelve languages.
  final String labelKey;

  bool matches(AnilistMedia media) {
    if (this == anime) return !media.isManga;
    return media.isManga && (media.format == 'NOVEL') == (this == novel);
  }
}

/// One title that AniList says is related to another, and how.
///
/// The relation TYPE is the whole value here. "There is another Naruto" is
/// something a search already answers; "Shippuden is the sequel to this" is
/// not, and it is the actual question somebody has when they finish a series.
class AnilistRelation {
  const AnilistRelation({
    required this.id,
    required this.relationType,
    required this.title,
    this.type,
    this.format,
    this.year,
    this.coverImage,
  });

  final int id;

  /// AniList's own enum: SEQUEL, PREQUEL, SIDE_STORY, SOURCE, ADAPTATION …
  /// Kept raw so a value added upstream still renders as something rather than
  /// disappearing.
  final String relationType;

  final String title;

  /// ANIME or MANGA. A manga source listed next to an anime sequel needs to be
  /// distinguishable, because only one of them is watchable here.
  final String? type;

  /// TV, MOVIE, OVA, SPECIAL, MANGA …
  final String? format;

  final int? year;
  final String? coverImage;

  /// Ordered by how likely somebody is to want it next.
  ///
  /// A sequel is what a person who just finished something is looking for; the
  /// manga it was adapted from is interesting and almost never the next thing
  /// they open. Anything unrecognised sorts last rather than being dropped.
  static const List<String> order = [
    'SEQUEL',
    'PREQUEL',
    'PARENT',
    'SIDE_STORY',
    'ALTERNATIVE',
    'SPIN_OFF',
    'SUMMARY',
    'ADAPTATION',
    'SOURCE',
    'CHARACTER',
    'OTHER',
  ];

  int get rank {
    final i = order.indexOf(relationType.toUpperCase());
    return i < 0 ? order.length : i;
  }

  factory AnilistRelation.fromEdge(Map<String, dynamic> edge) {
    final node = (edge['node'] as Map?)?.cast<String, dynamic>() ?? const {};
    final titles = (node['title'] as Map?)?.cast<String, dynamic>() ?? const {};
    final english = titles['english'] as String?;
    final romaji = titles['romaji'] as String?;
    return AnilistRelation(
      id: (node['id'] as num?)?.toInt() ?? 0,
      relationType: (edge['relationType'] as String? ?? 'OTHER').toUpperCase(),
      // English first: it is what somebody typing in Latin script is looking
      // for, and the romaji is often a title they have never seen written.
      title: (english != null && english.isNotEmpty ? english : romaji) ?? '',
      type: node['type'] as String?,
      format: node['format'] as String?,
      year: (node['seasonYear'] as num?)?.toInt(),
      coverImage:
          ((node['coverImage'] as Map?)?.cast<String, dynamic>())?['large']
              as String?,
    );
  }
}

/// One character and who voices them, as AniList lists them on a title.
class AnilistCharacter {
  const AnilistCharacter({
    required this.name,
    required this.image,
    this.voiceActor,
    this.voiceActorImage,
  });

  final String name;
  final String? image;
  final String? voiceActor;
  final String? voiceActorImage;
}

/// Everything AniList knows about one title that a detail page can use.
///
/// [AnilistMedia] is the card: enough to list and to search. This is the page:
/// the score and where it ranks, who made it and from what, who is in it, what
/// AniList thinks you would watch next, and when the next episode lands. One
/// request per title, and only when the title is opened.
class AnilistMediaDetail {
  const AnilistMediaDetail({
    required this.media,
    this.meanScore,
    this.popularity,
    this.rankText,
    this.studio,
    this.author,
    this.source,
    this.durationMinutes,
    this.countryOfOrigin,
    this.genres = const [],
    this.tags = const [],
    this.characters = const [],
    this.recommendations = const [],
    this.trailerYoutubeId,
  });

  final AnilistMedia media;
  final int? meanScore;
  final int? popularity;

  /// "#2 most popular this season", already worded, or null when AniList
  /// has no ranking for it.
  final String? rankText;
  final String? studio;

  /// Who wrote it: a manga's author, and on an anime the writer it was
  /// adapted from — which is a fact worth a line on both, and the only line a
  /// manga has where an anime shows its studio. Null when AniList credits
  /// nobody with the story, as it does for an original anime.
  final String? author;

  /// MANGA, LIGHT_NOVEL, ORIGINAL… what the anime was adapted from.
  final String? source;
  final int? durationMinutes;
  final String? countryOfOrigin;
  final List<String> genres;
  final List<String> tags;
  final List<AnilistCharacter> characters;
  final List<AnilistMedia> recommendations;
  final String? trailerYoutubeId;
}
