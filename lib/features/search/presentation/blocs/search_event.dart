part of 'search_bloc.dart';

abstract class SearchEvent {
  const SearchEvent();
}

/// First mount and every provider switch: genres belong to the provider, so
/// they are dropped and refetched, and whatever is in the box is re-run.
class SearchLoad extends SearchEvent {
  const SearchLoad();
}

class SearchQueryChanged extends SearchEvent {
  const SearchQueryChanged(this.query);
  final String query;
}

/// The keyboard's Search key: run now, no debounce, no dedupe.
class SearchSubmitted extends SearchEvent {
  const SearchSubmitted(this.query);
  final String query;
}

/// Applies or clears the genre filter. Combines with whatever text is present.
class SearchGenreSelected extends SearchEvent {
  const SearchGenreSelected(this.genre);
  final String genre;
}

class SearchLoadMore extends SearchEvent {
  const SearchLoadMore();
}

/// Re-runs the operation that actually failed, not the genres call.
class SearchRetry extends SearchEvent {
  const SearchRetry();
}

class SearchRecentRemoved extends SearchEvent {
  const SearchRecentRemoved(this.query);
  final String query;
}

class SearchRecentsCleared extends SearchEvent {
  const SearchRecentsCleared();
}

class _SearchRun extends SearchEvent {
  const _SearchRun(this.criteria);
  final SearchCriteria criteria;
}

/// Suggestions for the query that was being typed have arrived.
///
/// Its own event rather than an await inside [SearchQueryChanged] because the
/// lookup outlives the keystroke that started it: by the time AniList answers,
/// two more letters have usually been typed, and the bloc has to be able to
/// drop an answer to a question nobody is asking any more.
class SearchSuggestionsUpdated extends SearchEvent {
  const SearchSuggestionsUpdated(this.query, this.suggestions);

  final String query;
  final List<String> suggestions;
}
