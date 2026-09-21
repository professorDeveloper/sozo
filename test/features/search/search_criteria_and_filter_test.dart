// Two things the search tab could not say: which filter is on, and — on a
// source with forty-one genres — where the button that applies one went.
//
// The filter sheet put its Apply and Clear row inside the same scroll view as
// the chips, so past about twenty genres the commit row sat below the fold of a
// sheet that gave no sign it scrolled. And once a genre WAS applied, nothing on
// the screen it changed named it: the state carries the source's slug, because
// that is what a browse request takes, and every screen that needed to name the
// filter printed the slug — "No results for 10759".
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soplay/features/home/domain/entities/movie.dart';
import 'package:soplay/features/search/domain/entities/genre_entity.dart';
import 'package:soplay/features/search/presentation/blocs/search_bloc.dart';
import 'package:soplay/features/search/presentation/widgets/search_filter_sheet.dart';
import 'package:soplay/features/search/presentation/widgets/search_state_views.dart';

/// The real en.json, so the copy under test is the copy that ships.
class _Translations extends AssetLoader {
  const _Translations();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('assets/translations/en.json').readAsStringSync())
          as Map<String, dynamic>;
}

List<GenreEntity> _genres(int n) => [
  for (var i = 0; i < n; i++)
    GenreEntity(
      provider: 'p',
      slug: 'genre-$i',
      url: '',
      image: '',
      name: 'Genre $i',
    ),
];

MovieEntity _movie(int i) => MovieEntity(
  externalId: '$i',
  title: 'Title $i',
  description: '',
  slug: 'title-$i',
  url: 'https://example.test/$i',
  provider: 'p',
  thumbnail: '',
  year: 2024,
  rating: null,
  qualities: const [],
  category: '',
);

