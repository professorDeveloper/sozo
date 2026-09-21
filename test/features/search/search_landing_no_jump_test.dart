// The search tab used to land twice.
//
// The first frame drew no source rail at all — `_SourceRail` returned an empty
// box while the home was in flight — so the genres started at the top of the
// screen. A second later the posters arrived and pushed everything down by a
// quarter of a screen, under a thumb that was already reaching for a genre. The
// genre skeleton did the same thing again on its own account: two columns at
// 1.85 with ten points of spacing standing in for three columns at 1.5 with
// eight, so the section changed column count, tile shape and height the moment
// the genres landed.
//
// Both are measured here rather than described: the skeleton's height is
// compared against the height of the thing that replaces it.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/home/domain/entities/home_data_entity.dart';
import 'package:soplay/features/home/domain/entities/home_section_entity.dart';
import 'package:soplay/features/home/domain/entities/movie.dart';
import 'package:soplay/features/home/domain/entities/view_all.dart';
import 'package:soplay/features/home/domain/repositories/home_repository.dart';
import 'package:soplay/features/home/domain/usecase/home_usecase.dart';
import 'package:soplay/features/home/presentation/bloc/home/home_bloc.dart';
import 'package:soplay/features/home/presentation/bloc/home/home_event.dart';
import 'package:soplay/features/home/presentation/widgets/home_shared_widgets.dart';
import 'package:soplay/features/search/domain/entities/genre_entity.dart';
import 'package:soplay/features/search/presentation/widgets/genre_tile.dart';
import 'package:soplay/core/extractor/provider_manager.dart';
import 'package:soplay/core/js/provider_registry.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/profile/domain/usecases/get_providers_usecase.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_bloc.dart';
import 'package:soplay/features/search/presentation/widgets/search_landing.dart';

class _Translations extends AssetLoader {
  const _Translations();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('assets/translations/en.json').readAsStringSync())
          as Map<String, dynamic>;
}

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

/// A home that answers when told to, so the frame before the answer can be
/// measured against the frame after it.
class _HeldHome implements HomeRepository {
  _HeldHome({this.fail = false});

  final bool fail;
  final _gate = Completer<void>();

  void release() => _gate.complete();

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);

  @override
  Future<Result<HomeDataEntity>> loadHome() async {
    await _gate.future;
    if (fail) return Failure(Exception('this source has no home'));
    return Success(
      HomeDataEntity(
        provider: 'p',
        banner: const [],
        categories: const [],
        genres: const [],
        sections: [
          HomeSectionEntity(
            key: 'trending',
            label: 'Trending now',
            viewAll: ViewAllEntity(slug: 'trending', type: 'section'),
            items: [for (var i = 0; i < 8; i++) _movie(i)],
          ),
        ],
      ),
    );
  }

  @override
  Future<Result<List<GenreEntity>>> loadGenres() async => const Success([]);
}

