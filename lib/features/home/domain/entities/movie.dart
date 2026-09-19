class MovieEntity {
  final String externalId;
  final String title;
  final String description;
  final String slug;
  final String url;
  final String provider;
  final String? thumbnail;

  /// The wide still, for card layouts that are landscape rather than portrait.
  ///
  /// Null for most providers and for plenty of TMDB titles — older and
  /// regional releases often have no backdrop on file — so anything drawing
  /// this needs a portrait fallback rather than an empty frame.
  final String? banner;

  final int? year;
  final int? rating;
  final List<String>? qualities;
  final String category;

  /// The other names this work goes by, best first.
  ///
  /// Only a catalogue fills this: AniList knows a title in English, romaji and
  /// the original script, and TMDB knows a localised name and an original one.
  /// [title] is one of them, picked for display; the rest are here because a
  /// SOURCE does not get to choose — it indexes under whichever name its own
  /// site uses. animecube lists "Kaiju Girl Caramelise" and answers a search for
  /// "Otome Kaijuu Caramelise" with nothing at all, so a title every source
  /// carried was recorded as carried by none.
  ///
  /// Empty for a source's own rows, which have exactly one name by definition.
  final List<String> altTitles;

  MovieEntity({
    required this.externalId,
    required this.title,
    required this.description,
    required this.slug,
    required this.url,
    required this.provider,
    required this.thumbnail,
    this.banner,
    required this.year,
    required this.rating,
    required this.qualities,
    required this.category,
    this.altTitles = const [],
  });
}
