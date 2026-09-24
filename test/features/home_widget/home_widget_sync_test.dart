// What the home screen widget is handed: the same titles Home would offer to
// continue, and a line under each in the viewer's words.
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soplay/features/history/domain/entities/history_item.dart';
import 'package:soplay/features/home_widget/home_widget_sync.dart';

class _Translations extends AssetLoader {
  const _Translations();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('assets/translations/en.json').readAsStringSync())
          as Map<String, dynamic>;
}

HistoryItem item(
  String url, {
  int at = 0,
  bool serial = true,
  int? ep,
  int pos = 10 * 60000,
  int dur = 24 * 60000,
  String? media,
}) => HistoryItem(
  contentUrl: url,
  provider: 'p',
  title: url,
  isSerial: serial,
  episodeNumber: ep,
  positionMs: pos,
  durationMs: dur,
  watchedAt: at,
  mediaType: media,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'one row per title, newest first, finished films left out, three at most',
    () {
      final rows = HomeWidgetSync.continueItems([
        item('a', at: 1, ep: 1),
        item('a', at: 5, ep: 2),
        item('film', at: 9, serial: false, pos: 99, dur: 100),
        item('b', at: 3),
        item('c', at: 4),
        item('d', at: 2),
      ]);
      expect(rows.map((r) => r.contentUrl), ['a', 'c', 'b']);
      expect(rows.first.episodeNumber, 2);
    },
  );

  testWidgets('the line under a title', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    late BuildContext ctx;
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
            home: Builder(
              builder: (inner) {
                ctx = inner;
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(ctx, isNotNull);
    expect(
      HomeWidgetSync.subtitleOf(item('a', ep: 7, pos: 10 * 60000)),
      'Episode 7 · 14 min left',
    );
    expect(
      HomeWidgetSync.subtitleOf(
        item('m', ep: 128, pos: 3, dur: 20, media: 'manga'),
      ),
      'Chapter 128',
    );
    expect(HomeWidgetSync.subtitleOf(item('f', serial: false)), '14 min left');
  });
}
