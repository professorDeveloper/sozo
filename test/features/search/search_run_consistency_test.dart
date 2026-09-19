// Two ways to run the same search must give the same search.
//
// Typing a query and waiting for the debounce goes through `_onQueryChanged`,
// which builds a criteria with no genre. Pressing the keyboard's Search key
// goes through `_onSubmitted`, which copied the EXISTING criteria — so with a
// filter chip on, the two did different things: the debounced path ran a text
// search, and the submitted path ran a text search too, but under a chip still
// claiming the results were filtered. `_fetch` takes whichever of the two is
// set and silently prefers the text, so the genre was never applied and never
// could be.
//
// And the suggestions behind "Did you mean" were never cleared on an empty
// answer, so they belonged to whatever query last had any.
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soplay/core/analytics/analytics.dart';
import 'package:soplay/core/content/content_mode.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/search/data/title_suggestion_service.dart';
import 'package:soplay/features/search/domain/entities/genre_entity.dart';
import 'package:soplay/features/search/domain/entities/search_entity.dart';
import 'package:soplay/features/search/domain/repositories/search_repository.dart';
import 'package:soplay/features/search/domain/usecases/genre_usecase.dart';
import 'package:soplay/features/search/domain/usecases/search_usecase.dart';
import 'package:soplay/features/search/presentation/blocs/search_bloc.dart';

/// Records which route each fetch took: a text search or a genre browse.
class _Recording implements SearchRepository {
  final calls = <String>[];

  SearchEntity _empty(String provider) =>
      SearchEntity(provider: provider, items: const [], page: 1, totalPages: 1);

  @override
  Future<Result<SearchEntity>> searchMovies(String query, {int page = 1}) async {
    calls.add('search:$query');
    return Success(_empty('fixture'));
  }

  @override
  Future<Result<SearchEntity>> getMoviesByGenre(String genre, {int page = 1}) async {
    calls.add('genre:$genre');
    return Success(_empty('fixture'));
  }

  @override
  Future<Result<List<GenreEntity>>> getGenres() async =>
      const Success(<GenreEntity>[]);
}

/// Answers with whatever the test has queued for the next query.
class _Suggestions implements TitleSuggestionService {
  List<String> next = const [];

  @override
  Future<List<String>> suggest(
    String query, {
    int limit = 8,
    ContentMode mode = ContentMode.video,
  }) async => next;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Hive implements HiveService {
  @override
  String getContentMode() => 'video';

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  late _Recording repo;
  late _Suggestions suggestions;

  setUp(() async {
    await getIt.reset();
    getIt.registerSingleton<HiveService>(_Hive());
    // The run handler reports the search funnel. Suppressed, so it records
    // nothing and needs no client.
    getIt.registerSingleton<Analytics>(Analytics(suppressed: () => true));
    repo = _Recording();
    suggestions = _Suggestions();
  });

  tearDown(() async => getIt.reset());

  SearchBloc bloc() => SearchBloc(
    searchUseCase: SearchUseCase(repository: repo),
    genreUseCase: GenreUseCase(repository: repo),
    suggestions: suggestions,
  );

  test('submitting with a genre active runs a plain text search', () async {
    // Not "runs a filtered search": text and genre genuinely do not compose on
    // this API. The bug was that the criteria kept saying they did, so the
    // screen showed an active filter chip over unfiltered results.
    final b = bloc();
    addTearDown(b.close);

    b.add(const SearchGenreSelected('action'));
    await b.stream.firstWhere((s) => s.status == SearchStatus.empty);
    expect(repo.calls, ['genre:action']);

    b.add(const SearchSubmitted('naruto'));
    await b.stream.firstWhere(
      (s) => s.criteria.text == 'naruto' && s.status != SearchStatus.loading,
    );

    expect(repo.calls, ['genre:action', 'search:naruto']);
    expect(
      b.state.criteria.genre,
      isEmpty,
      reason:
          'the chip stayed on over results it had no part in producing — and '
          'typing the same query instead of pressing Search cleared it',
    );
  });

  test('and it matches what the debounced path does', () async {
    // The two routes are the whole point: they must agree.
    final b = bloc();
    addTearDown(b.close);
    b.add(const SearchGenreSelected('action'));
    await b.stream.firstWhere((s) => s.status == SearchStatus.empty);

    b.add(const SearchQueryChanged('naruto'));
    await b.stream.firstWhere(
      (s) => s.criteria.text == 'naruto' && s.status != SearchStatus.loading,
    );

    expect(b.state.criteria.genre, isEmpty);
    expect(repo.calls.last, 'search:naruto');
  });

  test('a query with no suggestions clears the previous query\'s', () async {
    // The defect: `titles.isEmpty` returned without emitting, so the chips
    // under an unrelated search belonged to whatever query last had any.
    final b = bloc();
    addTearDown(b.close);

    suggestions.next = ['Naruto Shippuden'];
    b.add(const SearchQueryChanged('naru'));
    await b.stream.firstWhere((s) => s.suggestions.isNotEmpty);

    suggestions.next = const [];
    b.add(const SearchQueryChanged('zzzz'));
    await b.stream.firstWhere(
      (s) => s.criteria.text == 'zzzz' || s.suggestions.isEmpty,
    );
    // Past both debounces — suggestions at 250ms, the search at 450ms.
    await Future<void>.delayed(const Duration(milliseconds: 700));

    expect(
      b.state.suggestions,
      isEmpty,
      reason: '"Did you mean Naruto Shippuden?" under a search for zzzz',
    );
  });
}
