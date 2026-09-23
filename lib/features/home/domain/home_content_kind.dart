import 'package:soplay/core/content/content_mode.dart';

/// Home recommendations follow the chosen medium, not merely video vs reader.
enum HomeContentKind {
  movie,
  anime,
  manga,
  novel;

  static HomeContentKind resolve({
    required String providerId,
    required ContentMode mode,
    String category = '',
  }) {
    if (mode == ContentMode.manga || providerId == 'cat:anilist-manga') {
      return manga;
    }
    if (mode == ContentMode.novel || providerId == 'cat:anilist-novel') {
      return novel;
    }
    // VidAPI is the default TMDB-backed source, including before metadata loads.
    if (providerId == 'cat:tmdb' || providerId == 'vidapi') return movie;
    if (providerId == 'cat:anilist') return anime;
    return {
          'tmdb',
          'movie',
          'movies',
          'series',
          'tv',
          'drama',
          'movies & series',
        }.contains(category.trim().toLowerCase())
        ? movie
        : anime;
  }

  String get catalogueKind => switch (this) {
    movie => 'tmdb',
    anime => 'anilist',
    manga => 'anilist-manga',
    novel => 'anilist-novel',
  };
}
