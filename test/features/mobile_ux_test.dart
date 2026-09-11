import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soplay/core/localization/language_picker.dart';
import 'package:soplay/core/content/content_mode.dart';
import 'package:soplay/core/navigation/app_tab.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/theme/app_theme.dart';
import 'package:soplay/features/detail/domain/entities/video_source_entity.dart';
import 'package:soplay/features/download/data/models/download_item_model.dart';
import 'package:soplay/features/download/domain/entities/download_item.dart';
import 'package:soplay/features/download/presentation/widgets/download_choice_sheet.dart';
import 'package:soplay/features/profile/domain/entities/provider_entity.dart';
import 'package:soplay/features/profile/presentation/widgets/provider_quick_switch.dart';
import 'package:soplay/features/main/presentation/pages/main_page.dart';
import 'package:soplay/features/onboarding/presentation/pages/onboarding_page.dart';
import 'package:soplay/features/search/domain/entities/cross_search_scope.dart';
import 'package:soplay/features/search/presentation/widgets/search_header.dart';
import 'package:soplay/features/search/presentation/widgets/source_scope_bar.dart';

class _Translations extends AssetLoader {
  const _Translations();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(
            File(
              'assets/translations/${locale.languageCode}.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
}

class _ManifestAdapter implements HttpClientAdapter {
  RequestOptions? request;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? body,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    return ResponseBody.fromString(
      '#EXTM3U\n'
      '#EXT-X-STREAM-INF:BANDWIDTH=900000,RESOLUTION=854x480\n480/index.m3u8\n'
      '#EXT-X-STREAM-INF:BANDWIDTH=4000000,RESOLUTION=1920x1080\n1080/index.m3u8\n',
      200,
      headers: {
        Headers.contentTypeHeader: ['application/vnd.apple.mpegurl'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void _noop() {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    double width = 360,
    double height = 800,
    double scale = 1,
    double keyboard = 0,
    String language = 'en',
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      EasyLocalization(
        key: ValueKey('$language-$scale-$width'),
        supportedLocales: const [
          Locale('en'),
          Locale('uz'),
          Locale('ru'),
          Locale('ar'),
          Locale('de'),
          Locale('nl'),
          Locale('es'),
          Locale('pt'),
          Locale('fr'),
          Locale('tr'),
          Locale('id'),
        ],
        startLocale: Locale(language),
        fallbackLocale: const Locale('en'),
        saveLocale: false,
        path: 'assets/translations',
        assetLoader: const _Translations(),
        child: Builder(
          builder: (context) => MaterialApp(
            theme: AppTheme.dark,
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
                viewInsets: EdgeInsets.only(bottom: keyboard),
              ),
              child: child!,
            ),
            home: child,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final providers = List.generate(
    2001,
    (i) => ProviderEntity(
      id: 'p$i',
      name: 'Source $i',
      image: '',
      url: '',
      description: '',
      domains: const [],
    ),
  );

  for (final locale in ['en', 'de', 'nl', 'ar']) {
    testWidgets('source picker stays visible with 2001 sources in $locale', (
      tester,
    ) async {
      var opened = false;
      await pump(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: SourceScopeBar(
              providers: providers,
              order: providers.map((p) => p.id).toList(),
              scope: const CrossSearchScope.all(),
              onToggle: (_) {},
              onSelectAll: () {},
              onOpenPicker: () => opened = true,
            ),
          ),
        ),
        width: 320,
        scale: 2,
        language: locale,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Source 2000'), findsNothing);
      await tester.tap(find.byIcon(Icons.tune));
      expect(opened, isTrue);
    });
  }

  testWidgets('search input retains its width while typing with every action', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    await pump(
      tester,
      Scaffold(
        body: SearchStickyHeader(
          progress: 0,
          topPad: 0,
          controller: controller,
          focus: focus,
          hasActiveFilter: false,
          showFilter: true,
          onFilterTap: () {},
          onMultiSearchTap: () {},
          onTorrentTap: () {},
          onQueryChanged: (_) {},
          onSubmitted: (_) {},
          onClear: controller.clear,
        ),
      ),
      width: 320,
      scale: 2,
      language: 'de',
    );
    final before = tester.getSize(find.byType(TextField)).width;
    await tester.enterText(find.byType(TextField), 'A long movie title');
    await tester.pump();
    expect(tester.getSize(find.byType(TextField)).width, before);
    // 16dp gutters and a 1dp border on each side; actions cost no input width.
    expect(before, 286);
    expect(tester.takeException(), isNull);
  });

  testWidgets('intro language choice scrolls at large text and short height', (
    tester,
  ) async {
    await pump(
      tester,
      const LanguagePage(),
      width: 320,
      height: 480,
      scale: 2,
      language: 'de',
    );
    expect(find.byType(FilledButton), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Bahasa Indonesia'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(ListView), const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(find.text('🇮🇩'), findsOneWidget);
    await tester.tap(find.text('Bahasa Indonesia'));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'intro header keeps logo left and skip right without language chip',
    (tester) async {
      await pump(
        tester,
        Scaffold(body: OnboardingHeader(onSkip: _noop)),
        width: 320,
        height: 480,
        scale: 2,
        language: 'de',
      );
      final logo = tester.getRect(find.text('SOZO'));
      final skip = tester.getRect(find.text('Überspringen'));
      expect(logo.left, lessThan(32));
      expect(skip.right, greaterThan(280));
      expect(find.byIcon(Icons.language_rounded), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'download confirms the chosen source headers and declared resolution',
    (tester) async {
      DownloadSelection? selected;
      await pump(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => selected = await chooseDownload(
                context,
                url: 'https://example.test/first.mp4',
                headers: const {'Referer': 'first'},
                type: 'mp4',
                sources: const [
                  VideoSourceEntity(
                    quality: '720p',
                    videoUrl: 'https://example.test/second.mp4',
                    isDefault: false,
                    accessible: true,
                    type: 'mp4',
                    height: 720,
                    headers: {'Referer': 'second'},
                  ),
                ],
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Quality unknown'), findsOneWidget);
      await tester.tap(find.text('720p'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(selected?.url, 'https://example.test/second.mp4');
      expect(selected?.headers, {'Referer': 'second'});
      expect(selected?.height, 720);
    },
  );

  test(
    'download resolution survives storage and legacy data stays unknown',
    () {
      const item = DownloadItem(
        id: 'a',
        contentUrl: 'page',
        provider: 'p',
        title: 'Film',
        sourceUrl: 'video',
        relativePath: 'downloads/a/video.mp4',
        createdAt: 0,
        videoHeight: 1080,
      );
      final json = DownloadItemModel.toJson(item.copyWith(sizeBytes: 2048));
      expect(DownloadItemModel.fromJson(json).videoHeight, 1080);
      json.remove('videoHeight');
      expect(DownloadItemModel.fromJson(json).videoHeight, isNull);
    },
  );

  testWidgets('source switcher is lazy and recoverable with a keyboard', (
    tester,
  ) async {
    await pump(
      tester,
      Scaffold(
        resizeToAvoidBottomInset: false,
        body: ProviderQuickSwitchSheet(
          favorites: const [],
          all: providers,
          mode: ContentMode.video,
          currentProviderId: 'p0',
        ),
      ),
      width: 320,
      height: 600,
      scale: 2,
      keyboard: 250,
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(ListTile).evaluate().length, lessThan(30));
    await tester.ensureVisible(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'not installed anywhere');
    await tester.pumpAndSettle();
    expect(find.text('No sources match your search.'), findsOneWidget);
    expect(find.text('Manage sources'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('six navigation destinations remain readable at 200 percent', (
    tester,
  ) async {
    var selected = -1;
    await pump(
      tester,
      Scaffold(
        bottomNavigationBar: ReadableNavigationBar(
          index: 0,
          items: [
            for (final id in [...kDefaultTabs, TabId.downloads])
              kTabRegistry[id]!,
          ],
          onTap: (i) => selected = i,
        ),
      ),
      width: 320,
      height: 640,
      scale: 2,
      language: 'de',
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byIcon(kTabRegistry[TabId.downloads]!.icon));
    expect(selected, 5);
  });

  testWidgets(
    'HLS download offers actual renditions and keeps the chosen URL',
    (tester) async {
      final adapter = _ManifestAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      DownloadSelection? selected;
      await pump(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              child: const Text('open'),
              onPressed: () async =>
                  selected = await showModalBottomSheet<DownloadSelection>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => DownloadChoiceSheet(
                      url: 'https://example.test/movie/master.m3u8',
                      headers: const {'Referer': 'required'},
                      type: 'hls',
                      manifestClient: dio,
                    ),
                  ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('1080p'), findsOneWidget);
      expect(find.text('480p'), findsOneWidget);
      expect(adapter.request?.headers['Referer'], 'required');
      await tester.tap(find.text('480p'));
      await tester.pump();
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(selected?.url, 'https://example.test/movie/480/index.m3u8');
      expect(selected?.height, 480);
    },
  );

  test('secondary copy clears 4.5:1 on every shipped dark surface', () {
    for (final background in [
      AppColors.background,
      AppColors.surface,
      AppColors.surfaceVariant,
    ]) {
      final ratio =
          (AppColors.textHint.computeLuminance() + 0.05) /
          (background.computeLuminance() + 0.05);
      expect(ratio, greaterThanOrEqualTo(4.5));
    }
  });
}
