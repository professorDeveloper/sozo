import 'package:soplay/core/content/catalogue.dart';
import 'package:soplay/core/content/content_mode.dart';

/// The four things a person can say they came for.
///
/// Anime and Movies & Series are both Watch mode but different catalogues,
/// which is why this is not [ContentMode].
enum TasteKind {
  anime('anime', ContentMode.video, Catalogue.anilist),
  movies('movies', ContentMode.video, Catalogue.tmdb),
  manga('manga', ContentMode.manga, Catalogue.anilistManga),
  novels('novels', ContentMode.novel, Catalogue.anilistNovel);

  const TasteKind(this.id, this.mode, this.catalogue);

  /// Persisted. Never rename one.
  final String id;
  final ContentMode mode;
  final Catalogue catalogue;

  String get labelKey => 'onboarding.kind_$id';
  String get hintKey => 'onboarding.kind_${id}_hint';

  static TasteKind? fromId(String? id) {
    for (final k in values) {
      if (k.id == id) return k;
    }
    return null;
  }
}

/// A genre, and which catalogues can be browsed by it.
///
/// The slug is the identity: AniList's "Sci-Fi" and TMDB's "Science Fiction"
/// are both `sci-fi`, so one chip stands for both.
class TasteGenre {
  const TasteGenre({
    required this.slug,
    required this.label,
    this.catalogues = const {},
    this.image,
  });

  final String slug;

  /// As the backend named it, in English. Screens translate by [slug].
  final String label;

  /// Catalogue kinds (`anilist`, `tmdb`, …) that list this genre.
  final Set<String> catalogues;
  final String? image;

  TasteGenre mergedWith(TasteGenre other) => TasteGenre(
    slug: slug,
    label: label.isNotEmpty ? label : other.label,
    catalogues: {...catalogues, ...other.catalogues},
    image: (image?.isNotEmpty ?? false) ? image : other.image,
  );

  Map<String, dynamic> toJson() => {
    'slug': slug,
    'label': label,
    'catalogues': catalogues.toList(),
    if (image != null) 'image': image,
  };

  factory TasteGenre.fromJson(Map<String, dynamic> j) => TasteGenre(
    slug: (j['slug'] ?? '').toString(),
    label: (j['label'] ?? '').toString(),
    catalogues: {
      for (final c in (j['catalogues'] as List? ?? const [])) c.toString(),
    },
    image: j['image'] as String?,
  );

  @override
  bool operator ==(Object other) => other is TasteGenre && other.slug == slug;

  @override
  int get hashCode => slug.hashCode;
}

/// What one profile said it likes. Written by onboarding, read by Home's
/// "Picked for you" band, and meant to be the input a recommendation engine
/// starts from.
class TasteProfile {
  const TasteProfile({
    this.kinds = const [],
    this.genres = const [],
    this.updatedAt = 0,
  });

  /// In the order picked; the first is the one the app opens on.
  final List<TasteKind> kinds;
  final List<TasteGenre> genres;
  final int updatedAt;

  static const TasteProfile empty = TasteProfile();

  bool get isEmpty => kinds.isEmpty && genres.isEmpty;

  TasteKind? get primary => kinds.isEmpty ? null : kinds.first;

  /// Modes in pick order, each once.
  List<ContentMode> get modes {
    final out = <ContentMode>[];
    for (final k in kinds) {
      if (!out.contains(k.mode)) out.add(k.mode);
    }
    return out;
  }

  /// Every (catalogue, genre) pair worth browsing in [mode], in pick order.
  List<({String catalogue, TasteGenre genre})> browseTargets(ContentMode mode) {
    final catalogues = [
      for (final k in kinds)
        if (k.mode == mode) k.catalogue.kind,
    ];
    return [
      for (final g in genres)
        for (final c in catalogues)
          if (g.catalogues.contains(c)) (catalogue: c, genre: g),
    ];
  }

  Map<String, dynamic> toJson() => {
    'kinds': [for (final k in kinds) k.id],
    'genres': [for (final g in genres) g.toJson()],
    'updatedAt': updatedAt,
  };

  factory TasteProfile.fromJson(Map<String, dynamic> j) => TasteProfile(
    kinds: [
      for (final id in (j['kinds'] as List? ?? const []))
        ?TasteKind.fromId(id.toString()),
    ],
    genres: [
      for (final g in (j['genres'] as List? ?? const []))
        if (g is Map) TasteGenre.fromJson(g.cast<String, dynamic>()),
    ],
    updatedAt: (j['updatedAt'] as num?)?.toInt() ?? 0,
  );
}

/// Genre lists merged across catalogues: one entry per slug, first seen first.
List<TasteGenre> mergeGenres(Iterable<TasteGenre> genres) {
  final bySlug = <String, TasteGenre>{};
  for (final g in genres) {
    if (g.slug.isEmpty) continue;
    final had = bySlug[g.slug];
    bySlug[g.slug] = had == null ? g : had.mergedWith(g);
  }
  return bySlug.values.toList();
}
