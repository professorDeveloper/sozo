import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:soplay/features/search/presentation/widgets/catalogue_discovery_sheet.dart';
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

class _Catalogue extends SearchRepository implements CatalogueSearchRepository {
  @override
  String? catalogueKind = 'tmdb';
  final calls = <(Map<String, String>, int)>[];
  @override
  Future<Result<List<GenreEntity>>> getGenres() async => const Success([]);
  @override
  Future<Result<List<GenreEntity>>> getDiscoveryGenres(String type) =>
      getGenres();
  @override
  Future<Result<SearchEntity>> discover(
    Map<String, String> filters, {
    int page = 1,
  }) async {
    calls.add((Map.of(filters), page));
    return Success(
      SearchEntity(
        provider: 'cat:tmdb',
        page: page,
        totalPages: 3,
        items: [
          MovieEntity(
            externalId: '$page',
            title: 'Title $page',
            description: '',
            slug: '$page',
            url: 'https://example.test/$page',
            provider: 'cat:tmdb',
            thumbnail: null,
            year: null,
            rating: 8,
            qualities: null,
            category: 'movie',
          ),
        ],
      ),
    );
  }

  @override
  Future<Result<SearchEntity>> getMoviesByGenre(
    String genre, {
    int page = 1,
  }) async => Success(
    SearchEntity(provider: 'cat:tmdb', items: [], page: 1, totalPages: 1),
  );
  @override
  Future<Result<SearchEntity>> searchMovies(String query, {int page = 1}) =>
      getMoviesByGenre(query);
}

class _Strings extends AssetLoader {
  const _Strings();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('assets/translations/en.json').readAsStringSync())
          as Map<String, dynamic>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  test(
    'discovery preserves every filter across pages and resets on catalogue switch',
    () async {
      final repo = _Catalogue();
      final bloc = SearchBloc(
        searchUseCase: SearchUseCase(repository: repo),
        genreUseCase: GenreUseCase(repository: repo),
      );
      addTearDown(bloc.close);
      const filters = {
        'type': 'tv',
        'rating': '8',
        'year': '2024',
        'sort': 'rating',
      };
      bloc.add(const SearchDiscoverySelected(filters));
      await bloc.stream.firstWhere((s) => s.status == SearchStatus.loaded);
      bloc.add(const SearchLoadMore());
      await bloc.stream.firstWhere((s) => s.page == 2 && !s.isLoadingMore);
      expect(repo.calls.map((c) => c.$2), [1, 2]);
      for (final call in repo.calls) {
        expect(call.$1, filters);
      }
      repo.catalogueKind = 'anilist';
      bloc.add(const SearchLoad());
      await bloc.stream.firstWhere((s) => s.status == SearchStatus.idle);
      expect(bloc.state.criteria.filters, isEmpty);
      expect(bloc.state.items, isEmpty);
    },
  );
  test(
    'clear removes discovery without making an empty genre request',
    () async {
      final repo = _Catalogue();
      final bloc = SearchBloc(
        searchUseCase: SearchUseCase(repository: repo),
        genreUseCase: GenreUseCase(repository: repo),
      );
      addTearDown(bloc.close);
      bloc.add(const SearchDiscoverySelected({'sort': 'rating'}));
      await bloc.stream.firstWhere((s) => s.status == SearchStatus.loaded);
      bloc.add(const SearchGenreSelected(''));
      await bloc.stream.firstWhere((s) => s.status == SearchStatus.idle);
      expect(bloc.state.criteria.isEmpty, isTrue);
      expect(repo.calls, hasLength(1));
    },
  );
  testWidgets(
    'rating selection remains visible and apply stays reachable on a small phone',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Map<String, String>? applied;
      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: const [Locale('en')],
          path: 'assets/translations',
          assetLoader: const _Strings(),
          saveLocale: false,
          child: Builder(
            builder: (context) => MaterialApp(
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: context.localizationDelegates,
              theme: ThemeData.dark(useMaterial3: true),
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    child: const Text('open'),
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => CatalogueDiscoverySheet(
                        kind: 'anilist',
                        genres: const [],
                        initial: const {},
                        loadGenres: (_) async => const Success([]),
                        onApply: (value) => applied = value,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('★ 8+'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '★ 8+'))
            .selected,
        isTrue,
      );
      expect(
        tester.getBottomRight(find.text('Show results')).dy,
        lessThan(640),
      );
      expect(tester.takeException(), isNull);
      final yearField = find.byKey(const ValueKey('year:null'));
      await tester.ensureVisible(yearField);
      await tester.tap(yearField);
      await tester.pumpAndSettle();
      final menuScroll = find.byType(Scrollable).last;
      expect(tester.getSize(menuScroll).height, lessThanOrEqualTo(640 * .4));
      await tester.scrollUntilVisible(
        find.text('2020'),
        120,
        scrollable: menuScroll,
      );
      await tester.tap(find.text('2020').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Show results'));
      await tester.pumpAndSettle();
      expect(applied, {'sort': 'popular', 'rating': '8', 'year': '2020'});
    },
  );
}
