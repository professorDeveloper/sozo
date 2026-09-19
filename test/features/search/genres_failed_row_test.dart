// A genre call that fails has to say so.
//
// `SearchState.genresFailed` was computed in the bloc, carried on the state and
// compared in `props` — and read by nothing. So when the genre call failed the
// Categories section was simply absent: on a device with recent searches the
// only way to browse this source disappeared, with no reason shown and no way
// to ask again. On a device with none, the fallback empty state hid it too.
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/home/domain/entities/home_data_entity.dart';
import 'package:soplay/features/home/domain/repositories/home_repository.dart';
import 'package:soplay/features/home/domain/usecase/home_usecase.dart';
import 'package:soplay/features/home/presentation/bloc/home/home_bloc.dart';
import 'package:soplay/features/search/domain/entities/genre_entity.dart';
import 'package:soplay/features/search/presentation/widgets/search_landing.dart';

/// The landing screen carries a source rail that reads the home catalogue.
/// It is not what these tests are about, so it is given a repository that
/// answers nothing and stays out of the way.
class _SilentHome implements HomeRepository {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);

  @override
  Future<Result<HomeDataEntity>> loadHome() async =>
      Failure(Exception('not part of this test'));

  @override
  Future<Result<List<GenreEntity>>> loadGenres() async => const Success([]);
}

/// The real en.json, so the copy under test is the copy that ships.
class _Translations extends AssetLoader {
  const _Translations();
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

  var retries = 0;

  setUp(() => retries = 0);

  /// Pumps the idle landing screen in the state the arguments describe.
  Future<void> pumpLanding(
    WidgetTester tester, {
    required List<GenreEntity> genres,
    required bool genresLoading,
    required bool genresFailed,
    List<String> recent = const [],
  }) async {
    await tester.pumpWidget(
      EasyLocalization(
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
            home: BlocProvider<HomeBloc>(
              create: (_) => HomeBloc(useCase: HomeUseCase(_SilentHome())),
              child: Scaffold(
                body: Builder(
                  builder: (inner) => CustomScrollView(
                    slivers: searchLandingSlivers(
                      inner,
                      recent: recent,
                      genres: genres,
                      genresLoading: genresLoading,
                      genresFailed: genresFailed,
                      onSuggestion: (_) {},
                      onGenre: (_) {},
                      onRemoveRecent: (_) {},
                      onClearRecents: () {},
                      onRetryGenres: () => retries++,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// The copy is looked up rather than spelled out, so a reworded string does
  /// not become a failing test.
  String failedCopy() => 'search.categories_failed'.tr();

  testWidgets('a failed genre call is reported, not hidden', (tester) async {
    await pumpLanding(
      tester,
      genres: const [],
      genresLoading: false,
      genresFailed: true,
      // With a recent search present, the old code fell through every branch
      // and rendered nothing at all — the worst version of the defect, because
      // the screen still looked complete.
      recent: const ['bleach'],
    );

    expect(find.text(failedCopy()), findsOneWidget);
  });

  testWidgets('and offers a way to ask again', (tester) async {
    await pumpLanding(
      tester,
      genres: const [],
      genresLoading: false,
      genresFailed: true,
    );

    await tester.tap(find.text('general.retry'.tr()));
    await tester.pump();

    expect(retries, 1);
  });

  testWidgets('says nothing while the call is still in flight', (tester) async {
    // The skeleton owns this frame. A failure notice over a request that has
    // not come back yet is the complaint that started this whole audit.
    await pumpLanding(
      tester,
      genres: const [],
      genresLoading: true,
      genresFailed: false,
    );

    expect(find.text(failedCopy()), findsNothing);
  });

  testWidgets('and nothing when the genres arrived', (tester) async {
    await pumpLanding(
      tester,
      genres: [
        GenreEntity(
          provider: 'src',
          slug: 'action',
          image: '',
          url: '',
          name: 'Action',
        ),
      ],
      genresLoading: false,
      genresFailed: false,
    );

    expect(find.text(failedCopy()), findsNothing);
    expect(find.text('Action'), findsOneWidget);
  });

  testWidgets('a stale flag does not hide genres that did load', (
    tester,
  ) async {
    // Defensive: the grid wins whenever there is something to draw, so a flag
    // left over from an earlier attempt cannot replace real content.
    await pumpLanding(
      tester,
      genres: [
        GenreEntity(
          provider: 'src',
          slug: 'action',
          image: '',
          url: '',
          name: 'Action',
        ),
      ],
      genresLoading: false,
      genresFailed: true,
    );

    expect(find.text(failedCopy()), findsNothing);
    expect(find.text('Action'), findsOneWidget);
  });
}
