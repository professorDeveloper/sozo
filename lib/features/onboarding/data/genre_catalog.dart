import 'package:easy_localization/easy_localization.dart';
import 'package:soplay/features/onboarding/domain/taste_profile.dart';
import 'package:soplay/features/search/domain/entities/genre_entity.dart';

/// The genres to offer for a set of kinds: each picked kind's catalogue asked
/// for its list, merged into one set of chips.
class GenreCatalog {
  GenreCatalog({required this.fetch});

  /// One catalogue's genres, by catalogue kind (`anilist`, `tmdb`, …).
  final Future<List<GenreEntity>> Function(String catalogue) fetch;

  /// Not offered on a first-run screen, whatever the adult setting says.
  static const Set<String> hidden = {'hentai', 'ecchi'};

  final Map<String, List<TasteGenre>> _cache = {};

  /// Returns the merged list, or [fallback] for any catalogue that could not
  /// be reached. Never throws.
  Future<({List<TasteGenre> genres, bool offline})> load(
    List<TasteKind> kinds,
  ) async {
    final catalogues = [for (final k in kinds) k.catalogue.kind];
    var offline = false;
    final lists = await Future.wait([
      for (final c in catalogues)
        _one(c).catchError((Object _) {
          offline = true;
          return fallbackFor(c);
        }),
    ]);
    return (genres: mergeGenres(lists.expand((l) => l)), offline: offline);
  }

  Future<List<TasteGenre>> _one(String catalogue) async {
    final hit = _cache[catalogue];
    if (hit != null) return hit;
    final fetched = await fetch(catalogue).timeout(const Duration(seconds: 8));
    final out = [
      for (final g in fetched)
        if (g.slug.isNotEmpty && !hidden.contains(g.slug))
          TasteGenre(
            slug: g.slug,
            label: g.label,
            catalogues: {catalogue},
            image: g.image.isEmpty ? null : g.image,
          ),
    ];
    if (out.isEmpty) throw StateError('no genres for $catalogue');
    return _cache[catalogue] = out;
  }

  /// What the backend lists today, for when it cannot be asked.
  static List<TasteGenre> fallbackFor(String catalogue) {
    final slugs = catalogue == 'tmdb' ? _tmdb : _anilist;
    return [
      for (final s in slugs)
        TasteGenre(slug: s.$1, label: s.$2, catalogues: {catalogue}),
    ];
  }

  static const List<(String, String)> _anilist = [
    ('action', 'Action'),
    ('adventure', 'Adventure'),
    ('comedy', 'Comedy'),
    ('drama', 'Drama'),
    ('fantasy', 'Fantasy'),
    ('horror', 'Horror'),
    ('mahou-shoujo', 'Mahou Shoujo'),
    ('mecha', 'Mecha'),
    ('music', 'Music'),
    ('mystery', 'Mystery'),
    ('psychological', 'Psychological'),
    ('romance', 'Romance'),
    ('sci-fi', 'Sci-Fi'),
    ('slice-of-life', 'Slice of Life'),
    ('sports', 'Sports'),
    ('supernatural', 'Supernatural'),
    ('thriller', 'Thriller'),
  ];

  static const List<(String, String)> _tmdb = [
    ('action', 'Action'),
    ('adventure', 'Adventure'),
    ('animation', 'Animation'),
    ('comedy', 'Comedy'),
    ('crime', 'Crime'),
    ('documentary', 'Documentary'),
    ('drama', 'Drama'),
    ('family', 'Family'),
    ('fantasy', 'Fantasy'),
    ('history', 'History'),
    ('horror', 'Horror'),
    ('music', 'Music'),
    ('mystery', 'Mystery'),
    ('romance', 'Romance'),
    ('sci-fi', 'Science Fiction'),
    ('thriller', 'Thriller'),
    ('war', 'War'),
    ('western', 'Western'),
  ];
}

/// The genre's name in the interface language when there is one, otherwise
/// the catalogue's own English name.
String genreDisplayName(TasteGenre genre) {
  final key = 'onboarding.genre_names.${genre.slug}';
  try {
    if (key.trExists()) return key.tr();
  } catch (_) {
    // No translations loaded — tests, or a frame before the loader ran.
  }
  return genre.label.isNotEmpty ? genre.label : genre.slug;
}
