// The About tab has to be readable at a glance, not eight identical cards.
//
// Every fact used to be the same grey box with an uppercase grey label over a
// value, so nothing distinguished the studio from the rank from the status and
// finding one meant reading all of them. Two things carry meaning now, and
// neither invents any data: each fact gets the icon of the KIND of thing it is,
// and status — the one fact whose value is a state rather than a value — is
// coloured by that state.
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soplay/features/detail/domain/entities/record_info.dart';
import 'package:soplay/features/detail/presentation/widgets/detail_about_tab.dart';

class _Translations extends AssetLoader {
  const _Translations();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('assets/translations/en.json').readAsStringSync())
          as Map<String, dynamic>;
}

/// Every label key a RecordFact is built with anywhere in the app. Kept here so
/// that adding a fact without giving it an icon fails a test rather than
/// quietly falling back to a generic one.
const _allFactKeys = <String>[
  'detail.about_studio',
  'detail.about_author',
  'detail.about_source',
  'detail.about_episodes',
  'detail.about_chapters',
  'detail.about_volumes',
  'detail.about_seasons',
  'detail.about_rank',
  'detail.about_status',
  'detail.about_format',
  'detail.about_network',
  'detail.about_budget',
  'detail.about_collection',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  Future<void> pumpAbout(WidgetTester tester, RecordInfo record) async {
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
            home: Scaffold(
              body: SingleChildScrollView(
                child: DetailAboutTab(record: record),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  RecordInfo recordOf(List<RecordFact> facts) =>
      RecordInfo(facts: facts, tags: const []);

  testWidgets('every fact kind has an icon of its own', (tester) async {
    // The point of the icons is that they DIFFER — a set where several share a
    // glyph is back to "find it by reading every one".
    await pumpAbout(
      tester,
      recordOf([for (final k in _allFactKeys) RecordFact(k, 'value')]),
    );

    final icons = tester
        .widgetList<Icon>(find.byType(Icon))
        .map((i) => i.icon)
        .toList();
    expect(icons, hasLength(_allFactKeys.length));
    expect(
      icons.toSet(),
      hasLength(_allFactKeys.length),
      reason: 'two facts share a glyph, so neither can be found by shape',
    );
    expect(
      icons,
      isNot(contains(Icons.info_rounded)),
      reason:
          'info_rounded is the fallback — a fact reaching it means the icon '
          'map was not updated when the fact was added',
    );
  });

  group('status is coloured by the state it reports', () {
    Future<Color?> colourOf(WidgetTester tester, String status) async {
      await pumpAbout(
        tester,
        recordOf([RecordFact('detail.about_status', status)]),
      );
      return tester.widget<Icon>(find.byType(Icon)).color;
    }

    testWidgets('something still going is green', (tester) async {
      expect(await colourOf(tester, 'Releasing'), const Color(0xFF3FB950));
      expect(await colourOf(tester, 'Returning Series'), const Color(0xFF3FB950));
    });

    testWidgets('something over is grey', (tester) async {
      expect(await colourOf(tester, 'Finished'), const Color(0xFF8B949E));
      expect(await colourOf(tester, 'Ended'), const Color(0xFF8B949E));
    });

    testWidgets('something stopped is red', (tester) async {
      expect(await colourOf(tester, 'Cancelled'), const Color(0xFFE5484D));
      expect(await colourOf(tester, 'Hiatus'), const Color(0xFFE5484D));
    });

    testWidgets('and a status nobody recognises is left neutral', (
      tester,
    ) async {
      // A wrong colour is worse than none: it states something about the title
      // that nothing established.
      final c = await colourOf(tester, 'Something new');
      expect(c, isNot(const Color(0xFF3FB950)));
      expect(c, isNot(const Color(0xFFE5484D)));
    });
  });

  testWidgets('no other fact is coloured', (tester) async {
    // Colour has to mean something. Used for decoration it stops being able to
    // say "this one is still airing".
    await pumpAbout(
      tester,
      recordOf([
        RecordFact('detail.about_studio', 'Bones'),
        RecordFact('detail.about_rank', '#6 highest rated'),
      ]),
    );

    for (final icon in tester.widgetList<Icon>(find.byType(Icon))) {
      expect(icon.color, isNot(const Color(0xFF3FB950)));
      expect(icon.color, isNot(const Color(0xFF8B949E)));
    }
  });

  testWidgets('a record with nothing in it draws nothing', (tester) async {
    await pumpAbout(tester, recordOf(const []));
    expect(find.byType(Icon), findsNothing);
  });
}
