import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/system/platform_utils.dart';
import 'package:soplay/features/onboarding/data/genre_catalog.dart';
import 'package:soplay/features/onboarding/data/onboarding_store.dart';
import 'package:soplay/features/onboarding/domain/onboarding_flow.dart';
import 'package:soplay/features/onboarding/domain/taste_profile.dart';
import 'package:soplay/features/onboarding/presentation/controllers/onboarding_controller.dart';
import 'package:soplay/features/onboarding/presentation/pages/onboarding_genres_page.dart';
import 'package:soplay/features/onboarding/presentation/pages/onboarding_kinds_page.dart';
import 'package:soplay/features/onboarding/presentation/pages/onboarding_notifications_page.dart';
import 'package:soplay/features/notifications/data/services/notification_service.dart';
import 'package:soplay/features/notifications/domain/repositories/notifications_repository.dart';
import 'package:soplay/features/search/data/model/genre_model.dart';

class _Repo implements NotificationsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BrokenNotifications extends NotificationService {
  _BrokenNotifications() : super(repository: _Repo());

  @override
  Future<bool> requestPermission() async => throw StateError('no plugin');
}

GenreModel _g(String slug, String provider) =>
    GenreModel(provider: provider, slug: slug, url: '', image: '');

void main() {
  late OnboardingController controller;
  late List<String> asked;
  late GenreCatalog catalog;

  GenreCatalog makeCatalog() => GenreCatalog(
    fetch: (catalogue) async {
      asked.add(catalogue);
      return catalogue == 'tmdb'
          ? [_g('action', 'cat:tmdb'), _g('war', 'cat:tmdb')]
          : [
              _g('action', 'cat:anilist'),
              _g('romance', 'cat:anilist'),
              _g('mecha', 'cat:anilist'),
              _g('ecchi', 'cat:anilist'),
            ];
    },
  );

  setUp(() async {
    asked = [];
    catalog = makeCatalog();
    await getIt.reset();
    controller = OnboardingController(
      store: MemoryOnboardingStore(),
      isSignedIn: () => false,
    );
    getIt.registerSingleton<OnboardingController>(controller);
    await controller.begin(OnboardingFlow.firstRun);
    await controller.advance();
    await controller.advance();
  });

  tearDown(() async {
    debugSetTvPlatform(false);
    await getIt.reset();
  });

  Widget app(String start) => MaterialApp.router(
    routerConfig: GoRouter(
      initialLocation: start,
      routes: [
        GoRoute(
          path: '/onboarding/kinds',
          builder: (_, _) => const OnboardingKindsPage(),
        ),
        GoRoute(
          path: '/onboarding/genres',
          builder: (_, _) => OnboardingGenresPage(catalog: catalog),
        ),
        GoRoute(
          path: '/onboarding/account',
          builder: (_, _) => const Scaffold(body: Text('ACCOUNT')),
        ),
      ],
    ),
  );

  ElevatedButton button(WidgetTester tester) =>
      tester.widget<ElevatedButton>(find.byType(ElevatedButton).last);

  group('kinds', () {
    testWidgets('offers four kinds and needs at least one', (tester) async {
      await tester.pumpWidget(app('/onboarding/kinds'));
      await tester.pumpAndSettle();

      expect(find.byType(KindCard), findsNWidgets(4));
      expect(find.text('onboarding.kinds_pick_one'), findsOneWidget);
      expect(button(tester).onPressed, isNull);

      await tester.tap(find.byType(KindCard).at(2));
      await tester.pumpAndSettle();
      expect(controller.kinds, [TasteKind.manga]);
      expect(find.text('onboarding.continue'), findsOneWidget);
      expect(button(tester).onPressed, isNotNull);

      await tester.tap(find.byType(KindCard).at(2));
      await tester.pumpAndSettle();
      expect(controller.kinds, isEmpty);
      expect(button(tester).onPressed, isNull);
    });

    testWidgets('several can be picked and the first is marked', (
      tester,
    ) async {
      await tester.pumpWidget(app('/onboarding/kinds'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(KindCard).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(KindCard).at(0));
      await tester.pumpAndSettle();
      expect(controller.kinds, [TasteKind.movies, TasteKind.anime]);
      expect(find.text('onboarding.kinds_starts_here'), findsOneWidget);
      final cards = tester.widgetList<KindCard>(find.byType(KindCard));
      expect(cards.where((c) => c.selected).length, 2);
      expect(cards.singleWhere((c) => c.primary).kind, TasteKind.movies);
    });

    testWidgets('continuing with a kind opens genres', (tester) async {
      await tester.pumpWidget(app('/onboarding/kinds'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(KindCard).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('onboarding.continue'));
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingGenresPage), findsOneWidget);
      expect(controller.step, OnboardingStep.genres);
    });

    testWidgets('a double tap on Continue moves one step, not two', (
      tester,
    ) async {
      await controller.toggleKind(TasteKind.anime);
      await tester.pumpWidget(app('/onboarding/kinds'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('onboarding.continue'));
      await tester.tap(find.text('onboarding.continue'));
      await tester.pumpAndSettle();

      expect(controller.step, OnboardingStep.genres);
      expect(find.text('ACCOUNT', skipOffstage: false), findsNothing);
      await tester.tap(find.byType(GenreChip).first);
      await tester.tap(find.byType(GenreChip).at(1));
      await tester.tap(find.byType(GenreChip).at(2));
      await tester.pumpAndSettle();
      await tester.tap(find.text('onboarding.continue'));
      await tester.tap(find.text('onboarding.continue'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(controller.step, OnboardingStep.account);
      expect(find.text('ACCOUNT'), findsOneWidget);
    });

    testWidgets('on a TV the remote picks kinds without touch', (tester) async {
      debugSetTvPlatform(true);
      await tester.pumpWidget(app('/onboarding/kinds'));
      await tester.pumpAndSettle();

      // The first card has focus from the start.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(controller.kinds, [TasteKind.anime]);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(controller.kinds, [TasteKind.anime, TasteKind.movies]);
    });
  });

  group('genres', () {
    testWidgets('merges the picked kinds and needs three', (tester) async {
      await controller.toggleKind(TasteKind.anime);
      await controller.toggleKind(TasteKind.movies);
      await controller.advance();
      await tester.pumpWidget(app('/onboarding/genres'));
      await tester.pumpAndSettle();

      expect(asked.toSet(), {'anilist', 'tmdb'});
      // action from both catalogues is one chip; ecchi is not offered.
      expect(find.byType(GenreChip), findsNWidgets(4));
      final action = tester
          .widgetList<GenreChip>(find.byType(GenreChip))
          .firstWhere((c) => c.genre.slug == 'action');
      expect(action.genre.catalogues, {'anilist', 'tmdb'});

      Future<void> tap(String slug) async {
        await tester.tap(
          find.byWidgetPredicate((w) => w is GenreChip && w.genre.slug == slug),
        );
        await tester.pumpAndSettle();
      }

      await tap('action');
      await tap('war');
      expect(controller.genres.length, 2);
      expect(button(tester).onPressed, isNull);
      expect(find.text('onboarding.genres_pick_more'), findsOneWidget);

      await tap('mecha');
      expect(controller.canLeaveGenres, isTrue);
      expect(button(tester).onPressed, isNotNull);

      await tap('war');
      expect(controller.genres.map((g) => g.slug), ['action', 'mecha']);
      expect(button(tester).onPressed, isNull);
    });

    testWidgets('falls back to the usual genres offline', (tester) async {
      await controller.toggleKind(TasteKind.manga);
      await controller.advance();
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: GoRouter(
            initialLocation: '/g',
            routes: [
              GoRoute(
                path: '/g',
                builder: (_, _) => OnboardingGenresPage(
                  catalog: GenreCatalog(
                    fetch: (_) async => throw StateError('offline'),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('onboarding.genres_offline'), findsOneWidget);
      expect(
        find.byType(GenreChip),
        findsNWidgets(GenreCatalog.fallbackFor('anilist-manga').length),
      );
    });
  });

  testWidgets('notifications move on even when asking fails', (tester) async {
    getIt.registerSingleton<NotificationService>(_BrokenNotifications());
    await controller.arrive(OnboardingStep.notifications);
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: '/onboarding/notifications',
          routes: [
            GoRoute(
              path: '/onboarding/notifications',
              builder: (_, _) => const OnboardingNotificationsPage(),
            ),
            GoRoute(
              path: '/onboarding/badges',
              builder: (_, _) => const Scaffold(body: Text('DONE')),
            ),
          ],
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('onboarding.notify_allow'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(tester.takeException(), isNull);
    expect(controller.notificationsOn, isFalse);
    expect(find.text('DONE'), findsOneWidget);
  });
}
