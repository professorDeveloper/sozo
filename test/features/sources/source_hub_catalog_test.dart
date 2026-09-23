// Regression tests for source selection and installation flows.
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/extractor/provider_manager.dart';
import 'package:soplay/core/js/provider_registry.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/extensions/data/catalog_repository.dart';
import 'package:soplay/features/extensions/data/mangayomi_bridge.dart';
import 'package:soplay/features/extensions/data/mangayomi_repo_store.dart';
import 'package:soplay/features/extensions/data/mangayomi_runtime.dart';
import 'package:soplay/features/extensions/domain/entities/catalog_source_entity.dart';
import 'package:soplay/features/extensions/domain/entities/extension_repo_entity.dart';
import 'package:soplay/features/extensions/presentation/pages/source_catalog_page.dart';
import 'package:soplay/features/profile/domain/entities/provider_entity.dart';
import 'package:soplay/features/profile/domain/entities/providers_snapshot.dart';
import 'package:soplay/features/profile/domain/usecases/get_providers_usecase.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_bloc.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_event.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_state.dart';
import 'package:soplay/features/sources/presentation/pages/sources_hub_page.dart';

class _Translations extends AssetLoader {
  const _Translations();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('assets/translations/en.json').readAsStringSync())
          as Map<String, dynamic>;
}

