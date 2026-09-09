import 'dart:async';
import 'dart:collection';

import 'package:soplay/features/anilist/data/anilist_api.dart';
import 'package:soplay/features/search/data/datasources/search_data_source.dart';

/// Title autocomplete for the search field.
///
/// ## Why this is not the search
///
/// The search fans out to every selected source, each of which scrapes a site.
/// It is expensive, it is slow, and — as the relevance work showed — several
/// sources answer a question they were not asked. None of that is what someone
/// half-way through typing "narut" needs. They need to know the show is called
/// *Naruto Shippuden* so they can stop typing.
///
/// So this asks metadata catalogues instead, which are fast, keyed on titles,
/// and cannot return a catalogue dump. Two of them, because Sozo is not only an
/// anime app: AniList knows the anime canon, and the backend's TMDB-backed
/// providers know films and series. Asking one would leave half the library
/// with no suggestions at all.
///
/// ## Best-effort, always
///
/// Every failure path returns an empty list. A suggestion strip that is
/// sometimes absent costs nothing; an autocomplete that can throw would take
/// the search field down with it, and the field has to keep working when
/// AniList is rate-limiting or the phone is on a train.
class TitleSuggestionService {
  TitleSuggestionService({
    required AnilistApi anilist,
    required SearchDataSource dataSource,
    this.filmProviders = defaultFilmProviders,
  })  : _anilist = anilist,
        _dataSource = dataSource;

  final AnilistApi _anilist;
  final SearchDataSource _dataSource;

  /// Backend providers whose catalogue is TMDB, tried in order until one
  /// answers.
  ///
  /// Named rather than "whatever the current provider is" on purpose: the
  /// current provider is exactly the one that might be a scraper answering with
  /// its front page, and its idea of a title is what the user is trying to get
  /// away from. A fallback list rather than one id because a single provider
  /// being down should cost a slower suggestion, not every film suggestion.
  static const List<String> defaultFilmProviders = ['vidapi', 'primesrc'];

  final List<String> filmProviders;

  /// Short enough that a suggestion never arrives after the answer it was
  /// meant to help find. A metadata lookup that has not answered in this long
  /// has stopped being autocomplete.
  static const Duration budget = Duration(seconds: 4);

  static const int _minLength = 2;
  static const int _cacheEntries = 40;

  /// Keyed by the lowercased query. Typing forwards and then backspacing walks
  /// back over prefixes that were just fetched, which is the single most common
  /// thing anyone does in a search field.
  final LinkedHashMap<String, List<String>> _cache = LinkedHashMap();

  /// Up to [limit] distinct titles for [query]. Never throws.
  Future<List<String>> suggest(String query, {int limit = 8}) async {
    final q = query.trim();
    if (q.length < _minLength) return const [];

    final key = q.toLowerCase();
    final hit = _cache.remove(key);
    if (hit != null) {
      _cache[key] = hit; // most-recently-used
      return hit;
    }

    final both = await Future.wait([_anime(q, limit), _film(q, limit)]);
    final merged = _interleave(both[1], both[0], limit);

    // Only a real answer is remembered. Caching an empty list would make one
    // rate-limited moment look like "this title does not exist" for as long as
    // the field stays open.
    if (merged.isNotEmpty) {
      _cache[key] = merged;
      if (_cache.length > _cacheEntries) _cache.remove(_cache.keys.first);
    }
    return merged;
  }

  /// Films first, then anime, alternating.
  ///
  /// Alternating rather than concatenating because a list that is film-shaped
  /// for eight rows tells an anime viewer the feature is broken, and vice
  /// versa. Whichever list runs out, the other fills the remaining slots.
  static List<String> _interleave(
    List<String> films,
    List<String> anime,
    int limit,
  ) {
    final out = <String>[];
    final seen = <String>{};
    final longest = films.length > anime.length ? films.length : anime.length;
    for (var i = 0; i < longest && out.length < limit; i++) {
      for (final list in [films, anime]) {
        if (i >= list.length) continue;
        final t = list[i].trim();
        if (t.isNotEmpty && seen.add(t.toLowerCase())) out.add(t);
        if (out.length >= limit) break;
      }
    }
    return out;
  }

  Future<List<String>> _anime(String q, int limit) async {
    try {
      final media = await _anilist
          .searchMedia(q, perPage: limit)
          .timeout(budget);
      return [
        for (final m in media)
          // English where it exists: it is what someone typing in Latin script
          // is reaching for, and the romaji is often a title they have never
          // seen written down.
          if ((m.englishTitle ?? m.romajiTitle ?? '').isNotEmpty)
            (m.englishTitle ?? m.romajiTitle)!,
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<List<String>> _film(String q, int limit) async {
    for (final provider in filmProviders) {
      try {
        final model = await _dataSource
            .searchMovies(q, provider: provider)
            .timeout(budget);
        final titles = [
          for (final item in model.items.take(limit))
            if (item.title.trim().isNotEmpty) item.title.trim(),
        ];
        if (titles.isNotEmpty) return titles;
      } catch (_) {
        // Try the next one. A provider being down costs a slower suggestion,
        // not the whole film half of the list.
      }
    }
    return const [];
  }

  void clearCache() => _cache.clear();
}
