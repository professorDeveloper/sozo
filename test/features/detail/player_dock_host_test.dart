// The desktop corner player moves the live player page — its State, timers,
// controller and all — out of /player and into a layer above the Navigator,
// and back, under one GlobalKey. Nothing is copied or restarted, so the one
// thing that must never happen is the State being disposed and created again
// on the way. These tests use a probe in place of the real PlayerPage (which
// needs the service locator, Hive and a video engine) and count exactly that.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/player/player_dock.dart';
import 'package:soplay/features/detail/domain/entities/player_args.dart';
import 'package:soplay/features/detail/presentation/pages/player_route.dart';
import 'package:soplay/features/detail/presentation/widgets/player_dock_host.dart';

final List<String> _events = [];

/// Stands in for PlayerPage: records its lifecycle, holds a piece of state
/// that must survive, and docks the way the page does.
class _Probe extends StatefulWidget {
  const _Probe({super.key, required this.args});

  final PlayerArgs args;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  int ticks = 0;
  final FocusNode keys = FocusNode(debugLabel: 'probeKeys');

  @override
  void initState() {
    super.initState();
    _events.add('init:${widget.args.title}');
  }

  @override
  void dispose() {
    _events.add('dispose:${widget.args.title}');
    keys.dispose();
    super.dispose();
  }

  /// What PlayerPage._dockToCorner does, minus the player.
  void dock() {
    PlayerDock.instance.dock(
      key: widget.key! as GlobalKey,
      args: widget.args,
      videoSize: const Size(1920, 1080),
    );
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final dock = PlayerDock.instance;
    // As PlayerPage: a key handler that lets Esc through while docked, and a
    // click on the player that takes the keyboard.
    return Focus(
      focusNode: keys,
      onKeyEvent: (_, e) => KeyEventResult.ignored,
      child: Listener(
        onPointerDown: (_) => keys.requestFocus(),
        child: _body(dock),
      ),
    );
  }

  Widget _body(PlayerDock dock) {
    return ColoredBox(
      color: Colors.black,
      // The real page's corner overlay drives the drag the same way.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => dock.dragStart(),
        onPanUpdate: (d) => dock.dragBy(d.delta),
        onPanEnd: (d) => dock.dragEnd(d.velocity.pixelsPerSecond),
        child: Center(
          child: Text(
            'probe ${widget.args.title} $ticks',
            style: const TextStyle(fontSize: 10),
          ),
        ),
      ),
    );
  }
}

/// Something on the page under the player that holds the keyboard.
FocusNode? _homeField;

class _Screen extends StatelessWidget {
  const _Screen(this.name);

  final String name;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Focus(
        focusNode: name == 'home' ? _homeField : null,
        child: Text('screen $name'),
      ),
    ),
  );
}

PlayerArgs _args(String title) =>
    PlayerArgs(title: title, provider: 'test', headers: const {});

Widget _probe(GlobalKey key, PlayerArgs args) => _Probe(key: key, args: args);

GoRouter _router() => GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, _) => const _Screen('home')),
    GoRoute(path: '/other', builder: (_, _) => const _Screen('other')),
    GoRoute(path: '/login', builder: (_, _) => const _Screen('login')),
    GoRoute(
      path: '/player',
      builder: (_, state) =>
          PlayerRoute(args: state.extra! as PlayerArgs, pageBuilder: _probe),
    ),
  ],
);

const _area = Size(1200, 800);
const _m = DockGeometry.margin;

