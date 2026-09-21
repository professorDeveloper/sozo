/// A country TMDB has a streaming line-up for.
class WatchRegionEntity {
  const WatchRegionEntity({
    required this.code,
    required this.name,
    this.nativeName = '',
  });

  /// ISO 3166-1 alpha-2, which is what every request takes.
  final String code;

  final String name;
  final String nativeName;
}
