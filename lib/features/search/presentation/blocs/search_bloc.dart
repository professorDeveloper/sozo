import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:soplay/core/analytics/analytics.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/home/domain/entities/movie.dart';
import 'package:soplay/features/search/data/search_recents_store.dart';
import 'package:soplay/features/search/data/title_suggestion_service.dart';
import 'package:soplay/features/search/domain/entities/genre_entity.dart';
import 'package:soplay/features/search/domain/entities/search_entity.dart';
import 'package:soplay/features/search/domain/usecases/genre_usecase.dart';
import 'package:soplay/features/search/domain/services/search_relevance.dart';
import 'package:soplay/features/search/domain/usecases/search_usecase.dart';
import 'package:soplay/features/search/presentation/blocs/search_query_policy.dart';

part 'search_event.dart';
part 'search_state.dart';

/// Single-source search.
///
/// Every handler that awaits carries the run token: a response that lands after
/// a newer run has started is dropped instead of overwriting it. Genres are a
/// field on the state, not a state of their own, so a failed genres fetch can
/// never repaint the results as a network error.
class SearchBloc extends Bloc<SearchEvent, SearchState> {
  final SearchUseCase _searchUseCase;
  final GenreUseCase _genreUseCase;
  final SearchRecentsStore _recents;

  /// Null in tests and wherever the app is built without it — every use is
  /// guarded, because an absent autocomplete is a missing convenience and a
  /// crashing one is a broken search field.
  final TitleSuggestionService? _suggestions;

  final QueryDebouncer _debouncer = QueryDebouncer();

  /// Its own timer, deliberately shorter than the search debounce.
  ///
  /// A suggestion is only useful while the user is still typing, so it has to
  /// arrive before they stop; the search runs at 450ms and this fires at 250ms,
  /// which puts the list on screen roughly when the first results do rather
  /// than after them.
  static const Duration _suggestDebounce = Duration(milliseconds: 250);
  Timer? _suggestTimer;
  int _suggestToken = 0;

  int _runToken = 0;
  int _genreToken = 0;

  /// What is in the box right now. Kept off the state on purpose: a keystroke
  /// must not rebuild the results grid.
  String _pendingText = '';

  SearchBloc({
    required SearchUseCase searchUseCase,
    required GenreUseCase genreUseCase,
    SearchRecentsStore? recentsStore,
    TitleSuggestionService? suggestions,
  })  : _searchUseCase = searchUseCase,
        _genreUseCase = genreUseCase,
        _recents = recentsStore ?? SearchRecentsStore(),
        _suggestions = suggestions,
        super(const SearchState()) {
    on<SearchLoad>(_onLoad);
    on<SearchQueryChanged>(_onQueryChanged);
    on<SearchSubmitted>(_onSubmitted);
    on<SearchGenreSelected>(_onGenreSelected);
    on<_SearchRun>(_onRun);
    on<SearchLoadMore>(_onLoadMore);
    on<SearchRetry>(_onRetry);
    on<SearchRecentRemoved>(_onRecentRemoved);
    on<SearchRecentsCleared>(_onRecentsCleared);
    on<SearchSuggestionsUpdated>(_onSuggestionsUpdated);

    add(const SearchLoad());
  }

  Future<void> _onLoad(SearchLoad event, Emitter<SearchState> emit) async {
    final genreToken = ++_genreToken;
    ++_runToken;
    _debouncer.reset();

    // Genres belong to the provider that is being left behind, and so do the
    // results; the text in the box does not.
    final criteria = SearchCriteria(text: state.criteria.text);
    emit(state.copyWith(
      criteria: criteria,
      status: criteria.isEmpty ? SearchStatus.idle : SearchStatus.loading,
      items: const [],
      page: 1,
      totalPages: 1,
      isLoadingMore: false,
      genres: const [],
      genresLoading: true,
      genresFailed: false,
      recent: _recents.load(),
      clearError: true,
    ));

    if (criteria.isNotEmpty) add(_SearchRun(criteria));

    final result = await _genreUseCase();
    if (genreToken != _genreToken || isClosed) return;
    emit(state.copyWith(
      genres: result.isSuccess ? result.getOrNull()! : const [],
      genresLoading: false,
      genresFailed: result.isError,
    ));
  }

