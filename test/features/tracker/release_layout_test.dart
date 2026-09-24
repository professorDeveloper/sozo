// The release cards hold on a narrow phone with large text, in long and
// right-to-left languages.
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/features/tracker/data/release_feed_store.dart';
import 'package:soplay/features/tracker/domain/release_entry.dart';
import 'package:soplay/features/tracker/presentation/pages/release_feed_page.dart';
import 'package:soplay/features/tracker/presentation/widgets/release_widgets.dart';

class _Strings extends AssetLoader {
  const _Strings();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(
            File('assets/translations/${locale.languageCode}.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
}

ReleaseEntry _entry(String url) => ReleaseEntry(
  provider: 'p',
  contentUrl: url,
  title: 'A title long enough to take both of the lines it is given $url',
  thumbnail: '',
  mode: 'video',
  episode: 1012,
  fromEpisode: 1011,
  at: DateTime.now().millisecondsSinceEpoch,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Box box;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    Hive.init('${Directory.systemTemp.path}/sozo_release_layout');
    box = await Hive.openBox('sozo_release_layout');
  });
  tearDownAll(() async => Hive.close());

  setUp(() async {
    await box.clear();
    await getIt.reset();
    final feed = ReleaseFeedStore(box: box);
    getIt.registerSingleton<ReleaseFeedStore>(feed);
    await feed.add(_entry('a'));
    await feed.add(_entry('b'));
  });
  tearDown(() => getIt.reset());

  final widgets = <String, Widget Function()>{
    'home rail': () => const NewReleasesRail(),
    'feed card': () => ReleaseCard(entry: _entry('a'), onSeen: () {}),
  };
  const screens = <(double, String)>[
    (1.0, 'en'),
    (1.3, 'fr'),
    (1.6, 'pt'),
    (2.0, 'ar'),
    (2.0, 'de'),
  ];

  for (final w in widgets.entries) {
    for (final (scale, lang) in screens) {
      testWidgets('${w.key} at 320dp, text x$scale, $lang', (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          EasyLocalization(
            supportedLocales: const [
              Locale('en'),
              Locale('fr'),
              Locale('pt'),
              Locale('ar'),
              Locale('de'),
            ],
            startLocale: Locale(lang),
            path: 'assets/translations',
            assetLoader: const _Strings(),
            saveLocale: false,
            child: Builder(
              builder: (context) => MaterialApp(
                locale: context.locale,
                supportedLocales: context.supportedLocales,
                localizationsDelegates: context.localizationDelegates,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Scaffold(body: SingleChildScrollView(child: w.value())),
              ),
            ),
          ),
        );
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 400));
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
