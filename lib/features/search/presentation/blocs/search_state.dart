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

/// Why a search failed, so the view can stop blaming the user's wifi for a
/// broken extension source.
enum SearchFailureKind { network, source, unknown }

/// What the user is asking for. Text and genre are composable: either one, both
/// or neither, and every change re-runs through the same path.
class SearchCriteria extends Equatable {
  const SearchCriteria({this.text = '', this.genre = ''});

  final String text;
  final String genre;

  bool get isEmpty => text.isEmpty && genre.isEmpty;
  bool get isNotEmpty => !isEmpty;

  String get label => text.isNotEmpty ? text : genre;

  SearchCriteria copyWith({String? text, String? genre}) => SearchCriteria(
        text: text ?? this.text,
        genre: genre ?? this.genre,
      );

  @override
  List<Object?> get props => [text, genre];
}

class SearchState extends Equatable {
  const SearchState({
    this.criteria = const SearchCriteria(),
    this.status = SearchStatus.idle,
    this.items = const [],
    this.page = 1,
    this.totalPages = 1,
    this.isLoadingMore = false,
    this.errorMessage = '',
    this.errorKind = SearchFailureKind.unknown,
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

  final String errorMessage;
  final SearchFailureKind errorKind;

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

  SearchState copyWith({
    SearchCriteria? criteria,
    SearchStatus? status,
    List<MovieEntity>? items,
    int? page,
    int? totalPages,
    bool? isLoadingMore,
    String? errorMessage,
    SearchFailureKind? errorKind,
    List<GenreEntity>? genres,
    bool? genresLoading,
    bool? genresFailed,
    List<String>? recent,
    bool? weakResults,
    List<String>? suggestions,
    bool clearError = false,
  }) =>
      SearchState(
        criteria: criteria ?? this.criteria,
        status: status ?? this.status,
        items: items ?? this.items,
        page: page ?? this.page,
        totalPages: totalPages ?? this.totalPages,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        errorMessage: clearError ? '' : (errorMessage ?? this.errorMessage),
        errorKind: clearError
            ? SearchFailureKind.unknown
            : (errorKind ?? this.errorKind),
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
        errorMessage,
        errorKind,
        genres,
        genresLoading,
        genresFailed,
        recent,
        weakResults,
        suggestions,
      ];
}

/// Best-effort classification of a repository failure.
///
/// The repository and the extension hosts already distinguish "source
/// unavailable" from "no match"; this keeps that distinction alive up to the
/// view instead of collapsing everything into "check your connection".
SearchFailureKind classifySearchFailure(String raw) {
  final m = raw.toLowerCase();
  if (m.contains('socketexception') ||
      m.contains('failed host lookup') ||
      m.contains('connection error') ||
      m.contains('connection refused') ||
      m.contains('connection closed') ||
      m.contains('network is unreachable') ||
      m.contains('timeout') ||
      m.contains('timed out')) {
    return SearchFailureKind.network;
  }
  if (m.contains('source unavailable') ||
      m.contains('platformexception') ||
      m.contains('extension') ||
      m.contains('extractor')) {
    return SearchFailureKind.source;
  }
  return SearchFailureKind.unknown;
}

String cleanFailureMessage(String raw) {
  var m = raw.trim();
  while (m.startsWith('Exception:')) {
    m = m.substring('Exception:'.length).trim();
  }
  return m;
}
