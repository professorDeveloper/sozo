import 'package:soplay/core/content/content_mode.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/home/domain/entities/movie.dart';
import 'package:soplay/features/home/domain/entities/view_all_paging_entity.dart';
import 'package:soplay/features/onboarding/domain/taste_profile.dart';

class PickedForYou {
  const PickedForYou({
    required this.catalogue,
    required this.genre,
    required this.items,
  });

  final String catalogue;
  final TasteGenre genre;
  final List<MovieEntity> items;

  /// The `/view-all` slug for type `catalogue-genre`.
  String get slug => '$catalogue:${genre.slug}';
}

/// [targets] starting from today's, so the band shows a different genre each
/// day and cycles through all of them.
List<T> rotateForDay<T>(List<T> targets, DateTime day) {
  if (targets.isEmpty) return targets;
  final days = DateTime.utc(
    day.year,
    day.month,
    day.day,
  ).difference(DateTime.utc(2024)).inDays;
  final start = days % targets.length;
  return [...targets.skip(start), ...targets.take(start)];
}

/// Home's "Picked for you": one of the picked genres, browsed in a catalogue
/// that matches the mode Home is in.
///
/// A deliberately small stand-in for real recommendations — the input is the
/// [TasteProfile] a later engine will start from too.
class PickedForYouSource {
  PickedForYouSource({required this.load, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// A `catalogue-genre` page by slug (`anilist:action`).
  final Future<Result<ViewAllPagingEntity>> Function(String slug) load;
  final DateTime Function() _clock;

  static const Duration ttl = Duration(hours: 6);
  final Map<String, ({DateTime at, List<MovieEntity> items})> _cache = {};

  /// What to browse for [taste] in [mode], limited to [catalogue] (a
  /// catalogue kind such as `tmdb`) when Home is showing one.
  List<({String catalogue, TasteGenre genre})> targetsFor(
    TasteProfile taste,
    ContentMode mode, {
    String? catalogue,
  }) => [
    for (final t in taste.browseTargets(mode))
      if (catalogue == null || t.catalogue == catalogue) t,
  ];

  /// The cached answer for [taste] in [mode], without asking anything.
  PickedForYou? peek(
    TasteProfile taste,
    ContentMode mode, {
    String? catalogue,
  }) {
    for (final t in rotateForDay(
      targetsFor(taste, mode, catalogue: catalogue),
      _clock(),
    )) {
      final slug = '${t.catalogue}:${t.genre.slug}';
      final hit = _cache[slug];
      if (hit == null || _clock().difference(hit.at) > ttl) return null;
      if (hit.items.isNotEmpty) {
        return PickedForYou(
          catalogue: t.catalogue,
          genre: t.genre,
          items: hit.items,
        );
      }
    }
    return null;
  }

  /// Today's genre, or the next one along when today's comes back empty.
  /// Null when nothing was picked for [mode] or nothing answered.
  Future<PickedForYou?> fetch(
    TasteProfile taste,
    ContentMode mode, {
    String? catalogue,
  }) async {
    final targets = rotateForDay(
      targetsFor(taste, mode, catalogue: catalogue),
      _clock(),
    );
    for (final t in targets.take(3)) {
      final slug = '${t.catalogue}:${t.genre.slug}';
      final hit = _cache[slug];
      List<MovieEntity> items;
      if (hit != null && _clock().difference(hit.at) <= ttl) {
        items = hit.items;
      } else {
        final result = await load(slug);
        final page = result.getOrNull();
        if (page == null) continue;
        items = page.items;
        _cache[slug] = (at: _clock(), items: items);
      }
      if (items.isNotEmpty) {
        return PickedForYou(
          catalogue: t.catalogue,
          genre: t.genre,
          items: items,
        );
      }
    }
    return null;
  }
}
