part of 'search_bloc.dart';

enum SearchStatus {
  /// Nothing asked for yet — recents, genres and the hint live here.
  idle,

  /// First results for the current criteria; nothing to keep on screen.
  loading,

  /// New results for criteria that already have something on screen.
  refreshing,
  loaded,
  empty,
  error,
}

/// What the user is asking for. Text and genre are composable: either one, both
/// or neither, and every change re-runs through the same path.
class SearchCriteria extends Equatable {
  const SearchCriteria({
    this.text = '',
    this.genre = '',
    this.filters = const {},
  });

  final String text;
  final String genre;
  final Map<String, String> filters;

  bool get isEmpty => text.isEmpty && genre.isEmpty && filters.isEmpty;
  bool get isNotEmpty => !isEmpty;

  String get label => text.isNotEmpty
      ? text
      : filters.isNotEmpty
      ? "Discover"
      : genre;

  SearchCriteria copyWith({
    String? text,
    String? genre,
    Map<String, String>? filters,
  }) => SearchCriteria(
    text: text ?? this.text,
    genre: genre ?? this.genre,
    filters: filters ?? this.filters,
  );

  @override
  List<Object?> get props => [text, genre, filters];
}

class SearchState extends Equatable {
  const SearchState({
    this.criteria = const SearchCriteria(),
    this.status = SearchStatus.idle,
    this.items = const [],
    this.page = 1,
    this.totalPages = 1,
    this.isLoadingMore = false,
    this.failure,
    this.loadMoreFailure,
    this.genres = const [],
    this.genresLoading = false,
    this.genresFailed = false,
    this.recent = const [],
    this.weakResults = false,
    this.suggestions = const [],
  });

  final SearchCriteria criteria;
  final SearchStatus status;
  final List<MovieEntity> items;
  final int page;
  final int totalPages;
  final bool isLoadingMore;

  /// Why the last search failed, already classified and already phrased.
  ///
  /// Null when nothing has failed. [SourceFailure] rather than a string and a
  /// local enum: the Search tab used to carry its own three-way classifier
  /// with its own list of substrings, which is exactly the duplication
  /// [SourceFailureKind] exists to end. It knew "network" and "source" and
  /// nothing else, so a source that had shut down, a source behind Cloudflare
  /// and a source whose extension no longer matches the app all came out as
  /// "Search failed" with a Java stack line underneath.
  final SourceFailure? failure;

  /// Why the NEXT page failed, when the pages already on screen are fine.
  ///
  /// Separate from [failure] because they want opposite treatments: a first
  /// page that fails has nothing to show and takes the screen, while a second
  /// page that fails must not disturb the results the reader is looking at.
  /// This used to be neither — the failure was dropped on the floor, the
  /// spinner vanished, no row arrived and no reason was given.
  final SourceFailure? loadMoreFailure;

  /// Genres are a *field*, not a state: a failed genre fetch must never be able
  /// to paint the search screen as broken, and clearing the box must never be
  /// able to wipe results.
  final List<GenreEntity> genres;
  final bool genresLoading;
  final bool genresFailed;

  final List<String> recent;

  /// The source answered, but nothing it returned looks like the query.
  ///
  /// This is the dead end the search tab used to leave people in. One row
  /// titled "Learn To Draw APK" for a search for "naruto" is not an error, is
  /// not empty, and is not an answer — and because it is not empty, the "try
  /// all sources" way out never appeared. Six other sources had the show.
  final bool weakResults;

  /// Titles that exist, for the query being typed.
  ///
  /// Metadata, not results: these come from AniList and TMDB, which know what
  /// things are called, rather than from the sources, which know what they can
  /// play. That is the point — someone who typed "narutoo" needs to be told the
  /// word before any source can help them.
  final List<String> suggestions;

  bool get hasMore => page < totalPages;
  bool get hasGenres => genres.isNotEmpty;
  bool get isBusy =>
      status == SearchStatus.loading || status == SearchStatus.refreshing;

  /// The selected genre in words, or an empty string when none is selected.
  ///
  /// [SearchCriteria.genre] holds the source's *slug* — `action-adventure`, or
  /// a bare TMDB id like `10759` — because that is what a browse request takes.
  /// Every screen that needed to name the active filter reached for that slug
  /// and printed it, so a genre that found nothing said "No results for
  /// 10759". The names are already in [genres]; nothing was looking them up.
  ///
  /// A slug with no entry is humanised rather than dropped: the genre list can
  /// arrive after the browse (or fail outright), and a filter that names
  /// itself "Action adventure" is still better than one that names itself
  /// nothing at all.
  String get genreName {
    final slug = criteria.genre;
    if (slug.isEmpty) return '';
    for (final g in genres) {
      if (g.slug != slug) continue;
      return g.name.isNotEmpty ? g.name : _humanise(slug);
    }
    return _humanise(slug);
  }

  /// What the user asked for, in words. Never a slug — see [genreName].
  String get criteriaLabel =>
      criteria.text.isNotEmpty ? criteria.text : genreName;

  static String _humanise(String slug) {
    final words = slug
        .replaceAll(RegExp(r'[-_+]+'), ' ')
        .split(' ')
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return slug;
    return words.map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');
  }

  SearchState copyWith({
    SearchCriteria? criteria,
    SearchStatus? status,
    List<MovieEntity>? items,
    int? page,
    int? totalPages,
    bool? isLoadingMore,
    SourceFailure? failure,
    SourceFailure? loadMoreFailure,
    bool clearLoadMoreFailure = false,
    List<GenreEntity>? genres,
    bool? genresLoading,
    bool? genresFailed,
    List<String>? recent,
    bool? weakResults,
    List<String>? suggestions,
    bool clearError = false,
  }) => SearchState(
    criteria: criteria ?? this.criteria,
    status: status ?? this.status,
    items: items ?? this.items,
    page: page ?? this.page,
    totalPages: totalPages ?? this.totalPages,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    failure: clearError ? null : (failure ?? this.failure),
    loadMoreFailure: clearLoadMoreFailure
        ? null
        : (loadMoreFailure ?? this.loadMoreFailure),
    genres: genres ?? this.genres,
    genresLoading: genresLoading ?? this.genresLoading,
    genresFailed: genresFailed ?? this.genresFailed,
    recent: recent ?? this.recent,
    weakResults: weakResults ?? this.weakResults,
    suggestions: suggestions ?? this.suggestions,
  );

  @override
  List<Object?> get props => [
    criteria,
    status,
    items,
    page,
    totalPages,
    isLoadingMore,
    failure,
    loadMoreFailure,
    genres,
    genresLoading,
    genresFailed,
    recent,
    weakResults,
    suggestions,
  ];
}