/// The rail's heading names the source, which it looks up in the provider list.
/// None of that is what these tests are about, so the bloc is built and never
/// asked anything: with no `ProviderLoad` there is no name, and the heading
/// falls back to the app's own sentence.
class _Fake {
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

class _UseCase extends _Fake implements GetProvidersUseCase {}

class _Hive extends _Fake implements HiveService {}

class _Manager extends _Fake implements ProviderManager {}

class _Registry extends _Fake implements ProviderRegistry {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  Future<HomeBloc> pump(
    WidgetTester tester, {
    required HomeRepository home,
    List<GenreEntity> genres = const [],
    bool genresLoading = false,
  }) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final bloc = HomeBloc(useCase: HomeUseCase(home));
    addTearDown(bloc.close);
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
            // The skeletons shimmer on an infinite repeat, so `pumpAndSettle`
            // can never settle while one is on screen.
            builder: (inner, child) => MediaQuery(
              data: MediaQuery.of(inner).copyWith(disableAnimations: true),
              child: child!,
            ),
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            home: MultiBlocProvider(
              providers: [
                BlocProvider<HomeBloc>.value(value: bloc),
                BlocProvider<ProviderBloc>(
                  create: (_) => ProviderBloc(
                    useCase: _UseCase(),
                    hiveService: _Hive(),
                    providerManager: _Manager(),
                    providerRegistry: _Registry(),
                  ),
                ),
              ],
              child: Scaffold(
                body: Builder(
                  builder: (inner) => CustomScrollView(
                    slivers: searchLandingSlivers(
                      inner,
                      recent: const ['bleach'],
                      genres: genres,
                      genresLoading: genresLoading,
                      genresFailed: false,
                      onSuggestion: (_) {},
                      onGenre: (_) {},
                      onRemoveRecent: (_) {},
                      onClearRecents: () {},
                      onRetryGenres: () {},
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
    return bloc;
  }

  /// Where the genre section starts, which is what a jump above it moves.
  double genresTop(WidgetTester tester) =>
      tester.getTopLeft(find.text('search.categories'.tr())).dy;

  testWidgets('the rail holds its space while the home loads', (tester) async {
    final home = _HeldHome();
    final bloc = await pump(
      tester,
      home: home,
      genres: [
        GenreEntity(
          provider: 'p',
          slug: 'action',
          url: '',
          image: '',
          name: 'Action',
        ),
      ],
    );
    bloc.add(HomeLoad());
    await tester.pump();

    final before = genresTop(tester);

    home.release();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // The posters are in, and the heading below them has not moved. A point of
    // slack for the heading's own text metrics; the defect was a quarter of a
    // screen.
    expect(
      find.text('Trending now'),
      findsNothing,
      reason: 'app heading, not the rail label',
    );
    expect(genresTop(tester), closeTo(before, 1.0));
  });

  testWidgets('and gives the space back when the home fails', (tester) async {
    final home = _HeldHome(fail: true);
    final bloc = await pump(
      tester,
      home: home,
      genres: [
        GenreEntity(
          provider: 'p',
          slug: 'action',
          url: '',
          image: '',
          name: 'Action',
        ),
      ],
    );
    bloc.add(HomeLoad());
    await tester.pump();
    final waiting = genresTop(tester);

    home.release();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // A failed home has no rail to show, so the reserved space is released —
    // once, before anything has been read. The old `buildWhen` could not see
    // this transition at all and left the skeleton shimmering for good.
    expect(genresTop(tester), lessThan(waiting));
  });

  testWidgets('the streaming services have a way in', (tester) async {
    // They had none. The page, its browse screen and its translations were all
    // built and routed, and then the rail that reached them came off Home and
    // nothing replaced it — so the whole feature was unreachable from any
    // screen in the app, which from the outside is indistinguishable from
    // having deleted it.
    await pump(tester, home: _HeldHome());

    expect(find.text('watch.services_title'.tr()), findsOneWidget);
    expect(find.text('watch.services_entry_hint'.tr()), findsOneWidget);
  });

  testWidgets('the genre skeleton is the genre grid, greyed out', (
    tester,
  ) async {
    // Both trees hold the same unreleased home, so the rail above the genres is
    // the same height in each and the grid below it starts in the same place.
    await pump(tester, home: _HeldHome(), genresLoading: true);
    final placeholder = tester.getRect(
      find
          .descendant(
            of: find.byType(GridView),
            matching: find.byType(HomeSkeletonBox),
          )
          .first,
    );

    await pump(
      tester,
      home: _HeldHome(),
      genres: [
        for (var i = 0; i < 9; i++)
          GenreEntity(
            provider: 'p',
            slug: 'g$i',
            url: '',
            image: '',
            name: 'Genre $i',
          ),
      ],
    );
    final real = tester.getRect(find.byType(GenreTile).first);

    // Same size and same position: three columns at 1.5 either way, under a
    // heading that occupies the line the real heading occupies. It used to be
    // two columns at 1.85, so the first tile was half again as wide and the
    // whole section a different height.
    expect(placeholder.left, closeTo(real.left, 1.0));
    expect(placeholder.top, closeTo(real.top, 1.0));
    expect(placeholder.width, closeTo(real.width, 1.0));
    expect(placeholder.height, closeTo(real.height, 1.0));
  });
}
