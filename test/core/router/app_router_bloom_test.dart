import 'package:flutter/foundation.dart'
    show
        TargetPlatform,
        debugDefaultTargetPlatformOverride,
        defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/router/app_router.dart';
import 'package:soplay/core/theme/app_theme.dart';
import 'package:soplay/core/widgets/bloom_page_transition.dart';
import 'package:soplay/features/detail/domain/entities/detail_args.dart';
import 'package:soplay/features/detail/domain/entities/episodes_args.dart';
import 'package:soplay/features/detail/presentation/pages/actor_page.dart';
import 'package:soplay/features/home/domain/entities/view_all.dart';
import 'package:soplay/features/user_lists/domain/entities/user_list_kind.dart';

/// Every route that opens a thing, with the `extra` its `pageBuilder` insists
/// on: each of them casts `state.extra` before it ever asks for a page, so the
/// wrong type here fails the test somewhere other than where it means to.
final _opening = <String, Object?>{
  '/view-all': ViewAllEntity(slug: 'trending', type: 'movie', name: 'Trending'),
  '/detail': const DetailArgs(contentUrl: 'https://example.test/title'),
  '/episodes': const EpisodesArgs(title: 'Title', episodes: []),
  '/my-lists': UserListKind.watchLater,
  '/actor': const ActorArgs(name: 'Someone'),
};

GoRoute _routeAt(String path) => AppRouter.router.configuration.routes
    .whereType<GoRoute>()
    .firstWhere((route) => route.path == path);

/// Asks a route for the page it would push, without going near the navigator.
///
/// Calling the `pageBuilder` directly is the only way to see the decision: the
/// five pages themselves want repositories, blocs and a network, so a test that
/// actually navigated to one would be testing dependency injection instead of
/// the transition.
Page<Object?> _pageFor(BuildContext context, String path) {
  final builder = _routeAt(path).pageBuilder;
  expect(
    builder,
    isNotNull,
    reason:
        '$path builds its own Page — a plain builder: means the shared '
        'arrival (and the platform choice inside it) has been lost',
  );
  return builder!(
    context,
    GoRouterState(
      AppRouter.router.configuration,
      uri: Uri.parse(path),
      matchedLocation: path,
      path: path,
      fullPath: path,
      pathParameters: const {},
      extra: _opening[path],
      pageKey: ValueKey<String>(path),
    ),
  );
}