class _Hive implements HiveService {
  @override
  String getContentMode() => 'video';
  @override
  Future<void> setContentMode(String mode) async {}
  @override
  List<String> getProviderLanguages() => [];
  @override
  bool get showNsfwMangaSources => false;
  @override
  bool get showAdultContent => false;
  @override
  String getCurrentProvider() => 'my:123';
  @override
  String getPreOutageProvider() => '';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UseCase implements GetProvidersUseCase {
  @override
  Future<Result<ProvidersSnapshot>> call() async =>
      const Success(ProvidersSnapshot(providers: [], fromCache: false));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Manager implements ProviderManager {
  @override
  void updateProviders(List<ProviderEntity> providers) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Registry implements ProviderRegistry {
  @override
  void invalidate() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Bridge implements MangayomiBridge {
  @override
  List<Map<String, dynamic>> listProviders({bool includeNsfw = false}) => [
    {
      'id': 'my:123',
      'name': 'French Novel',
      'lang': 'fr',
      'baseUrl': 'https://fixture.invalid',
    },
  ];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Providers extends Cubit<ProviderState> implements ProviderBloc {
  _Providers(super.initialState);
  final events = <ProviderEvent>[];
  @override
  void add(ProviderEvent event) => events.add(event);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Store extends MangayomiRepoStore {
  _Store() : super(dio: Dio());
  int installs = 0;
  @override
  Future<Map<String, int>> addRepo(String url) async {
    installs++;
    return {'added': 1, 'total': 1, 'skippedDart': 0};
  }
}

class _Catalog extends CatalogRepository {
  _Catalog() : super(dio: Dio());
  bool failMore = false;
  bool failFacets = false;
  final pages = <int>[];
  @override
  Future<CatalogPage> sources({
    List<String> languages = const [],
    ExtensionRepoKind? kind,
    CatalogItemType? itemType,
    String query = '',
    bool runnableOnly = false,
    bool nsfw = false,
    int page = 1,
    int limit = 50,
  }) async {
    pages.add(page);
    if (page > 1 && failMore) throw Exception('page request offline');
    return CatalogPage(
      items: List.generate(
        failMore ? 30 : 1,
        (i) => CatalogSourceEntity(
          id: 'source-$i',
          kind: ExtensionRepoKind.mangayomi,
          name: 'Readable Novel $i',
          itemType: CatalogItemType.novel,
          repoUrl: 'https://fixture.invalid/novel_index.json',
          repoName: 'Fixture',
        ),
      ),
      page: page,
      totalPages: failMore ? 2 : 1,
      total: failMore ? 60 : 1,
    );
  }

  @override
  Future<List<CatalogLanguage>> languages({
    ExtensionRepoKind? kind,
    CatalogItemType? itemType,
    bool runnableOnly = false,
    bool nsfw = false,
  }) async {
    if (failFacets) throw Exception('language facets unavailable');
    return [];
  }
}

ProviderEntity provider(String id, String name) => ProviderEntity(
  id: id,
  name: name,
  image: '',
  url: '',
  description: '',
  domains: [],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  setUp(() async {
    await getIt.reset();
    getIt.registerSingleton<HiveService>(_Hive());
    // The host is not under test. Without this these run one way on a Mac and
    // another on the Linux CI runner, where the JS runtime reports itself
    // unavailable and the extension paths below are never entered at all.
    MangayomiRuntime.debugSupportedSet = true;
  });
  tearDown(() async {
    MangayomiRuntime.debugSupportedSet = null;
    await getIt.reset();
  });

  Future<void> pump(WidgetTester tester, Widget child, _Providers bloc) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en')],
        startLocale: const Locale('en'),
        path: 'assets/translations',
        assetLoader: const _Translations(),
        saveLocale: false,
        child: Builder(
          builder: (context) => BlocProvider<ProviderBloc>.value(
            value: bloc,
            child: MaterialApp(
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: context.localizationDelegates,
              home: child,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('the header stays put while the list under it scrolls', (
    tester,
  ) async {
    // This used to assert the opposite mechanic: search scrolled away and the
    // category chips rose to sit under the tabs, because everything lived in
    // one scroll view with the app bar. That is the design that had no
    // TabBarView at all — swiping did nothing and the chips slid out of line
    // with the tabs they describe. Search, language and chips are a fixed
    // header now, so the contract is that they do not move.
    final bloc = _Providers(
      ProviderLoaded(
        providers: [
          for (var i = 0; i < 35; i++) provider('cs:source$i', 'Source $i'),
          provider('ay:fixture', 'Another source'),
        ],
        currentProviderId: 'cs:source0',
      ),
    );
    addTearDown(bloc.close);
    await pump(tester, const SourcesHubPage(), bloc);
    expect(find.byType(FlexibleSpaceBar), findsNothing);
    final tabs = find.byType(TabBar);
    final categories = find.text('All · 36');
    final tabsTop = tester.getTopLeft(tabs).dy;
    final categoriesTop = tester.getTopLeft(categories).dy;
    expect(categoriesTop, greaterThan(tester.getBottomLeft(tabs).dy));

    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -480),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(tester.getTopLeft(tabs).dy, closeTo(tabsTop, 1));
    expect(tester.getTopLeft(categories).dy, closeTo(categoriesTop, 1));
  });

  testWidgets('HUB-01 Manga tab must replace video sources immediately', (
    tester,
  ) async {
    final bloc = _Providers(
      ProviderLoaded(
        providers: [
          provider('cs:VideoFixture', 'Video Fixture'),
          provider('mn:123', 'Manga Fixture'),
        ],
        currentProviderId: 'cs:VideoFixture',
      ),
    );
    addTearDown(bloc.close);
    await pump(tester, const SourcesHubPage(), bloc);
    expect(find.text('Video Fixture'), findsOneWidget);
    final tab = find.descendant(
      of: find.byType(TabBar),
      matching: find.text('Manga'),
    );
    expect(tab, findsOneWidget);
    await tester.tap(tab);
    await tester.pumpAndSettle();
    expect(
      find.text('Manga Fixture'),
      findsOneWidget,
      reason:
          'Changing tabs must rebuild the body without typing or another Bloc event.',
    );
    expect(find.text('Video Fixture'), findsNothing);
  });

  test(
    'OFFLINE-01 Installed JS novel must remain usable during Sozo backend outage',
    () {
      final source = provider('my:local-novel', 'Local JS Novel');
      final state = ProviderLoaded(
        providers: [source],
        currentProviderId: source.id,
        offline: true,
      );
      expect(
        state.isUsable(source),
        isTrue,
        reason:
            'Mangayomi downloads/executes directly and does not require the Sozo API.',
      );
      expect(state.usableProviders, contains(source));
    },
  );

  test(
    'LANG-01 Native/JS provider language must survive ProviderBloc mapping',
    () async {
      getIt.registerSingleton<MangayomiBridge>(_Bridge());
      final bloc = ProviderBloc(
        useCase: _UseCase(),
        hiveService: getIt<HiveService>(),
        providerManager: _Manager(),
        providerRegistry: _Registry(),
      );
      addTearDown(bloc.close);
      final loaded = bloc.stream.firstWhere((s) => s is ProviderLoaded);
      bloc.add(const ProviderLoad());
      // Ten seconds, not two. The bound is here to fail a bloc that never
      // emits, not to time a CI runner — and two seconds was close enough to
      // the real thing that a loaded shared runner tripped it.
      final state =
          await loaded.timeout(const Duration(seconds: 10)) as ProviderLoaded;
      expect(state.providers.single.id, 'my:123');
      expect(
        state.providers.single.lang,
        'fr',
        reason:
            'An extension already reports its language; picker must not lose it.',
      );
    },
  );

  testWidgets(
    'CAT-01 Successful repo installation must notify provider registry',
    (tester) async {
      final catalog = _Catalog();
      final store = _Store();
      getIt.registerSingleton<CatalogRepository>(catalog);
      getIt.registerSingleton<MangayomiRepoStore>(store);
      final bloc = _Providers(
        ProviderLoaded(providers: [], currentProviderId: ''),
      );
      addTearDown(bloc.close);
      await pump(tester, const SourceCatalogPage(), bloc);
      expect(find.text('Readable Novel 0'), findsOneWidget);
      final buttons = find.descendant(
        of: find.byType(ListView),
        matching: find.byType(TextButton),
      );
      await tester.tap(buttons.first);
      // Pumped until the install lands rather than for a fixed 500ms. The
      // install is asynchronous, and a single pump long enough on a laptop is
      // not long enough on a busy runner — which is exactly how this passed
      // here and failed in CI.
      await tester.pump();
      for (var i = 0; i < 40 && store.installs == 0; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(store.installs, 1);
      expect(
        bloc.events.whereType<ProviderLoad>(),
        isNotEmpty,
        reason:
            'Otherwise SourcesHub and the picker keep their old provider list after success.',
      );
    },
  );

  testWidgets(
    'CAT-02 Language-facet failure must not discard a successful source page',
    (tester) async {
      getIt.registerSingleton<CatalogRepository>(_Catalog()..failFacets = true);
      final bloc = _Providers(
        ProviderLoaded(providers: [], currentProviderId: ''),
      );
      addTearDown(bloc.close);
      await pump(tester, const SourceCatalogPage(), bloc);
      expect(
        find.text('Readable Novel 0'),
        findsOneWidget,
        reason:
            'The actual source list request succeeded; auxiliary filter failure should degrade independently.',
      );
    },
  );

  testWidgets('CAT-03 Failed next page must stop spinner and offer retry', (
    tester,
  ) async {
    final catalog = _Catalog()..failMore = true;
    getIt.registerSingleton<CatalogRepository>(catalog);
    final bloc = _Providers(
      ProviderLoaded(providers: [], currentProviderId: ''),
    );
    addTearDown(bloc.close);
    await pump(tester, const SourceCatalogPage(), bloc);
    final scroll = tester
        .widgetList<Scrollable>(find.byType(Scrollable))
        .where((s) => s.axisDirection == AxisDirection.down)
        .single;
    final state = tester.state<ScrollableState>(find.byWidget(scroll));
    state.position.jumpTo(state.position.maxScrollExtent);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(catalog.pages, contains(2));
    expect(
      find.byType(CircularProgressIndicator),
      findsNothing,
      reason:
          'Failed page requests are complete, but _hasMore leaves a permanent spinner.',
    );
  });
}
