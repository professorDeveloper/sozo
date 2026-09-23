import 'dart:convert';
import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/live_tv/data/live_tv_service.dart';
import 'package:soplay/features/live_tv/presentation/pages/live_tv_page.dart';

class _Store implements HiveService {
  List<String> recent = [];
  @override
  List<String> getLiveTvFavourites() => [];
  @override
  List<String> getLiveTvRecent() => recent;
  @override
  Map<String, Map<String, String>> getLiveTvCards() => {};
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Service extends LiveTvService {
  _Service() : super(dio: Dio());
  bool fail = false;
  final limits = <int>[];
  @override
  Future<LiveIndex> index() async =>
      const LiveIndex(folders: [], countries: []);
  @override
  Future<LivePage> browse({
    String? category,
    String? country,
    String? search,
    int page = 1,
    int limit = 40,
  }) async {
    limits.add(limit);
    if (fail) throw StateError('offline');
    return LivePage(
      channels: const [
        LiveChannel(
          id: 'test-channel',
          name: 'Test broadcaster',
          streamUrl: 'https://example.com/live.m3u8',
        ),
      ],
      page: page,
      total: 1,
      hasMore: false,
    );
  }
}

class _Translations extends AssetLoader {
  const _Translations();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('assets/translations/en.json').readAsStringSync())
          as Map<String, dynamic>;
}

Future<void> _pump(WidgetTester tester) async {
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
          home: const LiveTvPage(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  late _Service service;
  setUp(() {
    service = _Service();
    getIt.registerSingleton<HiveService>(_Store());
    getIt.registerSingleton<LiveTvService>(service);
  });
  tearDown(() async => getIt.reset());

  testWidgets(
    'real service rows appear without opening a category; all opens browse',
    (tester) async {
      await _pump(tester);
      await tester.pumpAndSettle();
      expect(find.text('Test broadcaster'), findsOneWidget);
      expect(service.limits, [12]);
      await tester.tap(find.text('View all'));
      await tester.pumpAndSettle();
      expect(service.limits, [12, 40]);
      expect(find.text('Test broadcaster'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('failed lineup can recover without invented channel cards', (
    tester,
  ) async {
    service.fail = true;
    await _pump(tester);
    await tester.pumpAndSettle();
    expect(find.text('Test broadcaster'), findsNothing);
    service.fail = false;
    await tester.tap(find.text('Try again').first);
    await tester.pumpAndSettle();
    expect(find.text('Test broadcaster'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'last opened channel has a selected state separate from favourites',
    (tester) async {
      (getIt<HiveService>() as _Store).recent = ['test-channel'];
      await _pump(tester);
      final selected = find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Test broadcaster' &&
            widget.properties.selected == true,
      );
      expect(selected, findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(find.byIcon(Icons.star_rounded), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