  void _onQueryChanged(SearchQueryChanged event, Emitter<SearchState> emit) {
    final q = SearchQueryPolicy.normalize(event.query);
    _pendingText = q;

    _armSuggestions(q);

    if (q.isEmpty) {
      _debouncer.reset();
      ++_runToken;
      final criteria = state.criteria.copyWith(text: '');
      if (criteria.isEmpty) {
        emit(state.copyWith(
          criteria: criteria,
          status: SearchStatus.idle,
          items: const [],
          page: 1,
          totalPages: 1,
          isLoadingMore: false,
          recent: _recents.load(),
          clearError: true,
        ));
      } else {
        add(_SearchRun(criteria));
      }
      return;
    }

    _debouncer.schedule(q, (value) {
      if (isClosed) return;
      // Same reason as _onGenreSelected: the two cannot be combined, so the
      // one the user just acted on wins.
      add(_SearchRun(SearchCriteria(text: value, genre: '')));
    });
  }

  /// Asks for suggestions for [q], cancelling any request for an older prefix.
  ///
  /// Fire-and-forget: nothing awaits this, and the answer arrives as an event
  /// carrying the query it was for, so an answer for "naru" that lands after
  /// the user reached "naruto shi" is discarded instead of replacing a better
  /// list with a staler one.
  void _armSuggestions(String q) {
    _suggestTimer?.cancel();
    final service = _suggestions;
    if (service == null) return;
    if (q.length < 2) {
      if (state.suggestions.isNotEmpty) {
        add(const SearchSuggestionsUpdated('', []));
      }
      return;
    }
    final token = ++_suggestToken;
    _suggestTimer = Timer(_suggestDebounce, () async {
      final titles = await service.suggest(q);
      if (isClosed || token != _suggestToken || titles.isEmpty) return;
      add(SearchSuggestionsUpdated(q, titles));
    });
  }

  void _onSuggestionsUpdated(
    SearchSuggestionsUpdated event,
    Emitter<SearchState> emit,
  ) {
    // The box may have moved on or been cleared while the lookup was in flight.
    if (event.query.isNotEmpty && event.query != _pendingText) return;
    emit(state.copyWith(suggestions: event.suggestions));
  }

  void _onSubmitted(SearchSubmitted event, Emitter<SearchState> emit) {
    _pendingText = SearchQueryPolicy.normalize(event.query);
    _debouncer.runNow(_pendingText, (value) {
      if (isClosed) return;
      add(_SearchRun(state.criteria.copyWith(text: value)));
    });
  }

  void _onGenreSelected(SearchGenreSelected event, Emitter<SearchState> emit) {
    _debouncer.reset();
    // Genre and text do not compose: the server's /contents/search takes only
    // q, page and provider, so a genre sent alongside a query is dropped on the
    // floor and the user gets a plain text search under an active filter chip.
    // Picking a genre therefore browses that genre instead.
    final genre = event.genre.trim();
    if (genre.isNotEmpty) _pendingText = '';
    final text = genre.isNotEmpty
        ? ''
        : (SearchQueryPolicy.runnable(_pendingText) ? _pendingText : '');
    final criteria = SearchCriteria(text: text, genre: genre);
    if (criteria.isEmpty) {
      ++_runToken;
      emit(state.copyWith(
        criteria: criteria,
        status: SearchStatus.idle,
        items: const [],
        page: 1,
        totalPages: 1,
        isLoadingMore: false,
        recent: _recents.load(),
        clearError: true,
      ));
      return;
    }
    add(_SearchRun(criteria));
  }

