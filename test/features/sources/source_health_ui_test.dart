import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/content/content_mode.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/profile/domain/entities/provider_entity.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_bloc.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_event.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_state.dart';
import 'package:soplay/features/profile/presentation/widgets/provider_quick_switch.dart';
import 'package:soplay/features/search/data/source_health_store.dart';
import 'package:soplay/features/sources/data/source_check_store.dart';
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
  String getContentMode() => 'manga';
  @override
  Future<void> setContentMode(String mode) async {}
  @override
  List<String> getProviderLanguages() => [];
  @override
  List<String> getFavoriteProviders() => [];
  @override
  String get dateFormatPattern => '';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Providers extends Cubit<ProviderState> implements ProviderBloc {
  _Providers(super.initialState);
  @override
  void add(ProviderEvent event) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ProviderEntity _source(String id, String name) => ProviderEntity(
  id: id,
  name: name,
  image: '',
  url: '',
  description: '',
  domains: const [],
);

final _sources = [
  _source('mn:1', 'Alpha Dead'),
  _source('mn:2', 'Beta Walled'),
  _source('mn:3', 'Gamma Fine'),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // In memory: a disk write started under the fake clock never finishes, and
  // Hive's write lock would then stall the next test.
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    await Hive.openBox(AppConstants.settingsBox, bytes: Uint8List(0));
  });

  tearDownAll(Hive.close);

  setUp(() async {
    await getIt.reset();
    getIt.registerSingleton<HiveService>(_Hive());
    final store = SourceHealthStore();
    await store.clear();
    await store.setHideDown(false);
    final now = DateTime.now().millisecondsSinceEpoch;
    await Hive.box(AppConstants.settingsBox).put(
      'search_source_health_remote',
      {
        'fetchedAt': now,
        'checkedAt': now,
        'down': <String>[],
        'extCheckedAt': now,
        'ext': {
          'mn:1': {'s': 'dead', 'r': 'dns'},
          'mn:2': {'s': 'cloudflare', 'r': 'blocked'},
        },
      },
    );
  });

  tearDown(() => getIt.reset());

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final bloc = _Providers(
      ProviderLoaded(providers: _sources, currentProviderId: 'mn:3'),
    );
    addTearDown(bloc.close);
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

  double top(WidgetTester tester, String text) =>
      tester.getTopLeft(find.text(text)).dy;

  testWidgets('the hub badges, sinks and can hide down sources', (
    tester,
  ) async {
    await pump(tester, const SourcesHubPage());

    expect(find.text('Down'), findsOneWidget);
    expect(find.text('Cloudflare'), findsOneWidget);
    expect(top(tester, 'Alpha Dead'), greaterThan(top(tester, 'Gamma Fine')));
    expect(top(tester, 'Beta Walled'), lessThan(top(tester, 'Gamma Fine')));

    await tester.tap(find.text('Down'));
    await tester.pumpAndSettle();
    expect(find.text('This source looks down'), findsOneWidget);
    expect(find.text('The domain no longer resolves'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Hide down sources · 1'));
    await tester.pumpAndSettle();
    expect(find.text('Alpha Dead'), findsNothing);
    expect(find.text('Gamma Fine'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the picker badges and sinks down sources, and explains a '
      'Cloudflare wall', (tester) async {
    await pump(
      tester,
      Scaffold(
        body: ProviderQuickSwitchSheet(
          favorites: const [],
          all: _sources,
          mode: ContentMode.manga,
          currentProviderId: 'mn:3',
        ),
      ),
    );

    expect(find.text('Down'), findsOneWidget);
    expect(top(tester, 'Alpha Dead'), greaterThan(top(tester, 'Gamma Fine')));

    await tester.tap(find.text('Cloudflare'));
    await tester.pumpAndSettle();
    expect(find.text('Behind a Cloudflare check'), findsOneWidget);
    expect(
      find.text('A Cloudflare challenge blocked the check'),
      findsOneWidget,
    );
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Hide down sources · 1'));
    await tester.pumpAndSettle();
    expect(find.text('Alpha Dead'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the source in use is never hidden', (tester) async {
    await SourceHealthStore().setHideDown(true);
    await pump(
      tester,
      Scaffold(
        body: ProviderQuickSwitchSheet(
          favorites: const [],
          all: _sources,
          mode: ContentMode.manga,
          currentProviderId: 'mn:1',
        ),
      ),
    );
    expect(find.text('Alpha Dead'), findsOneWidget);
    expect(find.text('Down'), findsOneWidget);
  });

  testWidgets('a source this phone found dead, in use, badges and explains', (
    tester,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await SourceCheckStore.shared.put(
      'mn:3',
      SourceCheck(
        verdict: SourceVerdict.dead,
        at: now,
        detail: 'Could not download RoyalRoad (HTTP 404)',
        fails: 4,
        firstFailAt: now,
      ),
    );
    addTearDown(
      () => SourceCheckStore.shared.put(
        'mn:3',
        SourceCheck(verdict: SourceVerdict.alive, at: now),
      ),
    );
    await pump(tester, const SourcesHubPage());
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Down').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await pump(
      tester,
      Scaffold(
        body: ProviderQuickSwitchSheet(
          favorites: const [],
          all: _sources,
          mode: ContentMode.manga,
          currentProviderId: 'mn:3',
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Down').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
