import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/system/platform_utils.dart';
import 'package:soplay/features/detail/domain/entities/player_args.dart';

enum DockCorner { topLeft, topRight, bottomLeft, bottomRight }

/// Where the corner player sits, as plain arithmetic so it can be tested
/// without a window.
class DockGeometry {
  DockGeometry._();

  /// Gap between the player and the edge of the app's content area.
  static const double margin = 16;
  static const double minWidth = 240;
  static const double defaultWidth = 400;

  /// Past this share of the window the "mini" player covers the very page it
  /// exists to leave usable.
  static const double maxShare = 0.6;

  /// How far ahead a release is projected along its fling, in seconds: a
  /// flick toward a corner lands there even when let go of mid-window.
  static const double flingLookahead = 0.12;

  static double clampAspect(double a) =>
      a.isFinite && a > 0 ? a.clamp(0.5, 2.6).toDouble() : 16 / 9;

  /// The player's size for a wanted [width] at [aspect], kept between
  /// [minWidth] and [maxShare] of [area] and never taller than the area.
  static Size sizeFor(double width, double aspect, Size area) {
    final a = clampAspect(aspect);
    final maxW = math.max(
      minWidth,
      math.min(area.width * maxShare, (area.height - 2 * margin) * a),
    );
    final w = (width.isFinite ? width : defaultWidth)
        .clamp(minWidth, maxW)
        .toDouble();
    return Size(w, (w / a).roundToDouble());
  }

  static Rect rectFor(DockCorner c, Size size, Size area) {
    final left = c == DockCorner.topLeft || c == DockCorner.bottomLeft;
    final top = c == DockCorner.topLeft || c == DockCorner.topRight;
    return Rect.fromLTWH(
      left ? margin : area.width - size.width - margin,
      top ? margin : area.height - size.height - margin,
      size.width,
      size.height,
    );
  }

  /// [rect] moved by [offset] but kept wholly inside [area], so a drag can not
  /// lose the player past the edge of the window.
  static Rect dragged(Rect rect, Offset offset, Size area) {
    final r = rect.shift(offset);
    final maxLeft = math.max(0.0, area.width - r.width);
    final maxTop = math.max(0.0, area.height - r.height);
    return Rect.fromLTWH(
      r.left.clamp(0.0, maxLeft),
      r.top.clamp(0.0, maxTop),
      r.width,
      r.height,
    );
  }

  /// The corner a release snaps to: whichever quarter of the window the
  /// player's centre would be in a moment later at the release [velocity].
  static DockCorner nearest(Rect rect, Offset velocity, Size area) {
    final c = rect.center + velocity * flingLookahead;
    final left = c.dx < area.width / 2;
    final top = c.dy < area.height / 2;
    if (top) return left ? DockCorner.topLeft : DockCorner.topRight;
    return left ? DockCorner.bottomLeft : DockCorner.bottomRight;
  }

  /// The grips sit on the edges facing the middle of the window: dragging
  /// one away from the docked corner grows the player, toward it shrinks it.
  /// The box keeps the picture's shape, so a vertical pull is converted to
  /// width through [aspect], and of the two axes the larger pull wins.
  static double resized(
    double width,
    Offset delta,
    DockCorner c,
    double aspect,
  ) {
    final left = c == DockCorner.topLeft || c == DockCorner.bottomLeft;
    final top = c == DockCorner.topLeft || c == DockCorner.topRight;
    final growX = left ? delta.dx : -delta.dx;
    final growY = (top ? delta.dy : -delta.dy) * clampAspect(aspect);
    return width + (growX.abs() >= growY.abs() ? growX : growY);
  }
}

enum _DockMode { none, docked, handingBack }

/// The desktop corner player, Telegram-style.
///
/// Owns no playback. It holds the [GlobalKey] of the PlayerPage that is in
/// the corner and where the corner window is. The page's State moves between
/// the /player route and PlayerDockHost under that key, so every timer,
/// subscription and the controller itself keep running across the move —
/// history ticks, auto-advance, subtitles, party sync and retries included.
///
/// Two channels, because they change at very different rates: this notifier
/// says *which* page is docked (rare, and it rebuilds the host), [geometry]
/// says where it is (every frame of a drag, and only relays the box out).
class PlayerDock extends ChangeNotifier {
  PlayerDock._();
  static final PlayerDock instance = PlayerDock._();

  /// Desktop only. Phones already float over other apps through the system
  /// picture-in-picture, and a television has no pointer to drag one with.
  static bool get supported => isDesktopPlatform && !isTvPlatform;

  static const _cornerKey = 'player_dock_corner';
  static const _widthKey = 'player_dock_width';

  _DockMode _mode = _DockMode.none;
  GlobalKey? _key;
  PlayerArgs? _args;
  bool _prefsRead = false;

  final _Pulse _geometry = _Pulse();

  /// Fires when the corner, size, aspect or drag offset changes.
  Listenable get geometry => _geometry;

  /// Opens /player. Set by the host, so this file does not import the router.
  void Function(PlayerArgs args)? openRoute;