Widget _app(Widget child) => EasyLocalization(
  supportedLocales: const [Locale('en')],
  startLocale: const Locale('en'),
  path: 'assets/translations',
  assetLoader: const _Translations(),
  saveLocale: false,
  child: Builder(
    builder: (context) => MaterialApp(
      locale: context.locale,
      supportedLocales: context.supportedLocales,
      localizationsDelegates: context.localizationDelegates,
      home: child,
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  /// A phone-sized window, because the defect is about the fold.
  Future<void> phone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  group('the filter sheet keeps its commit row on screen', () {
    /// Opens the sheet the way `search_page` opens it: a scroll-controlled
    /// modal, which is the shape that let the buttons fall off the bottom.
    Future<SearchFilterSelection?> open(
      WidgetTester tester, {
      required int count,
      String selected = '',
    }) async {
      SearchFilterSelection? applied;
      await phone(tester);
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => SearchFilterSheet(
                    initialSelection: SearchFilterSelection(genre: selected),
                    genres: _genres(count),
                    onApply: (s) => applied = s,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      // EasyLocalization loads its bundle before it builds anything, so the
      // first frame is a placeholder and there is nothing to tap yet.
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return applied;
    }

    /// The sheet's own bottom, not the window's: a scroll-controlled sheet is
    /// allowed to be shorter than the screen, and what matters is that the row
    /// is inside whatever height it took.
    void expectCommitRowVisible(WidgetTester tester) {
      final apply = tester.getRect(find.text('search.apply'.tr()));
      final clear = tester.getRect(find.text('search.clear_filter'.tr()));
      expect(apply.bottom, lessThanOrEqualTo(640));
      expect(apply.top, greaterThanOrEqualTo(0));
      expect(clear.bottom, lessThanOrEqualTo(640));
    }

    testWidgets('at forty-one genres', (tester) async {
      await open(tester, count: 41);
      expectCommitRowVisible(tester);
    });

    testWidgets('and at three', (tester) async {
      await open(tester, count: 3);
      expectCommitRowVisible(tester);
      // Under the threshold there is nothing to narrow, so no field for it.
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('typing narrows the chips', (tester) async {
      await open(tester, count: 41);
      expect(find.byType(TextField), findsOneWidget);

      // '17' rather than 'Genre 17': the field's own contents are text on the
      // screen too, and matching the full label would find both.
      await tester.enterText(find.byType(TextField), '17');
      await tester.pumpAndSettle();

      expect(find.text('Genre 17'), findsOneWidget);
      expect(find.text('Genre 18'), findsNothing);
      expect(find.text('Genre 1'), findsNothing);
      expectCommitRowVisible(tester);
    });

    testWidgets('and never narrows away the chip that is on', (tester) async {
      // The whole point of pinning it: "Genre 3" does not match "17", and
      // without the pin the sheet would stop showing what is currently applied
      // at exactly the moment somebody is changing it.
      await open(tester, count: 41, selected: 'genre-3');

      await tester.enterText(find.byType(TextField), '17');
      await tester.pumpAndSettle();

      expect(find.text('Genre 3'), findsOneWidget);
      expect(find.text('Genre 17'), findsOneWidget);

      final pinned = tester.getRect(find.text('Genre 3'));
      final other = tester.getRect(find.text('Genre 17'));
      expect(pinned.left, lessThan(other.left));
    });
  });

  group('the state names the genre rather than its slug', () {
    const state = SearchState(
      criteria: SearchCriteria(genre: 'action-adventure'),
      status: SearchStatus.empty,
    );

    test('resolved from the genre list when it is there', () {
      final withNames = state.copyWith(
        genres: [
          GenreEntity(
            provider: 'p',
            slug: 'action-adventure',
            url: '',
            image: '',
            name: 'Action & Adventure',
          ),
        ],
      );
      expect(withNames.genreName, 'Action & Adventure');
      expect(withNames.criteriaLabel, 'Action & Adventure');
    });

    test('humanised when the list has not arrived', () {
      // A genre can be browsed from a deep link or survive a source switch, so
      // the names are not always in hand. "Action Adventure" is not the
      // source's own wording, but it is words.
      expect(state.genreName, 'Action Adventure');
    });

    test('and the text query wins when there is one', () {
      expect(
        state
            .copyWith(criteria: const SearchCriteria(text: 'naruto'))
            .genreName,
        '',
      );
      expect(
        state
            .copyWith(criteria: const SearchCriteria(text: 'naruto'))
            .criteriaLabel,
        'naruto',
      );
    });

    test('and nothing is named when nothing is selected', () {
      expect(const SearchState().genreName, '');
      expect(const SearchState().criteriaLabel, '');
    });
  });

  group('the results say what they are', () {
    Future<List<String>> pumpResults(
      WidgetTester tester,
      SearchState state,
    ) async {
      final cleared = <String>[];
      await phone(tester);
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: SearchContentView(
              state: state,
              scrollController: ScrollController(),
              topPad: 0,
              bottomPad: 0,
              onRetry: () {},
              onRetryMore: () {},
              onRefresh: () async {},
              onSuggestion: (_) {},
              onGenre: cleared.add,
              onRemoveRecent: (_) {},
              onClearRecents: () {},
              onTryAllSources: () {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      return cleared;
    }

    testWidgets('a count, and the genre with a way to drop it', (tester) async {
      final cleared = await pumpResults(
        tester,
        SearchState(
          criteria: const SearchCriteria(genre: 'genre-2'),
          status: SearchStatus.loaded,
          items: [for (var i = 0; i < 4; i++) _movie(i)],
          genres: _genres(5),
        ),
      );

      expect(find.text('search.results_n'.tr(args: ['4'])), findsOneWidget);
      expect(find.text('Genre 2'), findsOneWidget);

      await tester.tap(find.text('Genre 2'));
      await tester.pump();

      // An empty genre is how the bloc is told to go back to the landing.
      expect(cleared, ['']);
    });

    testWidgets('and says so when the count is only so far', (tester) async {
      await pumpResults(
        tester,
        SearchState(
          status: SearchStatus.loaded,
          criteria: const SearchCriteria(text: 'naruto'),
          items: [for (var i = 0; i < 4; i++) _movie(i)],
          page: 1,
          totalPages: 6,
        ),
      );

      expect(
        find.text('search.results_so_far'.tr(args: ['4'])),
        findsOneWidget,
      );
      // No filter is on, so there is no pill to remove.
      expect(find.byIcon(Icons.filter_alt_rounded), findsNothing);
    });

    testWidgets('an empty genre browse names itself and offers a way out', (
      tester,
    ) async {
      final cleared = await pumpResults(
        tester,
        SearchState(
          criteria: const SearchCriteria(genre: 'genre-2'),
          status: SearchStatus.empty,
          genres: _genres(5),
        ),
      );

      expect(
        find.text('search.no_results_for'.tr(namedArgs: {'query': 'Genre 2'})),
        findsOneWidget,
      );

      // The offers above this one are all text-search offers, so a genre that
      // returns nothing used to be an empty page with an icon on it.
      await tester.tap(find.text('search.clear_genre'.tr()));
      await tester.pump();
      expect(cleared, ['']);
    });
  });
}