Future<GoRouter> _pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = _area;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = _router();
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MaterialApp.router(
      routerConfig: router,
      builder: (context, child) =>
          PlayerDockHost(router: router, pageBuilder: _probe, child: child!),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

/// The location on top of the stack. Not `uri`: go_router keeps that at the
/// base location for an imperative push.
String _path(GoRouter router) =>
    router.routerDelegate.currentConfiguration.last.matchedLocation;

Finder get _frame => find.byKey(PlayerDockHost.frameKey);

Finder get _inFrame =>
    find.descendant(of: _frame, matching: find.byType(_Probe));

_ProbeState _state(WidgetTester tester) =>
    tester.state<_ProbeState>(find.byType(_Probe));

/// Opens "A" in /player, gives it some state, and docks it.
Future<void> _openAndDock(WidgetTester tester, GoRouter router) async {
  unawaited(router.push('/player', extra: _args('A')));
  await tester.pumpAndSettle();
  final s = _state(tester);
  // ignore: invalid_use_of_protected_member
  s.setState(() => s.ticks = 3);
  s.dock();
  await tester.pump();
  expect(tester.takeException(), isNull);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    _events.clear();
    _homeField = null;
    PlayerDock.instance.debugReset();
  });
  tearDown(PlayerDock.instance.debugReset);

  testWidgets('nothing in the corner until a page docks', (tester) async {
    final router = await _pumpApp(tester);
    expect(_frame, findsNothing);
    unawaited(router.push('/player', extra: _args('A')));
    await tester.pumpAndSettle();
    expect(_frame, findsNothing);
    expect(find.byType(_Probe), findsOneWidget);
  });

  testWidgets(
    'docking moves the same State into the corner and leaves the route',
    (tester) async {
      final router = await _pumpApp(tester);
      await _openAndDock(tester, router);

      expect(_path(router), '/');
      expect(find.text('screen home'), findsOneWidget);
      expect(_inFrame, findsOneWidget);
      expect(find.byType(_Probe), findsOneWidget);
      // Created once, never disposed, and still holding what it held.
      expect(_events, ['init:A']);
      expect(find.text('probe A 3'), findsOneWidget);
      expect(PlayerDock.instance.isDocked, isTrue);

      // Settled in the default corner, at the picture's shape.
      expect(
        tester.getRect(_frame),
        const Rect.fromLTWH(
          1200 - DockGeometry.defaultWidth - _m,
          800 - 225 - _m,
          DockGeometry.defaultWidth,
          225,
        ),
      );

      // The page finds a Navigator and the router where it now lives, so a
      // Tooltip, a dialog or an app navigation from inside it does not throw.
      final ctx = tester.element(find.byType(_Probe));
      expect(Navigator.maybeOf(ctx), isNotNull);
      expect(GoRouter.maybeOf(ctx), same(router));
      expect(ScaffoldMessenger.maybeOf(ctx), isNotNull);
    },
    variant: TargetPlatformVariant.desktop(),
  );

  testWidgets('it keeps playing while the pages under it change', (
    tester,
  ) async {
    final router = await _pumpApp(tester);
    await _openAndDock(tester, router);

    router.go('/other');
    await tester.pumpAndSettle();
    expect(find.text('screen other'), findsOneWidget);
    expect(_inFrame, findsOneWidget);

    unawaited(router.push('/'));
    await tester.pumpAndSettle();
    router.pop();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(_inFrame, findsOneWidget);
    expect(_events, ['init:A']);
    expect(find.text('probe A 3'), findsOneWidget);
  });

  testWidgets(
    'expanding hands the same State back to a /player route',
    (tester) async {
      final router = await _pumpApp(tester);
      await _openAndDock(tester, router);
      router.go('/other');
      await tester.pumpAndSettle();

      PlayerDock.instance.expand();
      await tester.pump();
      expect(tester.takeException(), isNull);
      // Already in the new route in that same frame — offstage while the
      // hero controller measures it, but mounted — and not recreated.
      expect(_frame, findsNothing);
      expect(find.byType(_Probe, skipOffstage: false), findsOneWidget);
      expect(_events, ['init:A']);
      await tester.pumpAndSettle();

      expect(_path(router), '/player');
      expect(_frame, findsNothing);
      expect(find.byType(_Probe), findsOneWidget);
      expect(_events, ['init:A']);
      expect(find.text('probe A 3'), findsOneWidget);
      expect(PlayerDock.instance.isDocked, isFalse);

      // And back to the corner again from there.
      _state(tester).dock();
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(_path(router), '/other');
      expect(_inFrame, findsOneWidget);
      expect(_events, ['init:A']);
    },
    variant: TargetPlatformVariant.desktop(),
  );

  testWidgets('Esc in the corner gives the keyboard back to the page', (
    tester,
  ) async {
    _homeField = FocusNode(debugLabel: 'home');
    final router = await _pumpApp(tester);
    await _openAndDock(tester, router);
    _homeField!.requestFocus();
    await tester.pump();
    expect(_homeField!.hasFocus, isTrue);

    // A click on the player takes the keyboard…
    await tester.tapAt(tester.getRect(_frame).center);
    await tester.pumpAndSettle();
    final keys = _state(tester).keys;
    expect(keys.hasFocus, isTrue);

    // …and Esc hands it back, without closing the player or popping the
    // page underneath.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(keys.hasFocus, isFalse);
    expect(_homeField!.hasFocus, isTrue);
    expect(_inFrame, findsOneWidget);
    expect(_path(router), '/');

    // A click elsewhere does the same.
    await tester.tapAt(tester.getRect(_frame).center);
    await tester.pump();
    expect(keys.hasFocus, isTrue);
    await tester.tapAt(const Offset(40, 40));
    await tester.pump();
    expect(keys.hasFocus, isFalse);
    expect(_events, ['init:A']);
  });

  group('acting while the left route still animates away', () {
    /// Opens "A" and docks it, stopping mid exit transition.
    Future<void> dockMidway(WidgetTester tester, GoRouter router) async {
      unawaited(router.push('/player', extra: _args('A')));
      await tester.pumpAndSettle();
      _state(tester).dock();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
    }

    testWidgets('restoring at once keeps one page', (tester) async {
      final router = await _pumpApp(tester);
      await dockMidway(tester, router);

      PlayerDock.instance.expand();
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();

      expect(_path(router), '/player');
      expect(find.byType(_Probe), findsOneWidget);
      expect(_events, ['init:A']);
    }, variant: TargetPlatformVariant.desktop());

    testWidgets(
      'closing at once disposes it, and it stays gone',
      (tester) async {
        final router = await _pumpApp(tester);
        await dockMidway(tester, router);

        unawaited(PlayerDock.instance.close());
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.pumpAndSettle();

        expect(find.byType(_Probe, skipOffstage: false), findsNothing);
        expect(_events, ['init:A', 'dispose:A']);
      },
      variant: TargetPlatformVariant.desktop(),
    );

    testWidgets(
      'another title disposes the docked one before it starts',
      (tester) async {
        final router = await _pumpApp(tester);
        await dockMidway(tester, router);

        unawaited(router.push('/player', extra: _args('B')));
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.pumpAndSettle();

        expect(_events, ['init:A', 'dispose:A', 'init:B']);
        expect(find.text('probe B 0'), findsOneWidget);
      },
      variant: TargetPlatformVariant.desktop(),
    );
  });

  testWidgets('closing disposes the page', (tester) async {
    final router = await _pumpApp(tester);
    await _openAndDock(tester, router);

    unawaited(PlayerDock.instance.close());
    await tester.pumpAndSettle();

    expect(_frame, findsNothing);
    expect(find.byType(_Probe), findsNothing);
    expect(_events, ['init:A', 'dispose:A']);
    expect(PlayerDock.instance.isDocked, isFalse);
  });

  testWidgets('a drag moves it and the release snaps to the nearest corner', (
    tester,
  ) async {
    final router = await _pumpApp(tester);
    await _openAndDock(tester, router);
    final start = tester.getRect(_frame);

    final gesture = await tester.startGesture(start.center);
    await gesture.moveBy(const Offset(-30, 0));
    await gesture.moveBy(const Offset(-200, -100));
    await tester.pump();
    // It follows the pointer while held.
    final held = tester.getRect(_frame);
    expect(held.left, lessThan(start.left - 150));
    expect(held.top, lessThan(start.top - 50));

    // Let go well into the top-left quarter.
    await gesture.moveBy(const Offset(-500, -300));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(PlayerDock.instance.corner, DockCorner.topLeft);
    expect(
      tester.getRect(_frame),
      const Rect.fromLTWH(_m, _m, DockGeometry.defaultWidth, 225),
    );
    expect(_events, ['init:A']);
  });

  testWidgets('the inner edge resizes it within bounds', (tester) async {
    final router = await _pumpApp(tester);
    await _openAndDock(tester, router);
    final start = tester.getRect(_frame);

    // Docked bottom-right, so the grip is the left edge.
    await tester.dragFrom(
      Offset(start.left + 2, start.center.dy),
      const Offset(-100, 0),
    );
    await tester.pumpAndSettle();
    final grown = tester.getRect(_frame);
    expect(grown.width, closeTo(start.width + 100, 1));
    // Still anchored to its corner.
    expect(grown.right, closeTo(1200 - _m, 0.5));
    expect(grown.bottom, closeTo(800 - _m, 0.5));

    // Far past the limit stops at the share of the window.
    await tester.dragFrom(
      Offset(grown.left + 2, grown.center.dy),
      const Offset(-2000, 0),
    );
    await tester.pumpAndSettle();
    expect(tester.getRect(_frame).width, 1200 * DockGeometry.maxShare);
    expect(_events, ['init:A']);
  });

  testWidgets(
    'opening another title closes the docked one before the new one starts',
    (tester) async {
      final router = await _pumpApp(tester);
      await _openAndDock(tester, router);

      unawaited(router.push('/player', extra: _args('B')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // The old page's dispose runs first: it tears down page-wide
      // singletons the new one would otherwise have just set up.
      expect(_events, ['init:A', 'dispose:A', 'init:B']);
      expect(_frame, findsNothing);
      expect(find.text('probe B 0'), findsOneWidget);
    },
  );

  testWidgets('signing out closes it', (tester) async {
    final router = await _pumpApp(tester);
    await _openAndDock(tester, router);

    router.go('/login');
    await tester.pumpAndSettle();

    expect(_frame, findsNothing);
    expect(_events, ['init:A', 'dispose:A']);
  });

  testWidgets('a pushed sign-in page closes it too', (tester) async {
    final router = await _pumpApp(tester);
    await _openAndDock(tester, router);

    unawaited(router.push('/login'));
    await tester.pumpAndSettle();

    expect(_frame, findsNothing);
    expect(_events, ['init:A', 'dispose:A']);
  });

  test('the routes that close it', () {
    expect(playerDockClosesOn('/login'), isTrue);
    expect(playerDockClosesOn('/splash'), isTrue);
    expect(playerDockClosesOn('/profiles'), isTrue);
    expect(playerDockClosesOn('/onboarding'), isTrue);
    expect(playerDockClosesOn('/onboarding/genres'), isTrue);
    expect(playerDockClosesOn('/main'), isFalse);
    expect(playerDockClosesOn('/detail'), isFalse);
    expect(playerDockClosesOn('/profiles/manage'), isFalse);
  });
}
