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
  });
}
