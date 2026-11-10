class EpisodeEntity {
  final int episode;
  final String label;
  final String mediaRef;
  final List<String> availableLangs;
  final bool? hasSub;
  final bool? hasDub;
  final String? image;
  final String? airdate;
  final String? runtime;
  final String? overview;

  /// This chapter or episode's own page on the source's website, when the
  /// source can name one.
  ///
  /// An extension stores `url` as a path relative to its own `baseUrl`, so the
  /// app never held a link it could hand to a browser — the hosts now resolve
  /// it against the base they alone know. Null for a provider that has no web
  /// page to point at, and the action that uses this is hidden then rather than
  /// opening something that is not there.
  final String? webUrl;

  /// The group that translated a manga chapter. A source often lists the
  /// same chapter once per group; the chapter list filters by it.
  final String? scanlator;

  /// The season this episode belongs to, when the source lists more than one
  /// in a single run — a CloudStream series hands every season over at once.
  /// Null for a single-season list, so nothing about those changes.
  final int? season;

  /// The episode's number within [season], as the source wrote it. [episode]
  /// is then the position in the whole run: two seasons both start at 1, and
  /// the number is what downloads, history and the player tell episodes apart
  /// by — Lupin's S2E1 used to be a second "episode 1", sorted in among S1's.
  final int? numberInSeason;

  const EpisodeEntity({
    required this.episode,
    required this.label,
    required this.mediaRef,
    this.availableLangs = const [],
    this.hasSub,
    this.hasDub,
    this.image,
    this.airdate,
    this.runtime,
    this.overview,
    this.webUrl,
    this.scanlator,
    this.season,
    this.numberInSeason,
  });

  /// "S2 E1" for an episode of a multi-season run, the plain number otherwise.
  String get numberLabel =>
      season == null ? '$episode' : 'S$season E${numberInSeason ?? episode}';
}
