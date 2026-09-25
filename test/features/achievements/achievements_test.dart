// Badges: what the server says, in what order they are celebrated, and that
// every screen that shows them draws without error.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/achievements/data/achievements_remote_data_source.dart';
import 'package:soplay/features/achievements/data/achievements_service.dart';
import 'package:soplay/features/achievements/presentation/pages/achievements_page.dart';
import 'package:soplay/features/streak/data/streak_remote_data_source.dart';
import 'package:soplay/features/streak/data/streak_service.dart';
import 'package:soplay/features/streak/domain/entities/streak_state.dart';
import 'package:soplay/features/achievements/domain/achievements.dart';
import 'package:soplay/features/achievements/presentation/dialogs/achievement_unlocked_dialog.dart';
import 'package:soplay/features/achievements/presentation/widgets/achievement_medal.dart';
import 'package:soplay/features/achievements/presentation/widgets/medal_viewer.dart';
import 'package:soplay/features/social/domain/social_models.dart';
import 'package:soplay/features/social/presentation/widgets/activity_card.dart';

class _Translations extends AssetLoader {
  const _Translations();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('assets/translations/en.json').readAsStringSync())
          as Map<String, dynamic>;
}

class _Hive implements HiveService {
  @override
  bool get isLoggedIn => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Remote extends AchievementsRemoteDataSource {
  _Remote(this.body) : super(dio: Dio());
  final Map<String, dynamic> body;
  @override
  Future<Map<String, dynamic>> me() async => body;
}

final _json = {
  'total': 38,
  'unlockedCount': 5,
  'families': [
    {
      'id': 'streak',
      'tiers': [7, 30, 100, 365],
      'tier': 3,
      'value': 104,
      'next': 365,
      'unlockedAt': [
        '2026-06-01T00:00:00Z',
        '2026-06-24T00:00:00Z',
        '2026-09-08T00:00:00Z',
        null,
      ],
    },
    {
      'id': 'episodes',
      'tiers': [10, 100, 500, 1000],
      'tier': 2,
      'value': 312,
      'next': 500,
      'unlockedAt': [],
    },
  ],
  'singles': [
    {
      'id': 'iron_will',
      'rarity': 'ember',
      'need': 100,
      'value': 100,
      'unlocked': true,
      'at': '2026-09-08T00:00:00Z',
    },
    {
      'id': 'explorer',
      'rarity': 'silver',
      'need': 10,
      'value': 4,
      'unlocked': false,
    },
  ],
  'showcase': ['streak', 'iron_will', 'future_badge'],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the model', () {
    test('parses families, singles and progress', () {
      final v = AchievementsView.fromJson(_json);
      final streak = v.family('streak')!;
      expect(streak.medal, MedalTier.gold);
      // 104 of the way from 100 to 365.
      expect(streak.progress, closeTo(4 / 265, 1e-9));
      expect(v.single('iron_will')!.medal, MedalTier.ember);
      expect(v.single('explorer')!.medal, MedalTier.locked);
      // Hardest-won first: an ember single before a gold family tier.
      expect(v.earnedIds.take(2), ['iron_will', 'streak']);
      expect(v.earnedIds, isNot(contains('explorer')));
    });

    test('an id this build does not know still gets a medal', () {
      expect(
        AchievementDef.of('future_badge').icon,
        Icons.emoji_events_rounded,
      );
      expect(AchievementDef.isKnown('future_badge'), isFalse);
    });

    test('a friend\'s showcase arrives as id and tier', () {
      final v = AchievementsView.fromJson({
        'total': 38,
        'unlockedCount': 2,
        'families': [
          {
            'id': 'streak',
            'tier': 4,
            'tiers': [7, 30, 100, 365],
          },
        ],
        'singles': [
          {'id': 'binge', 'rarity': 'ember'},
        ],
        'showcase': [
          {'id': 'streak', 'tier': 4},
        ],
      });
      expect(v.showcase, ['streak']);
      expect(v.medalOf('streak'), MedalTier.ember);
      expect(v.medalOf('binge'), MedalTier.ember);
    });
  });

  test('the streak is celebrated first, one badge per family', () {
    final ranked = AchievementUnlockedDialog.ranked(const [
      AchievementUnlock(id: 'episodes', tier: 1),
      AchievementUnlock(id: 'episodes', tier: 2),
      AchievementUnlock(id: 'binge', tier: 1),
      AchievementUnlock(id: 'streak', tier: 3),
    ]);
    expect(ranked.map((u) => '${u.id}:${u.tier}'), [
      'streak:3',
      'episodes:2',
      'binge:1',
    ]);
  });

  group('on screen', () {
    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      await EasyLocalization.ensureInitialized();
      await Hive.openBox(AppConstants.settingsBox, bytes: Uint8List(0));
    });
    tearDownAll(Hive.close);

    Future<void> pump(WidgetTester tester, Widget child) async {
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
            builder: (context) => MaterialApp(
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: context.localizationDelegates,
              home: Scaffold(body: child),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('every tier of medal paints', (tester) async {
      await pump(
        tester,
        Wrap(
          children: [
            for (final t in MedalTier.values)
              AchievementBadge(id: 'streak', tier: t, size: 64),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        find.byType(AchievementMedal),
        findsNWidgets(MedalTier.values.length),
      );
    });

    testWidgets('the celebration shows the streak and what else came', (
      tester,
    ) async {
      final view = AchievementsView.fromJson(_json);
      await pump(
        tester,
        AchievementUnlockedDialog(
          view: view,
          unlocks: const [
            AchievementUnlock(id: 'streak', tier: 3),
            AchievementUnlock(id: 'iron_will', tier: 1),
          ],
        ),
      );
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
      expect(find.text('Flame'), findsOneWidget);
      expect(find.text('Gold tier'), findsOneWidget);
      expect(find.text('100 days in a row'), findsOneWidget);
      expect(find.text('Also earned'), findsOneWidget);
    });

    testWidgets('the viewer holds a medal up and steps through its tiers', (
      tester,
    ) async {
      final view = AchievementsView.fromJson(_json);
      await pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showMedalViewer(context, id: 'streak', view: view),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      expect(find.text('Flame'), findsOneWidget);
      // Opens on the best tier earned: gold, a hundred days.
      expect(find.text('Gold'), findsOneWidget);
      expect(find.text('100 days in a row'), findsOneWidget);
      // The ember tier, not yet earned.
      await tester.tap(find.byType(AchievementBadge).last);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Ember'), findsOneWidget);
      expect(find.text('365 days in a row'), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the streak card: medals from the best streak, each one opens '
        'its tier, and the viewer lists every tier', (tester) async {
      await getIt.reset();
      addTearDown(getIt.reset);
      final hive = _Hive();
      getIt.registerSingleton<HiveService>(hive);
      // Best 4 days, running 2: nothing earned yet, aiming at the 7-day mark.
      final body = {
        ..._json,
        'families': [
          {'id': 'streak', 'tiers': [7, 30, 100, 365], 'tier': 0, 'value': 4, 'next': 7, 'unlockedAt': []},
        ],
      };
      final achievements = AchievementsService(remote: _Remote(body), hive: hive);
      getIt.registerSingleton<AchievementsService>(achievements);
      final streak = StreakService(
        remote: StreakRemoteDataSource(dio: Dio()),
        hive: hive,
      );
      streak.state.value = StreakState.fromJson({'current': 2, 'longest': 4});
      getIt.registerSingleton<StreakService>(streak);

      await pump(tester, const AchievementsPage());
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
      expect(find.text('5 more days to Bronze'), findsOneWidget);

      // The 7-day medal opens the viewer on that tier, with the tier list.
      await tester.tap(find.text('7 d'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('7 days in a row'), findsOneWidget);
      expect(find.text('Bronze · 7 days in a row'), findsOneWidget);
      expect(find.text('Ember · 365 days in a row'), findsOneWidget);
      // Choosing a line in the list shows that tier above it.
      await tester.tap(find.text('Silver · 30 days in a row'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('30 days in a row'), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await tester.pump(const Duration(milliseconds: 500));

      // The card itself opens at the mark being aimed for.
      await tester.tap(find.text('2 days in a row'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('7 days in a row'), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a badge in the feed is a medal card, not an unnamed title', (
      tester,
    ) async {
      final item = ActivityItem.fromJson({
        'id': 'a1',
        'type': 'achieved',
        'provider': 'sozo',
        'achievementId': 'manga_done',
        'achievementTier': 2,
        'at': DateTime.now().toIso8601String(),
      });
      await pump(tester, ActivityCard(item: item, showActor: false));
      expect(tester.takeException(), isNull);
      expect(find.text('Manga master · Silver'), findsOneWidget);
      expect(find.byType(AchievementMedal), findsOneWidget);
      expect(find.text('Unknown'), findsNothing);
    });
  });
}
