// The search tab's rail used to be headed with whatever the source called its
// own first home row, so one source headed it "HOMEPAGE" — a section on the
// search screen named after a page. These pin the two halves of the
// replacement: which row gets borrowed, and what the app calls it.
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soplay/features/home/domain/entities/home_section_entity.dart';
import 'package:soplay/features/home/domain/entities/movie.dart';
import 'package:soplay/features/home/domain/entities/view_all.dart';
import 'package:soplay/features/search/presentation/widgets/search_landing.dart';

/// The real en.json, so the headings under test are the strings that ship
/// rather than a fixture that can drift away from them.
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
  provider: 'src',
  thumbnail: null,
  year: null,
  rating: null,
  qualities: null,
  category: '',
);

HomeSectionEntity _section(String key, String label, {int items = 6}) =>
    HomeSectionEntity(
      key: key,
      label: label,
      viewAll: ViewAllEntity(slug: key, type: 'category'),
      items: [for (var i = 0; i < items; i++) _movie(i)],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  /// `tr()` reads a global that only exists once EasyLocalization has mounted,
  /// so every heading case runs inside a pumped one.
  Future<void> withTranslations(
    WidgetTester tester,
    void Function() body,
  ) async {
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
            home: const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    body();
  }

  group('searchRailHeading', () {
    testWidgets('never repeats a source that named its row after a page', (
      tester,
    ) async {
      await withTranslations(tester, () {
        final heading = searchRailHeading(
          railKey: 'home',
          railLabel: 'Homepage',
          source: 'AnimePahe',
        );
        expect(heading.toLowerCase(), isNot(contains('homepage')));
        expect(heading, contains('AnimePahe'));
        expect(heading, 'Browse AnimePahe');
      });
    });

    testWidgets('reads a row named "Trending now" as the popularity row', (
      tester,
    ) async {
      await withTranslations(tester, () {
        // The key says nothing; the name is the only place the fact appears,
        // and it is used as evidence rather than printed.
        final heading = searchRailHeading(
          railKey: 'home',
          railLabel: 'Trending now',
          source: 'AnimePahe',
        );
        expect(heading, 'Popular on AnimePahe');
        expect(heading.toLowerCase(), isNot(contains('trending now')));
      });
    });

    testWidgets('still says something for a source that names nothing', (
      tester,
    ) async {
      await withTranslations(tester, () {
        final heading = searchRailHeading(
          railKey: '',
          railLabel: '',
          source: 'AnimePahe',
        );
        expect(heading, 'Browse AnimePahe');
      });
    });

    testWidgets('falls back to the shelf\'s purpose when the source has no '
        'name to give', (tester) async {
      await withTranslations(tester, () {
        final heading = searchRailHeading(
          railKey: 'trending',
          railLabel: 'Trending now',
          source: '',
        );
        expect(heading, isNotEmpty);
        expect(heading, isNot(contains('{source}')));
        expect(heading, 'Before you search');
      });
    });

    testWidgets('trusts the key when the name is in a language it cannot read',
        (tester) async {
      await withTranslations(tester, () {
        expect(
          searchRailHeading(
            railKey: 'popular-anime',
            railLabel: 'Ommabop',
            source: 'Asilmedia',
          ),
          'Popular on Asilmedia',
        );
      });
    });
  });

  group('searchRailSection', () {
    test('prefers the popularity row over whatever comes first', () {
      final rail = searchRailSection([
        _section('latest', 'Latest additions'),
        _section('home', 'Trending now'),
      ]);
      expect(rail?.label, 'Trending now');
    });

    test('skips the rails built out of this viewer\'s own history', () {
      final rail = searchRailSection([
        _section('continue-watching', 'Continue watching'),
        _section('my-list', 'My list'),
        _section('home', 'Homepage'),
      ]);
      expect(rail?.label, 'Homepage');
    });

    test('ignores a shelf too short to look like a shelf', () {
      // Three covers and a gap read as a row that failed to load.
      expect(searchRailSection([_section('home', 'Homepage', items: 3)]), null);
    });

    test('has nothing to borrow from a home with only personal rails', () {
      expect(searchRailSection([_section('history', 'Recently watched')]), null);
    });
  });
}
