import 'dart:convert';
import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soplay/features/sources/domain/source_ecosystem.dart';
import 'package:soplay/features/sources/domain/source_scope.dart';
import 'package:soplay/features/sources/presentation/widgets/source_scope_menu.dart';

class _Strings extends AssetLoader {
  const _Strings();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('assets/translations/en.json').readAsStringSync())
          as Map<String, dynamic>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  Future<void> mount(
    WidgetTester tester,
    SourceScopeCounts counts,
    ValueChanged<SourceScope> onPick,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en')],
        path: 'assets/translations',
        assetLoader: const _Strings(),
        child: Builder(
          builder: (context) => MaterialApp(
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            home: Scaffold(
              body: SourceScopeMenu(
                counts: counts,
                scope: SourceScope.all,
                onPick: onPick,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'host filters are visible and selectable without opening a menu',
    (tester) async {
      SourceScope? picked;
      await mount(
        tester,
        const SourceScopeCounts(
          byEcosystem: {
            SourceEcosystem.sozo: 4,
            SourceEcosystem.cloudstream: 100,
            SourceEcosystem.aniyomi: 12,
          },
          byRepo: {},
        ),
        (s) => picked = s,
      );
      await tester.tap(find.text('Sozo · 4'));
      expect(picked, const SourceScope(ecosystem: SourceEcosystem.sozo));
      expect(find.text('CloudStream · 100').hitTestable(), findsOneWidget);
      expect(find.text('Aniyomi · 12').hitTestable(), findsOneWidget);
      await tester.tap(find.text('CloudStream · 100'));
      expect(picked, const SourceScope(ecosystem: SourceEcosystem.cloudstream));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'a CloudStream-only library still exposes its repository filter',
    (tester) async {
      SourceScope? picked;
      await mount(
        tester,
        const SourceScopeCounts(
          byEcosystem: {SourceEcosystem.cloudstream: 100},
          byRepo: {
            SourceEcosystem.cloudstream: {'repo-one': 60, 'repo-two': 40},
          },
        ),
        (s) => picked = s,
      );
      expect(find.text('Sozo · 0'), findsOneWidget);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Sozo · 0'))
            .onSelected,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('repository-picker')));
      await tester.pumpAndSettle();
      expect(find.text('repo-two'), findsOneWidget);
      await tester.tap(find.text('repo-two'));
      await tester.pumpAndSettle();
      expect(
        picked,
        const SourceScope(
          ecosystem: SourceEcosystem.cloudstream,
          repo: 'repo-two',
        ),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