Future<BuildContext> _pumpContext(WidgetTester tester) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Builder(
        builder: (context) {
          captured = context;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return captured;
}

/// Runs [body] as if the app were on [platform], and puts the override back
/// before the test ends.
///
/// Reset here rather than in an `addTearDown`: the test binding checks that no
/// foundation debug variable survived the body, and it checks before tear-downs
/// run, so a tear-down reset fails every test that uses one.
Future<void> _onPlatform(
  TargetPlatform platform,
  Future<void> Function() body,
) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  group('the opening routes', () {
    testWidgets('hand back the platform page on iOS', (tester) async {
      await _onPlatform(TargetPlatform.iOS, () async {
        final context = await _pumpContext(tester);
        for (final path in _opening.keys) {
          final page = _pageFor(context, path);
          // A CustomTransitionPage brings its own transitionsBuilder and so
          // never consults the PageTransitionsTheme — which on iOS is where
          // the back-gesture detector comes from. Anything but a plain page
          // here costs the edge swipe.
          expect(page, isA<MaterialPage<void>>(), reason: path);
          expect(page, isNot(isA<CustomTransitionPage<void>>()), reason: path);
        }
      });
    });

    for (final platform in const [
      TargetPlatform.android,
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    ]) {
      testWidgets('bloom on $platform', (tester) async {
        await _onPlatform(platform, () async {
          final context = await _pumpContext(tester);
          for (final path in _opening.keys) {
            final page = _pageFor(context, path);
            expect(page, isA<CustomTransitionPage<void>>(), reason: path);

            final custom = page as CustomTransitionPage<void>;
            expect(custom.transitionDuration, BloomPageTransition.duration);
            expect(
              custom.reverseTransitionDuration,
              BloomPageTransition.reverseDuration,
            );
            expect(
              custom.transitionsBuilder(
                context,
                kAlwaysCompleteAnimation,
                kAlwaysDismissedAnimation,
                const SizedBox.shrink(),
              ),
              isA<BloomPageTransition>(),
              reason: path,
            );
          }
        });
      });
    }

    testWidgets('differ between iOS and Android in the transition only', (
      tester,
    ) async {
      // The split itself, pinned from both sides at once: same route, same
      // state, two platforms, and the ONLY thing allowed to come back
      // different is the kind of page.
      //
      // The four assertions below are what the iOS branch is easy to get
      // wrong. It is a second, hand-written `MaterialPage` rather than a
      // fall-through to go_router's own, so a key, a name or a restorationId
      // left off it costs that platform its page identity, its analytics
      // screen name or its restored navigation stack — and every other test
      // in this group looks at one platform at a time and would not see it.
      for (final path in _opening.keys) {
        late Page<Object?> cupertino;
        late Page<Object?> bloomed;
        await _onPlatform(TargetPlatform.iOS, () async {
          cupertino = _pageFor(await _pumpContext(tester), path);
        });
        await _onPlatform(TargetPlatform.android, () async {
          bloomed = _pageFor(await _pumpContext(tester), path);
        });

        expect(
          cupertino.runtimeType,
          isNot(bloomed.runtimeType),
          reason:
              '$path: both platforms got the same page, so the helper is not '
              'branching at all and iOS is back to losing the edge swipe',
        );
        expect(cupertino.key, bloomed.key, reason: path);
        expect(cupertino.name, bloomed.name, reason: path);
        expect(
          cupertino.restorationId,
          bloomed.restorationId,
          reason: path,
        );
        expect(cupertino.restorationId, isNotNull, reason: path);
      }
    });

    testWidgets('keep a screen name for the analytics observer', (
      tester,
    ) async {
      // go_router names the page it builds for a `builder:`; a hand-built one
      // is nameless unless it is told, and FirebaseAnalyticsObserver logs
      // nothing for a nameless route. True on both sides of the platform split.
      for (final platform in const [
        TargetPlatform.iOS,
        TargetPlatform.android,
      ]) {
        await _onPlatform(platform, () async {
          final context = await _pumpContext(tester);
          for (final path in _opening.keys) {
            expect(
              _pageFor(context, path).name,
              path,
              reason: '$platform $path',
            );
          }
        });
      }
    });
  });

  test('/player and /reader stay out of the shared arrival', () {
    // They are a change of mode rather than a thing being opened, and they
    // bring their own transitions; a pageBuilder here would mean one of them
    // had been swept into the helper.
    for (final path in const ['/player', '/reader']) {
      expect(_routeAt(path).pageBuilder, isNull, reason: path);
    }
  });

  testWidgets('a platform page on iOS is what carries the back swipe', (
    tester,
  ) async {
    // The whole reason the five routes give up the bloom on iOS. If the app's
    // theme ever stops leaving iOS to CupertinoPageTransitionsBuilder, the
    // trade buys nothing and this fails.
    await _onPlatform(TargetPlatform.iOS, () async {
      final pages = <Page<void>>[
        const MaterialPage<void>(child: Text('behind')),
        const MaterialPage<void>(child: Text('opened')),
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: StatefulBuilder(
            builder: (context, setState) => Navigator(
              pages: List<Page<void>>.of(pages),
              onDidRemovePage: (page) => setState(() => pages.remove(page)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('opened'), findsOneWidget);

      final swipeable = pages.last.runtimeType;
      final swipe = await tester.startGesture(const Offset(2, 300));
      await swipe.moveBy(const Offset(150, 0));
      await tester.pump();
      await swipe.moveBy(const Offset(300, 0));
      await tester.pump();
      await swipe.up();
      await tester.pumpAndSettle();

      expect(find.text('opened'), findsNothing);
      expect(find.text('behind'), findsOneWidget);

      // Ties the demonstration to the thing being demonstrated. Everything
      // above this line is about a page built by hand in this test, and would
      // go on passing if the helper started blooming iOS again tomorrow. What
      // makes it evidence is that the helper hands back a page of the same
      // kind as the one the swipe just dismissed.
      for (final path in _opening.keys) {
        expect(
          _pageFor(tester.element(find.text('behind')), path).runtimeType,
          swipeable,
          reason: path,
        );
      }
    });
  });

  testWidgets('the app theme leaves TargetPlatform alone', (tester) async {
    // The helper branches on `defaultTargetPlatform`. The widget that actually
    // installs the Cupertino back-gesture detector is chosen by
    // `Theme.of(context).platform`, inside `PageTransitionsTheme.buildTransitions`.
    // Those are the same value only because `AppTheme` passes no `platform:`
    // and `ThemeData` then defaults the field to `defaultTargetPlatform`.
    //
    // Override it — the usual reason is to force one platform's transitions
    // everywhere, or to make desktop behave like Android — and the two halves
    // of this fix come apart silently: the helper still hands iOS a plain
    // page, the theme no longer wraps it in a back gesture, and iOS ends up
    // with neither the bloom it gave up nor the swipe it gave it up for. Every
    // other test in this file would still pass, because every other test asks
    // the helper what it built and never asks the theme what it will do with
    // it.
    for (final platform in const [TargetPlatform.iOS, TargetPlatform.android]) {
      await _onPlatform(platform, () async {
        final context = await _pumpContext(tester);
        expect(
          Theme.of(context).platform,
          defaultTargetPlatform,
          reason:
              'AppTheme.dark pins platform to ${Theme.of(context).platform}; '
              'the page type and the back gesture no longer agree',
        );
      });
    }
  });
}
