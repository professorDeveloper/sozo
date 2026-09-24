import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/features/social/data/social_remote_data_source.dart';
import 'package:soplay/features/social/data/social_service.dart';
import 'package:soplay/features/social/presentation/pages/friends_page.dart';
import 'package:soplay/features/social/presentation/pages/social_privacy_page.dart';

import 'social_fakes.dart';

class _English extends AssetLoader {
  const _English();
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

  late FakeSocialAdapter adapter;

  Future<void> pump(
    WidgetTester tester,
    Widget page,
    Map<String, SocialRoute> routes,
  ) async {
    await getIt.reset();
    adapter = FakeSocialAdapter({
      'GET /api/social/overview': (_) => {
        'friends': 1,
        'incoming': 0,
        'outgoing': 0,
      },
      'GET /api/social/settings': (_) => {
        'visibility': 'friends',
        'shareActivity': false,
        'allowRequests': 'everyone',
      },
      'GET /api/social/feed': (_) => {'items': [], 'nextCursor': null},
      'GET /api/social/friends': (_) => {'items': [], 'nextCursor': null},
      'GET /api/social/requests': (_) => {'dir': 'in', 'items': []},
      ...routes,
    });
    getIt.registerSingleton<SocialService>(
      SocialService(
        remote: SocialRemoteDataSource(dio: fakeDio(adapter)),
        hive: SignedInHive(),
      ),
    );
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en')],
        startLocale: const Locale('en'),
        path: 'assets/translations',
        assetLoader: const _English(),
        saveLocale: false,
        child: Builder(
          builder: (context) => MaterialApp(
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            home: page,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  tearDown(() async => getIt.reset());

  testWidgets('the feed says who did what, with the episode range', (
    tester,
  ) async {
    await pump(tester, const FriendsPage(), {
      'GET /api/social/feed': (_) => {
        'items': [
          activityJson(
            'a1',
            from: 3,
            to: 5,
            actor: userJson('bek', name: 'Bek'),
            title: 'Frieren',
          ),
          activityJson(
            'a2',
            type: 'read',
            mediaType: 'manga',
            from: 12,
            to: 12,
            actor: userJson('lola', name: 'Lola'),
            title: 'Berserk',
          ),
        ],
        'nextCursor': null,
      },
    });

    expect(find.text('Frieren'), findsOneWidget);
    expect(find.text('Episodes 3–5'), findsOneWidget);
    expect(find.text('Berserk'), findsOneWidget);
    expect(find.text('Chapter 12'), findsOneWidget);
    expect(find.textContaining('watched', findRichText: true), findsOneWidget);
    expect(find.textContaining('read', findRichText: true), findsWidgets);
  });

  testWidgets('with no friends the feed points at search, and at sharing', (
    tester,
  ) async {
    await pump(tester, const FriendsPage(), {
      'GET /api/social/overview': (_) => {
        'friends': 0,
        'incoming': 0,
        'outgoing': 0,
      },
    });

    expect(find.text('Your feed is empty'), findsOneWidget);
    expect(find.text('Find friends'), findsOneWidget);
    expect(
      find.text('Your activity is private. Friends can\'t see what you watch.'),
      findsOneWidget,
      reason: 'sharing is off, so the viewer is told their side is private',
    );
  });

  testWidgets('a failed feed offers a retry instead of an empty state', (
    tester,
  ) async {
    await pump(tester, const FriendsPage(), {
      'GET /api/social/feed': (_) => (500, {'message': 'boom'}),
    });
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Quiet for now'), findsNothing);
  });

  testWidgets('an incoming request is accepted from the Requests tab', (
    tester,
  ) async {
    var accepted = false;
    await pump(tester, const FriendsPage(initialTab: FriendsTab.requests), {
      'GET /api/social/overview': (_) => {
        'friends': 0,
        'incoming': accepted ? 0 : 1,
        'outgoing': 0,
      },
      'GET /api/social/requests': (o) => {
        'dir': o.queryParameters['dir'],
        'items': o.queryParameters['dir'] == 'in' && !accepted
            ? [
                {
                  'id': 'r1',
                  'direction': 'in',
                  'user': userJson('aziz', name: 'Aziz'),
                  'createdAt': DateTime.now().toUtc().toIso8601String(),
                },
              ]
            : [],
      },
      'POST /api/social/requests/r1/accept': (_) {
        accepted = true;
        return {'relation': 'friends', 'user': userJson('aziz', name: 'Aziz')};
      },
    });

    expect(find.text('Requests · 1'), findsOneWidget);
    expect(find.text('Aziz'), findsOneWidget);
    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();

    expect(accepted, isTrue);
    expect(find.text('Aziz'), findsNothing);
    expect(find.text('You\'re now friends with Aziz'), findsOneWidget);
    expect(find.text('Requests'), findsOneWidget, reason: 'badge cleared');
  });

  testWidgets('sharing is only turned on after the explainer is confirmed', (
    tester,
  ) async {
    await pump(tester, const SocialPrivacyPage(), {
      'PUT /api/social/settings': (o) => {
        'visibility': 'friends',
        'shareActivity': (o.data as Map)['shareActivity'],
        'allowRequests': 'everyone',
      },
    });

    final toggle = find.byType(Switch);
    expect(tester.widget<Switch>(toggle).value, isFalse);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('Share your activity?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(adapter.requests.where((r) => r.method == 'PUT'), isEmpty);
    expect(tester.widget<Switch>(toggle).value, isFalse);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Share'));
    await tester.pumpAndSettle();
    final put = adapter.requests.singleWhere((r) => r.method == 'PUT');
    expect(put.data, {'shareActivity': true});
    expect(tester.widget<Switch>(toggle).value, isTrue);
  });
}
