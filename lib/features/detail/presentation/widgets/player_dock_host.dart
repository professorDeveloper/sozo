import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/player/player_dock.dart';
import 'package:soplay/core/router/app_router.dart';
import 'package:soplay/features/detail/domain/entities/player_args.dart';
import 'package:soplay/features/detail/presentation/pages/player_route.dart';

/// Where the corner player belongs to the session that started it: signing
/// out, switching profile or starting over closes it.
bool playerDockClosesOn(String path) =>
    path == '/login' ||
    path == '/splash' ||
    path == '/profiles' ||
    path == '/onboarding' ||
    path.startsWith('/onboarding/');

/// The desktop corner player's home: a layer above the app's Navigator, so
/// the player stays while the pages under it change.
///
/// The docked PlayerPage is the same element, with the same State, that was
/// playing in /player a frame earlier — see [PlayerDock]. Here it gets a
/// rounded, shadowed box in one corner of the content area, which it can be
/// dragged out of (it snaps to the nearest corner on release) and resized
/// from the edges that face the middle of the window.
class PlayerDockHost extends StatefulWidget {
  const PlayerDockHost({
    super.key,
    required this.child,
    this.router,
    this.pageBuilder = defaultPlayerPageBuilder,
  });

  final Widget child;

  /// The app's router; [AppRouter.router] unless a test brings its own.
  final GoRouter? router;
  final PlayerPageBuilder pageBuilder;

  /// Wraps the docked page's box; widget tests find the corner player by it.
  static const Key frameKey = ValueKey('player-dock-frame');

  @override
  State<PlayerDockHost> createState() => _PlayerDockHostState();
}

