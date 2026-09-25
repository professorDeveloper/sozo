import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/onboarding/data/genre_catalog.dart';
import 'package:soplay/features/onboarding/data/onboarding_store.dart';
import 'package:soplay/features/onboarding/domain/onboarding_flow.dart';
import 'package:soplay/features/onboarding/domain/taste_profile.dart';
import 'package:soplay/features/onboarding/presentation/controllers/onboarding_controller.dart';
import 'package:soplay/features/onboarding/presentation/pages/onboarding_done_page.dart';
import 'package:soplay/features/onboarding/presentation/pages/onboarding_genres_page.dart';
import 'package:soplay/features/onboarding/presentation/pages/onboarding_kinds_page.dart';
import 'package:soplay/features/onboarding/presentation/pages/onboarding_notifications_page.dart';
import 'package:soplay/features/onboarding/presentation/pages/onboarding_page.dart';

class _Strings extends AssetLoader {
  const _Strings();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(
            File(
              'assets/translations/${locale.languageCode}.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
}

/// Every step laid out on a small phone with large text, in Arabic, and on a
/// landscape phone and a tablet — nothing may overflow.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sozo_onb_layout_');
    Hive.init(dir.path);
    await Hive.openBox(AppConstants.authBox, bytes: Uint8List(0));
    await Hive.openBox(AppConstants.settingsBox, bytes: Uint8List(0));
    await getIt.reset();
    getIt.registerSingleton<HiveService>(HiveService());
    final c = OnboardingController(
      store: MemoryOnboardingStore(),
      isSignedIn: () => false,
    );
    getIt.registerSingleton<OnboardingController>(c);
    await c.begin(OnboardingFlow.firstRun);
    await c.toggleKind(TasteKind.anime);
    await c.toggleKind(TasteKind.novels);
    for (final g in GenreCatalog.fallbackFor('anilist').take(5)) {
      await c.toggleGenre(g);
    }
  });

  tearDown(() async {
    await getIt.reset();
    await Hive.close();
    await dir.delete(recursive: true);
  });

  final catalog = GenreCatalog(
    fetch: (c) async => throw StateError('offline in tests'),
  );

  final pages = <String, Widget Function()>{
    'kinds': () => const OnboardingKindsPage(),
    'genres': () => OnboardingGenresPage(catalog: catalog),
    'notifications': () => const OnboardingNotificationsPage(),
    'done': () => const OnboardingDonePage(),
  };

  const screens = <String, (Size, double, String)>{
    'small phone, huge text, Arabic': (Size(360, 640), 2.0, 'ar'),
    'small phone, Uzbek': (Size(360, 640), 1.3, 'uz'),
    'landscape phone': (Size(780, 360), 1.0, 'en'),
    'tablet': (Size(1024, 768), 1.0, 'de'),
  };

  // The welcome copy under large text scrolls instead of overflowing.
  const welcomeScreens = <String, (Size, double, String)>{
    'tiny phone, big text, German': (Size(320, 568), 1.6, 'de'),
    'small phone, huge text': (Size(360, 640), 2.0, 'en'),
  };

  final runs = [
    for (final page in pages.entries)
      for (final screen in screens.entries) (page, screen),
    for (final screen in welcomeScreens.entries)
      (
        MapEntry<String, Widget Function()>('welcome', OnboardingPage.new),
        screen,
      ),
  ];

  for (final (page, screen) in runs) {
    testWidgets('${page.key} on a ${screen.key}', (tester) async {
      final (size, scale, lang) = screen.value;
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: const [
            Locale('en'),
            Locale('ar'),
            Locale('uz'),
            Locale('de'),
          ],
          startLocale: Locale(lang),
          path: 'assets/translations',
          assetLoader: const _Strings(),
          saveLocale: false,
          child: Builder(
            builder: (context) => MaterialApp.router(
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: context.localizationDelegates,
              theme: ThemeData.dark(useMaterial3: true),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              routerConfig: GoRouter(
                routes: [GoRoute(path: '/', builder: (_, _) => page.value())],
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 400));
      }
      expect(tester.takeException(), isNull);
      if (lang == 'ar') {
        final dir = Directionality.of(
          tester.element(find.byType(Scaffold).first),
        );
        expect(dir.name, 'rtl');
      }
    });
  }
}