  Future<void> _onRun(_SearchRun event, Emitter<SearchState> emit) async {
    final token = ++_runToken;
    final criteria = event.criteria;

    // Something is already on screen: keep it and show progress on top of it
    // rather than blanking the grid on every keystroke.
    final keepItems = state.items.isNotEmpty;
    emit(state.copyWith(
      criteria: criteria,
      status: keepItems ? SearchStatus.refreshing : SearchStatus.loading,
      isLoadingMore: false,
      weakResults: false,
      clearError: true,
    ));

    final result = await _fetch(criteria, 1);
    if (token != _runToken || isClosed) return;

    if (result.isError) {
      final raw = result.getErrorOrNull()!.toString();
      _debouncer.forget();
      emit(state.copyWith(
        status: SearchStatus.error,
        items: const [],
        page: 1,
        totalPages: 1,
        errorMessage: cleanFailureMessage(raw),
        errorKind: classifySearchFailure(raw),
      ));
      return;
    }

    final data = result.getOrNull()!;
    // Remembering the query is a convenience on the idle screen. It sits
    // between a fetch that has already succeeded and the emit that shows what
    // it returned, so anything it throws takes the results down with it — and
    // once did, for every query on every device. Results are not held hostage
    // to it.
    List<String> recent = state.recent;
    if (criteria.text.isNotEmpty) {
      try {
        recent = await _recents.add(criteria.text);
      } catch (_) {}
    }
    if (token != _runToken || isClosed) return;

    // Browsing a genre has no query to be relevant to; the source's own order
    // is the only meaningful one there.
    final query = criteria.text;
    var items = data.items;
    var weak = false;
    if (query.isNotEmpty) {
      if (SearchRelevance.looksUnsearched(items, query)) {
        // A page of rows that answer a different question. Reported as empty,
        // which is both true and the state that offers a way out.
        items = const [];
      } else {
        items = SearchRelevance.rank(items, query);
        // Not empty, but nothing here is the thing that was asked for — the
        // one aliased match this deliberately does not drop, or a source
        // padding a thin result. Either way the user needs the other sources
        // offered, not a grid they have to judge for themselves.
        weak = items.isNotEmpty && SearchRelevance.bestScore(items, query) == 0;
      }
    }

    // The search funnel, as counts only — never the query itself. The pair of
    // numbers that matters is how often a search returns nothing useful against
    // how often it returns something, because that is the difference between
    // "the catalogue is thin" and "the search is broken", and until now the
    // only evidence for either was somebody complaining.
    if (query.isNotEmpty) {
      getIt<Analytics>().track(
        items.isEmpty ? AnalyticsEvent.searchEmpty : AnalyticsEvent.searchRan,
        props: {
          AnalyticsProp.resultCount: items.length,
          AnalyticsProp.surface: 'single_source',
          // Weak is its own outcome: the source answered, with the wrong thing.
          if (weak) AnalyticsProp.reason: 'weak',
        },
      );
    }

    emit(state.copyWith(
      items: items,
      page: data.page,
      totalPages: data.totalPages,
      status: items.isEmpty ? SearchStatus.empty : SearchStatus.loaded,
      recent: recent,
      weakResults: weak,
      clearError: true,
    ));
  }

  Future<void> _onLoadMore(
    SearchLoadMore event,
    Emitter<SearchState> emit,
  ) async {
    if (state.status != SearchStatus.loaded ||
        state.isLoadingMore ||
        !state.hasMore) {
      return;
    }

    final token = ++_runToken;
    final criteria = state.criteria;
    final nextPage = state.page + 1;
    emit(state.copyWith(isLoadingMore: true));

    final result = await _fetch(criteria, nextPage);
    if (token != _runToken || isClosed) return;

    if (result.isError) {
      emit(state.copyWith(isLoadingMore: false));
      return;
    }

    final data = result.getOrNull()!;
    final seen = {for (final m in state.items) '${m.provider}::${m.url}'};
    final fresh = <MovieEntity>[
      for (final m in data.items)
        if (seen.add('${m.provider}::${m.url}')) m,
    ];
    // Ranked within the page, appended after it. Sorting the whole list again
    // would reorder cards the user has already scrolled past and is reaching
    // for — a page boundary is the one place reordering is invisible.
    final ranked = criteria.text.isEmpty
        ? fresh
        : SearchRelevance.rank(fresh, criteria.text);
    emit(state.copyWith(
      items: [...state.items, ...ranked],
      page: data.page,
      totalPages: data.totalPages,
      isLoadingMore: false,
    ));
  }

  void _onRetry(SearchRetry event, Emitter<SearchState> emit) {
    _debouncer.reset();
    if (state.criteria.isEmpty) {
      add(const SearchLoad());
      return;
    }
    add(_SearchRun(state.criteria));
  }

  Future<void> _onRecentRemoved(
    SearchRecentRemoved event,
    Emitter<SearchState> emit,
  ) async {
    final recent = await _recents.remove(event.query);
    if (isClosed) return;
    emit(state.copyWith(recent: recent));
  }

  Future<void> _onRecentsCleared(
    SearchRecentsCleared event,
    Emitter<SearchState> emit,
  ) async {
    final recent = await _recents.clear();
    if (isClosed) return;
    emit(state.copyWith(recent: recent));
  }

  Future<Result<SearchEntity>> _fetch(SearchCriteria criteria, int page) {
    if (criteria.text.isNotEmpty) {
      return _searchUseCase(criteria.text, page: page);
    }
    return _genreUseCase.callByGenre(criteria.genre, page: page);
  }

  @override
  Future<void> close() {
    _debouncer.dispose();
    _suggestTimer?.cancel();
    return super.close();
  }
}
