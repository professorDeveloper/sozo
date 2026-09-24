import 'package:flutter/material.dart';
import 'package:soplay/features/onboarding/data/onboarding_posters.dart';
import 'package:soplay/features/onboarding/domain/taste_profile.dart';

/// How a kind looks on the setup screens.
extension TasteKindStyle on TasteKind {
  Color get accent => switch (this) {
    TasteKind.anime => const Color(0xFF4FA3FF),
    TasteKind.movies => const Color(0xFFFF6B4A),
    TasteKind.manga => const Color(0xFF8B6CFF),
    TasteKind.novels => const Color(0xFFE0A23C),
  };

  IconData get icon => switch (this) {
    TasteKind.anime => Icons.animation_rounded,
    TasteKind.movies => Icons.movie_filter_rounded,
    TasteKind.manga => Icons.auto_stories_rounded,
    TasteKind.novels => Icons.menu_book_rounded,
  };

  /// Bundled art to stand in for the kind. The reading kinds have none of
  /// their own and borrow the anime covers, which are the same stories.
  List<String> get posters => switch (this) {
    TasteKind.movies => kMoviePosters,
    TasteKind.anime => kAnimePosters,
    TasteKind.manga => kAnimePosters.sublist(8),
    TasteKind.novels => kAnimePosters.sublist(16),
  };
}

/// Posters for a set of kinds, interleaved, for backdrops.
List<String> postersFor(List<TasteKind> kinds, {int count = 18}) {
  final sets = kinds.isEmpty
      ? [kMoviePosters, kAnimePosters]
      : [for (final k in kinds) k.posters];
  final out = <String>[];
  for (var i = 0; out.length < count; i++) {
    final set = sets[i % sets.length];
    out.add(set[(i ~/ sets.length) % set.length]);
  }
  return out;
}