  DockCorner corner = DockCorner.bottomRight;
  double width = DockGeometry.defaultWidth;
  double aspect = 16 / 9;
  Offset drag = Offset.zero;
  bool dragging = false;

  /// The host's last laid-out content area and player rect. Written during
  /// layout, without notifying: a drag ends in screen space and needs to know
  /// what it was dragged across.
  Size area = Size.zero;
  Rect? lastRect;

  bool get isDocked => _mode == _DockMode.docked;
  GlobalKey? get dockedKey => isDocked ? _key : null;
  PlayerArgs? get dockedArgs => isDocked ? _args : null;

  /// Where the player belongs in [area] right now, drag included.
  Rect rectIn(Size area) {
    final base = DockGeometry.rectFor(
      corner,
      DockGeometry.sizeFor(width, aspect, area),
      area,
    );
    return drag == Offset.zero ? base : DockGeometry.dragged(base, drag, area);
  }

  void dock({
    required GlobalKey key,
    required PlayerArgs args,
    required Size videoSize,
  }) {
    _readPrefs();
    _key = key;
    _args = args;
    _mode = _DockMode.docked;
    _setAspect(videoSize);
    drag = Offset.zero;
    dragging = false;
    notifyListeners();
  }

  /// Back to the full player. Flip first, push second: the host stops
  /// building the page in the same frame the new route starts building it,
  /// which is what lets the GlobalKey carry the State across. A key that is
  /// built nowhere at the end of a frame is disposed.
  ///
  /// False, and nothing changes, when there is no host to hand back from.
  bool expand() {
    final args = _args;
    final open = openRoute;
    if (!isDocked || args == null || open == null) return false;
    _mode = _DockMode.handingBack;
    notifyListeners();
    open(args);
    return true;
  }

  /// Called by PlayerRoute.initState: the key of the page being handed back,
  /// or null for an ordinary open. No notify: the host already stopped
  /// showing it when [expand] flipped the mode.
  GlobalKey? takeHandBack() {
    if (_mode != _DockMode.handingBack) return null;
    final key = _key;
    _clear();
    return key;
  }

  /// Closes the corner player. Completes after the frame in which the page
  /// was disposed, so its history is saved and its stream stopped by then.
  Future<void> close() async {
    if (_mode == _DockMode.none) return;
    _clear();
    notifyListeners();
    await SchedulerBinding.instance.endOfFrame;
  }

  /// From PlayerPage.dispose. Silent: it runs while the tree is finalised.
  void forget(GlobalKey key) {
    if (_key == key) _clear();
  }

  /// A new episode or rendition can change the shape of the picture.
  void reportVideoSize(Size size) {
    if (!isDocked) return;
    final before = aspect;
    _setAspect(size);
    if ((aspect - before).abs() > 0.01) _geometry.ping();
  }

  void dragStart() {
    dragging = true;
    drag = Offset.zero;
    _geometry.ping();
  }

  void dragBy(Offset delta) {
    drag += delta;
    _geometry.ping();
  }

  void dragEnd(Offset velocity) {
    if (!area.isEmpty) {
      corner = DockGeometry.nearest(rectIn(area), velocity, area);
    }
    drag = Offset.zero;
    dragging = false;
    _savePrefs();
    _geometry.ping();
  }

  void resizeBy(Offset delta) {
    if (area.isEmpty) return;
    width = DockGeometry.sizeFor(
      DockGeometry.resized(width, delta, corner, aspect),
      aspect,
      area,
    ).width;
    _geometry.ping();
  }

  void resizeEnd() => _savePrefs();

  void _clear() {
    _mode = _DockMode.none;
    _key = null;
    _args = null;
    drag = Offset.zero;
    dragging = false;
  }

  void _setAspect(Size s) {
    if (s.width > 0 && s.height > 0) {
      aspect = DockGeometry.clampAspect(s.width / s.height);
    }
  }

  // The same box and the same direct access as DesktopWindow's geometry.
  void _readPrefs() {
    if (_prefsRead) return;
    _prefsRead = true;
    try {
      final box = Hive.box(AppConstants.settingsBox);
      final c = box.get(_cornerKey);
      if (c is int && c >= 0 && c < DockCorner.values.length) {
        corner = DockCorner.values[c];
      }
      final w = box.get(_widthKey);
      if (w is num && w > 0) width = w.toDouble();
    } catch (_) {}
  }

  void _savePrefs() {
    try {
      final box = Hive.box(AppConstants.settingsBox);
      box.put(_cornerKey, corner.index);
      box.put(_widthKey, width);
    } catch (_) {}
  }

  /// Back to a fresh, empty dock between widget tests.
  @visibleForTesting
  void debugReset() {
    _clear();
    openRoute = null;
    corner = DockCorner.bottomRight;
    width = DockGeometry.defaultWidth;
    aspect = 16 / 9;
    area = Size.zero;
    lastRect = null;
    _prefsRead = true;
  }
}

class _Pulse extends ChangeNotifier {
  void ping() => notifyListeners();
}
