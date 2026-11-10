import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';

/// Where the route a widget stands in is on its way in: still sliding,
/// landed, or taken back — and work held until it has come to rest.
///
/// A page's first frames are the slide's frames. Anything that can wait —
/// a picture decoded, a menu readied, the keyboard raised, a long list
/// laid out — waits for the route to land, or the slide pays for it. Every
/// page that held work back wrote the same dozen lines against
/// `ModalRoute.of(context)?.animation`; this is them once.
///
/// It is read *quietly*: asking `ModalRoute.of` from a page's own state
/// makes the page depend on whether its route is the top one, so the whole
/// page was built again on the frame a page was pushed over it and on the
/// frame that page started back — the two busiest frames of the way
/// there and back. Here the route is asked for through the nearest
/// render object above [BuildContext] instead: one that is rebuilt anyway
/// is told, and it rebuilds as a render object does, without building
/// anything under it again.
@immutable
final class RouteArrival {
  const RouteArrival._(this.route);

  /// The arrival of the route [context] stands in; one with no route (a
  /// widget above every navigator, a test pumping a bare widget) has
  /// always arrived.
  factory RouteArrival.of(BuildContext context) =>
      RouteArrival._(routeOf(context));

  /// The route [context] stands in, without [context] depending on it.
  static ModalRoute<dynamic>? routeOf(BuildContext context) {
    Element? quiet;
    context.visitAncestorElements((element) {
      if (element is RenderObjectElement) {
        quiet = element;
        return false;
      }
      return true;
    });
    return ModalRoute.of(quiet ?? context);
  }

  final ModalRoute<dynamic>? route;

  /// The route's way in, 0 to 1: always complete without a route.
  Animation<double> get entrance =>
      route?.animation ?? kAlwaysCompleteAnimation;

  /// Whether the route has landed — or there is none to land.
  bool get arrived => entrance.isCompleted;

  /// Whether the page is moving on the glass: coming in or going, a page
  /// over it coming or going, or a thumb holding a back swipe — which
  /// moves the page without an animation status of its own.
  bool get moving {
    final route = this.route;
    if (route == null) return false;
    if (route.animation?.isAnimating ?? false) return true;
    if (route.secondaryAnimation?.isAnimating ?? false) return true;
    return route.navigator?.userGestureInProgress ?? false;
  }

  /// Calls [then] once the route has come to rest — with true when it has
  /// landed, false when it was taken back before it did — or at once (with
  /// true, or false for a route already gone) when it already stands.
  ///
  /// Only where it comes to rest counts: a back swipe let go short of the
  /// edge turns the page round and brings it in again, and that is not
  /// rest. [then] is not called once [context] has left the tree; the
  /// returned wait can also be [ArrivalWait.cancel]led — from `dispose`,
  /// by a state that wants its listener off at once.
  static ArrivalWait whenSettled(
    BuildContext context,
    void Function(bool landed) then,
  ) {
    final arrival = RouteArrival.of(context);
    final animation = arrival.route?.animation;
    if (animation == null || !animation.isAnimating) {
      then(animation == null || animation.isCompleted);
      return ArrivalWait._settled();
    }
    return ArrivalWait._(animation, (landed) {
      if (context.mounted) then(landed);
    });
  }

  /// Calls [then] once the route has landed, never if it is taken back:
  /// the work belongs to a page that stays. At once when it has already
  /// landed.
  static ArrivalWait whenLanded(BuildContext context, VoidCallback then) =>
      whenSettled(context, (landed) {
        if (landed) then();
      });
}

/// A wait for a route to come to rest ([RouteArrival.whenSettled]).
class ArrivalWait {
  ArrivalWait._(Animation<double> animation, this._then)
    : _animation = animation {
    animation.addStatusListener(_heard);
  }

  ArrivalWait._settled() : _animation = null, _then = null, _over = true;

  final Animation<double>? _animation;
  final void Function(bool landed)? _then;
  bool _over = false;

  /// Whether it is still waiting.
  bool get waiting => !_over;

  void _heard(AnimationStatus status) {
    if (status.isAnimating) return;
    cancel();
    _then?.call(status.isCompleted);
  }

  /// Stops waiting; [RouteArrival.whenSettled]'s `then` is not called.
  void cancel() {
    if (_over) return;
    _over = true;
    _animation?.removeStatusListener(_heard);
  }
}

/// Whether a route is moving on the glass, told as it starts and stops:
/// its own way in or out ([ModalRoute.animation]), a page coming over it or
/// leaving it ([ModalRoute.secondaryAnimation]), or a finger dragging any
/// navigator above it back ([NavigatorState.userGestureInProgressNotifier]) —
/// the iPhone's swipe back, held half way, moves the page without a status
/// of its own.
///
/// [RouteArrival.moving] asks the same once; this keeps listening, for
/// what must change while the route moves — the glass held for as long as
/// it does (`GlassHoldReason.route`).
class RouteMotion {
  /// Listens to [route] and to every navigator from [route]'s own (or, with
  /// no route, the one above [context]) up to the root; [onChange] is told
  /// on every status change and every drag start or end.
  RouteMotion({
    required ModalRoute<Object?>? route,
    required BuildContext context,
    required VoidCallback onChange,
  }) : _route = route,
       _onChange = onChange {
    route?.animation?.addStatusListener(_status);
    route?.secondaryAnimation?.addStatusListener(_status);
    var navigator =
        route?.navigator ?? context.findAncestorStateOfType<NavigatorState>();
    while (navigator != null) {
      final gesture = navigator.userGestureInProgressNotifier;
      gesture.addListener(_onChange);
      _gestures.add(gesture);
      navigator = navigator.context.findAncestorStateOfType<NavigatorState>();
    }
  }

  final ModalRoute<Object?>? _route;
  final VoidCallback _onChange;
  final List<ValueListenable<bool>> _gestures = [];

  /// The route listened to.
  ModalRoute<Object?>? get route => _route;

  /// Whether the route is moving now.
  bool get moving {
    final route = _route;
    if (route != null &&
        ((route.animation?.isAnimating ?? false) ||
            (route.secondaryAnimation?.isAnimating ?? false))) {
      return true;
    }
    return _gestures.any((gesture) => gesture.value);
  }

  void _status(AnimationStatus _) => _onChange();

  /// Stops listening.
  void cancel() {
    _route?.animation?.removeStatusListener(_status);
    _route?.secondaryAnimation?.removeStatusListener(_status);
    for (final gesture in _gestures) {
      gesture.removeListener(_onChange);
    }
    _gestures.clear();
  }
}
