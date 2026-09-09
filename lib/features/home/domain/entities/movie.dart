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
  });
}