class _PlayerDockHostState extends State<PlayerDockHost>
    with SingleTickerProviderStateMixin {
  final PlayerDock _dock = PlayerDock.instance;
  late final GoRouter _router = widget.router ?? AppRouter.router;

  /// Drives both moves the box makes on its own: shrinking from the full
  /// window into its corner when a page docks, and gliding to the corner it
  /// snapped to after a drag.
  late final AnimationController _move = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );

  /// Where the current move started, given the area: the full area for a
  /// page arriving, the drop point for a snap. Null when nothing is moving.
  Rect Function(Size area)? _from;

  GlobalKey? _shown;
  bool _wasDragging = false;

  /// Owns the keyboard while the viewer is using the corner player, and gives
  /// it back to the page underneath on a click anywhere else.
  final FocusScopeNode _scope = FocusScopeNode(debugLabel: 'playerDock');

  void _open(PlayerArgs args) => _router.push('/player', extra: args);

  @override
  void initState() {
    super.initState();
    _dock.openRoute = _open;
    _dock.addListener(_onDock);
    _dock.geometry.addListener(_onGeometry);
    _move.addStatusListener((s) {
      if (s == AnimationStatus.completed) _from = null;
    });
    _router.routerDelegate.addListener(_closeOnSessionChange);
    _shown = _dock.dockedKey;
  }

  @override
  void dispose() {
    _dock.removeListener(_onDock);
    _dock.geometry.removeListener(_onGeometry);
    if (_dock.openRoute == _open) _dock.openRoute = null;
    _router.routerDelegate.removeListener(_closeOnSessionChange);
    _move.dispose();
    _scope.dispose();
    super.dispose();
  }

  /// Synchronous with the notify on purpose: the route that gave the page up
  /// rebuilds in the same frame, and the GlobalKey has to land here in that
  /// frame or the page is disposed.
  void _onDock() {
    final key = _dock.dockedKey;
    if (key == _shown) return;
    _shown = key;
    if (key != null) {
      // The Telegram move, and the visible half of the hand-off: the picture
      // starts where the full player was and shrinks into its corner.
      _from = (area) => Offset.zero & area;
      _move.forward(from: 0);
    } else {
      _from = null;
      _move.stop();
    }
    setState(() {});
  }

  void _onGeometry() {
    final dragging = _dock.dragging;
    if (_wasDragging && !dragging) {
      final start = _dock.lastRect;
      if (start != null) {
        _from = (_) => start;
        _move.forward(from: 0);
      }
    } else if (dragging && _move.isAnimating) {
      _move.stop();
      _from = null;
    }
    _wasDragging = dragging;
  }

  void _closeOnSessionChange() {
    if (!_dock.isDocked) return;
    final paths = <String>[];
    try {
      final config = _router.routerDelegate.currentConfiguration;
      paths.add(config.uri.path);
      // A push leaves `uri` at the location it was pushed from; the top
      // match is where the viewer actually is.
      if (config.isNotEmpty) paths.add(config.last.matchedLocation);
    } catch (_) {
      return;
    }
    if (!paths.any(playerDockClosesOn)) return;
    // Not from inside the router's own notification, which can arrive while
    // the tree is being built.
    scheduleMicrotask(() => unawaited(_dock.close()));
  }

  /// The box this frame should occupy in [area]. Called during layout only.
  Rect _rectIn(Size area) {
    _dock.area = area;
    final target = _dock.rectIn(area);
    final from = _from;
    final rect = from != null && _move.isAnimating
        ? Rect.lerp(
            from(area),
            target,
            Curves.easeOutCubic.transform(_move.value),
          )!
        : target;
    _dock.lastRect = rect;
    return rect;
  }

  @override
  Widget build(BuildContext context) {
    final key = _dock.dockedKey;
    final args = _dock.dockedArgs;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        if (key != null && args != null)
          // Empty space in this layer takes no hits, so the page underneath
          // stays fully usable all around the player.
          Positioned.fill(
            child: CustomSingleChildLayout(
              delegate: _DockLayout(this),
              child: _frame(key, args),
            ),
          )
        else
          const SizedBox.shrink(),
      ],
    );
  }

  /// Gives the keyboard back to whatever had it before the player took it:
  /// the page the viewer is using under the corner.
  void _releaseKeyboard() {
    if (_scope.hasFocus) {
      _scope.unfocus(disposition: UnfocusDisposition.previouslyFocusedChild);
    }
  }

  Widget _frame(GlobalKey key, PlayerArgs args) {
    return TapRegion(
      onTapOutside: (_) => _releaseKeyboard(),
      child: FocusScope(
        node: _scope,
        // The page lets Esc through while it is in the corner. Here it means
        // back to the page underneath; closing the player would surprise.
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape &&
              _scope.hasFocus) {
            _releaseKeyboard();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: DecoratedBox(
          key: PlayerDockHost.frameKey,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(
                color: Color(0x99000000),
                blurRadius: 24,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _DockMedia(
                  dock: _dock,
                  // Its own messenger, so a player toast does not land on the
                  // page underneath. Its own Navigator, so a Tooltip or
                  // Navigator.of(context) inside the page finds one: the
                  // app's Navigator is below this layer, not above it.
                  child: ScaffoldMessenger(
                    child: HeroControllerScope.none(
                      child: InheritedGoRouter(
                        // The router is below this layer too. With it here,
                        // anything in the page that navigates the app does so
                        // rather than throwing.
                        goRouter: _router,
                        child: Navigator(
                          key: ValueKey(key),
                          // The keyboard stays with the page the viewer
                          // moved on to; a click on the player takes it.
                          requestFocus: false,
                          onGenerateRoute: (_) => PageRouteBuilder<void>(
                            transitionDuration: Duration.zero,
                            reverseTransitionDuration: Duration.zero,
                            pageBuilder: (_, _, _) =>
                                widget.pageBuilder(key, args),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                _ResizeGrips(dock: _dock),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DockLayout extends SingleChildLayoutDelegate {
  _DockLayout(this.host)
    : super(relayout: Listenable.merge([host._dock.geometry, host._move]));

  final _PlayerDockHostState host;

  @override
  Size getSize(BoxConstraints constraints) => constraints.biggest;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.tight(host._rectIn(constraints.biggest).size);

  @override
  Offset getPositionForChild(Size size, Size childSize) =>
      host._rectIn(size).topLeft;

  @override
  bool shouldRelayout(_DockLayout oldDelegate) => oldDelegate.host != host;
}

/// What the page sees of the world while it is in the corner: a screen the
/// size of the box, and text scaled down with it. Subtitles and the page's
/// cards are sized for a full window; at a quarter of the width they read
/// like a small player's.
///
/// From the settled size rather than the frame-by-frame one, so a drag or the
/// docking glide rebuilds nothing inside the page.
class _DockMedia extends StatelessWidget {
  const _DockMedia({required this.dock, required this.child});

  final PlayerDock dock;
  final Widget child;

  /// The window width the player's text is designed for.
  static const double _designWidth = 960;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return ListenableBuilder(
      listenable: dock.geometry,
      child: child,
      builder: (context, child) {
        final area = dock.area.isEmpty ? mq.size : dock.area;
        final size = DockGeometry.sizeFor(dock.width, dock.aspect, area);
        final scale = (size.width / _designWidth).clamp(0.45, 1.0);
        return MediaQuery(
          data: mq.copyWith(
            size: size,
            padding: EdgeInsets.zero,
            viewPadding: EdgeInsets.zero,
            viewInsets: EdgeInsets.zero,
            textScaler: TextScaler.linear(mq.textScaler.scale(1) * scale),
          ),
          child: child!,
        );
      },
    );
  }
}

/// Resize handles on the two edges that face the middle of the window. The
/// box keeps the picture's shape, so either edge changes the width.
class _ResizeGrips extends StatelessWidget {
  const _ResizeGrips({required this.dock});

  final PlayerDock dock;

  /// Thin enough to stay clear of the corner buttons the page draws 6 px in.
  static const double _thickness = 5;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: dock.geometry,
      builder: (context, _) {
        if (dock.dragging) return const SizedBox.shrink();
        final c = dock.corner;
        final onRight = c == DockCorner.topRight || c == DockCorner.bottomRight;
        final onBottom =
            c == DockCorner.bottomLeft || c == DockCorner.bottomRight;
        Widget grip(MouseCursor cursor, Offset Function(Offset) axis) =>
            MouseRegion(
              cursor: cursor,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (d) => dock.resizeBy(axis(d.delta)),
                onPanEnd: (_) => dock.resizeEnd(),
              ),
            );
        return Stack(
          children: [
            Positioned(
              top: 0,
              bottom: 0,
              width: _thickness,
              left: onRight ? 0 : null,
              right: onRight ? null : 0,
              child: grip(
                SystemMouseCursors.resizeLeftRight,
                (d) => Offset(d.dx, 0),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              height: _thickness,
              top: onBottom ? 0 : null,
              bottom: onBottom ? null : 0,
              child: grip(
                SystemMouseCursors.resizeUpDown,
                (d) => Offset(0, d.dy),
              ),
            ),
          ],
        );
      },
    );
  }
}
