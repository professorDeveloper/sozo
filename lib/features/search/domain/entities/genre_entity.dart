class GenreEntity {
  final String provider;
  final String slug;
  final String url;
  final String image;
  final String name;

  GenreEntity({
    required this.provider,
    required this.slug,
    required this.image,
    required this.url,
    this.name = '',
  });

  /// What to call it: its name, or its slug made readable where a source sent
  /// none — `science-fiction` as "Science Fiction", not as a url.
  String get label {
    if (name.isNotEmpty) return name;
    return slug
        .replaceAll('-', ' ')
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
}
