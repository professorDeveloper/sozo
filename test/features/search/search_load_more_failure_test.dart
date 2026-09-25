import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/home/domain/entities/movie.dart';
import 'package:soplay/features/search/domain/entities/genre_entity.dart';
import 'package:soplay/features/search/domain/entities/search_entity.dart';
import 'package:soplay/features/search/domain/repositories/search_repository.dart';
import 'package:soplay/features/search/domain/usecases/genre_usecase.dart';
import 'package:soplay/features/search/domain/usecases/search_usecase.dart';
import 'package:soplay/features/search/presentation/blocs/search_bloc.dart';
import 'package:soplay/features/sources/domain/source_failure.dart';

/// A repository whose pages can be made to fail one at a time.
///
/// Browsing a genre rather than searching text, because the text path writes a
/// recent query and reports to analytics, and neither is what is under test.
class _StagedRepository implements SearchRepository {
  _StagedRepository({required this.failOnPage});

  /// Mutable so a test can let a dropped connection come back, which is the
  /// usual way a failed page ends.
  int failOnPage;
  final List<int> requested = [];

  @override
  Future<Result<SearchEntity>> getMoviesByGenre(String genre, {int page = 1}) {
    requested.add(page);
    if (page == failOnPage) {
      return Future.value(
        Failure(Exception('SocketException: Failed host lookup')),
      );
    }
    return Future.value(
      Success(
        SearchEntity(
          provider: 'fixture',
          page: page,
          totalPages: 5,
          items: [
            for (var i = 0; i < 3; i++)
              MovieEntity(
                externalId: '$page-$i',
                title: 'p$page #$i',
                description: '',
                slug: 'p$page-$i',
                url: 'https://example.test/$page/$i',
                provider: 'fixture',
                thumbnail: null,
                year: null,
                rating: null,
                qualities: null,
                category: 'movie',
              ),
          ],
        ),
      ),
    );
  }

  @override
  Future<Result<List<GenreEntity>>> getGenres() async =>
      const Success(<GenreEntity>[]);

  @override
  Future<Result<SearchEntity>> searchMovies(String query, {int page = 1}) =>
      getMoviesByGenre(query, page: page);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  SearchBloc blocOver(_StagedRepository repo) => SearchBloc(
    searchUseCase: SearchUseCase(repository: repo),
    genreUseCase: GenreUseCase(repository: repo),
  );

  /// Drives the bloc to a loaded first page, then asks for the second.
  Future<(SearchBloc, _StagedRepository)> loadedThenMore({
    required int failOnPage,
  }) async {
    final repo = _StagedRepository(failOnPage: failOnPage);
    final bloc = blocOver(repo);
    bloc.add(const SearchGenreSelected('action'));
    await bloc.stream.firstWhere((s) => s.status == SearchStatus.loaded);
    bloc.add(const SearchLoadMore());
    await bloc.stream.firstWhere((s) => !s.isLoadingMore);
    return (bloc, repo);
  }

  group('a next page that does not arrive', () {
    test('says why, instead of leaving a spinner that just vanishes', () async {
      // The defect. `_onLoadMore` emitted `isLoadingMore: false` and returned.
      // The reader saw a spinner appear, disappear, and no new rows — with no
      // way to tell a source that had broken from a list that had ended.
      final (bloc, _) = await loadedThenMore(failOnPage: 2);
      addTearDown(bloc.close);

      expect(bloc.state.loadMoreFailure, isNotNull);
      expect(
        bloc.state.loadMoreFailure!.kind,
        SourceFailureKind.unreachable,
        reason: 'a host lookup failure is the reader being offline',
      );
    });

    test('keeps the results that did arrive', () async {
      // The whole reason this is not the ordinary error path: page one is fine
      // and the reader is reading it.
      final (bloc, _) = await loadedThenMore(failOnPage: 2);
      addTearDown(bloc.close);

      expect(bloc.state.items, hasLength(3));
      expect(bloc.state.status, SearchStatus.loaded);
      expect(
        bloc.state.failure,
        isNull,
        reason: 'the full-page error view must not take over the grid',
      );
    });

    test('does not keep asking on every pixel of scroll', () async {
      // The scroll listener fires SearchLoadMore on every frame within 300px
      // of the bottom, and nothing about a failure stopped it: offline, one
      // flick of the thumb became an unbounded stream of failing requests.
      final (bloc, repo) = await loadedThenMore(failOnPage: 2);
      addTearDown(bloc.close);
      final afterFirstFailure = repo.requested.length;

      for (var i = 0; i < 20; i++) {
        bloc.add(const SearchLoadMore());
      }
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(
        repo.requested.length,
        afterFirstFailure,
        reason:
            'scrolling at the bottom of a failed page asked the dead source '
            '${repo.requested.length - afterFirstFailure} more times',
      );
    });

    test('but a deliberate retry does ask again', () async {
      // The other half: refusing the automatic ones must not make the footer's
      // own control dead too.
      final (bloc, repo) = await loadedThenMore(failOnPage: 2);
      addTearDown(bloc.close);
      final before = repo.requested.length;

      bloc.add(const SearchLoadMore(retry: true));
      await bloc.stream.firstWhere((s) => !s.isLoadingMore);

      expect(repo.requested.length, greaterThan(before));
    });

    test('and a retry that works clears the failure and appends', () async {
      final repo = _StagedRepository(failOnPage: 2);
      final bloc = blocOver(repo);
      addTearDown(bloc.close);
      bloc.add(const SearchGenreSelected('action'));
      await bloc.stream.firstWhere((s) => s.status == SearchStatus.loaded);
      bloc.add(const SearchLoadMore());
      await bloc.stream.firstWhere((s) => s.loadMoreFailure != null);

      // The source comes back — the commonest case, since the usual cause is a
      // connection that dropped for a moment.
      repo.failOnPage = -1;
      bloc.add(const SearchLoadMore(retry: true));
      await bloc.stream.firstWhere((s) => !s.isLoadingMore && s.page == 2);

      expect(bloc.state.loadMoreFailure, isNull);
      expect(bloc.state.items, hasLength(6));
    });

    test('a new search starts without the old failure', () async {
      final (bloc, _) = await loadedThenMore(failOnPage: 2);
      addTearDown(bloc.close);
      expect(bloc.state.loadMoreFailure, isNotNull);

      bloc.add(const SearchGenreSelected('comedy'));
      await bloc.stream.firstWhere((s) => s.status == SearchStatus.loaded);

      expect(
        bloc.state.loadMoreFailure,
        isNull,
        reason:
            'a footer left saying the previous genre was unreachable would '
            'stop the new one ever paging',
      );
    });
  });
}
