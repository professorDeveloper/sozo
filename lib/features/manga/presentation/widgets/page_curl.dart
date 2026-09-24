import 'dart:math' as math;
import 'dart:ui' as ui show Gradient, PointerDeviceKind;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Pages that turn like paper.
///
/// The turning page folds along the perpendicular bisector of its corner and
/// the point being dragged: what lies past the fold is reflected over it and
/// drawn as the back of the sheet, the page underneath shows through where
/// the sheet has lifted, and gradients along the fold give it its curve.
///
/// Controlled: the parent owns [page] and hears about a finished turn through
/// [onPageChanged]. Turning past either end calls [onPastEnd] or
/// [onPastStart] instead.
class PageCurlView extends StatefulWidget {
  const PageCurlView({
    super.key,
    required this.pageCount,
    required this.page,
    required this.pageBuilder,
    required this.onPageChanged,
    required this.paper,
    this.onPastEnd,
    this.onPastStart,
  });

  final int pageCount;
  final int page;
  final IndexedWidgetBuilder pageBuilder;
  final ValueChanged<int> onPageChanged;

  /// The colour of the back of a sheet.
  final Color paper;
  final VoidCallback? onPastEnd;
  final VoidCallback? onPastStart;

  @override
  State<PageCurlView> createState() => PageCurlViewState();
}

class PageCurlViewState extends State<PageCurlView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  /// The sheet that is moving and the one it uncovers, while a turn is on.
  int? _sheet;
  int? _under;
  bool _forward = true;

  Offset _touch = Offset.zero;
  Offset _from = Offset.zero;
  Offset _to = Offset.zero;
  bool _commit = false;
  double _cornerY = 0;
  Size _size = Size.zero;

  Offset? _dragStart;
  double _dragDx = 0;
  bool? _dragForward;

  /// A turn finished but not yet echoed back through [PageCurlView.page].
  int? _landed;

  int get _current => _landed ?? widget.page;

  bool get isTurning => _sheet != null;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this)
      ..addListener(_onTick)
      ..addStatusListener(_onStatus);
  }

  @override
  void didUpdateWidget(PageCurlView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _landed = null;
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void turnForward() => _turnBy(true);
  void turnBackward() => _turnBy(false);

  void _turnBy(bool forward) {
    if (_anim.isAnimating) _finish();
    if (!_begin(forward)) return;
    final w = _size.width;
    final h = _size.height;
    _cornerY = h;
    _touch = forward ? Offset(w, h) : Offset(-w, h);
    _animateTo(forward ? Offset(-w, h) : Offset(w, h), commit: true);
  }

  /// Sets up a turn, or reports turning past an end.
  bool _begin(bool forward) {
    final target = _current + (forward ? 1 : -1);
    if (target < 0 || target >= widget.pageCount) {
      (forward ? widget.onPastEnd : widget.onPastStart)?.call();
      return false;
    }
    if (_size.isEmpty || MediaQuery.disableAnimationsOf(context)) {
      _landed = target;
      widget.onPageChanged(target);
      return false;
    }
    setState(() {
      _forward = forward;
      _sheet = forward ? _current : target;
      _under = forward ? target : _current;
    });
    return true;
  }

  void _animateTo(Offset target, {required bool commit}) {
    _from = _touch;
    _to = target;
    _commit = commit;
    final distance = (_to - _from).distance / math.max(1, _size.width * 2);
    _anim.duration = Duration(
      milliseconds: (180 + 420 * distance.clamp(0.0, 1.0)).round(),
    );
    _anim.forward(from: 0);
  }

  void _onTick() {
    final t = Curves.easeOutCubic.transform(_anim.value);
    final lift = _commit ? math.sin(math.pi * t) * _size.height * 0.06 : 0.0;
    setState(() {
      _touch = Offset.lerp(_from, _to, t)! - Offset(0, lift);
    });
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _finish();
  }

  void _finish() {
    final committed = _commit;
    final target = _forward ? _under : _sheet;
    _anim.stop();
    setState(() {
      _sheet = null;
      _under = null;
    });
    if (committed && target != null) {
      _landed = target;
      widget.onPageChanged(target);
    }
  }

  void _onDragStart(DragStartDetails d) {
    if (_anim.isAnimating) _finish();
    _dragStart = d.localPosition;
    _dragDx = 0;
    _dragForward = null;
  }

  void _onDragUpdate(DragUpdateDetails d) {
    final start = _dragStart;
    if (start == null) return;
    _dragDx += d.delta.dx;
    if (_dragForward == null) {
      if (_dragDx.abs() < 4) return;
      final forward = _dragDx < 0;
      _dragForward = forward;
      final target = _current + (forward ? 1 : -1);
      if (target < 0 || target >= widget.pageCount) return;
      if (!_begin(forward)) return;
      _cornerY = start.dy > _size.height / 2 ? _size.height : 0;
    }
    if (!isTurning) return;
    final w = _size.width;
    final dy = (d.localPosition.dy - start.dy) * 0.5;
    final x = (_forward ? w : -w) + _dragDx * 2;
    setState(() => _touch = Offset(x, _cornerY + dy));
  }

  void _onDragEnd(DragEndDetails d) {
    final forward = _dragForward;
    _dragStart = null;
    _dragForward = null;
    if (forward == null) return;
    final v = d.primaryVelocity ?? 0;
    if (!isTurning) {
      if (_dragDx.abs() > 60) {
        (forward ? widget.onPastEnd : widget.onPastStart)?.call();
      }
      return;
    }
    final w = _size.width;
    // A quarter of the width, or a flick, is enough.
    final commit = forward
        ? (v < -350 || (v <= 350 && _touch.dx < w / 2))
        : (v > 350 || (v >= -350 && _touch.dx > -w / 2));
    final turned = forward ? -w : w;
    final flat = forward ? w : -w;
    _animateTo(Offset(commit ? turned : flat, _cornerY), commit: commit);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _size = constraints.biggest;
        return RawGestureDetector(
          behavior: HitTestBehavior.translucent,
          gestures: {
            HorizontalDragGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<
                  HorizontalDragGestureRecognizer
                >(
                  () => HorizontalDragGestureRecognizer(
                    debugOwner: this,
                    supportedDevices: const {
                      ui.PointerDeviceKind.touch,
                      ui.PointerDeviceKind.stylus,
                      ui.PointerDeviceKind.invertedStylus,
                    },
                  ),
                  (drag) {
                    // Under half the usual slop, so a swipe that starts on
                    // text turns the page before the text claims the drag
                    // for selecting.
                    drag.gestureSettings = const DeviceGestureSettings(
                      touchSlop: 8,
                    );
                    drag
                      ..onStart = _onDragStart
                      ..onUpdate = _onDragUpdate
                      ..onEnd = _onDragEnd;
                  },
                ),
          },
          child: _pages(),
        );
      },
    );
  }

  Widget _page(int index) => RepaintBoundary(
    child: KeyedSubtree(
      key: ValueKey(index),
      child: widget.pageBuilder(context, index),
    ),
  );

  Widget _pages() {
    final sheet = _sheet;
    final under = _under;
    if (sheet == null || under == null) {
      return widget.pageCount == 0
          ? const SizedBox.expand()
          : _page(widget.page);
    }
    final fold = CurlGeometry.of(_size, _touch, _cornerY);
    if (fold == null) {
      return _page(sheet);
    }
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          _page(under),
          CustomPaint(painter: _UnderShadePainter(fold)),
          ClipPath(
            clipper: _HalfClipper(fold, keepCorner: false),
            child: _page(sheet),
          ),
          CustomPaint(painter: _DropShadowPainter(fold)),
          Transform(
            transform: fold.reflection,
            child: ClipPath(
              clipper: _HalfClipper(fold, keepCorner: true),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  KeyedSubtree(
                    key: const ValueKey('back'),
                    child: widget.pageBuilder(context, sheet),
                  ),
                  ColoredBox(color: widget.paper.withValues(alpha: 0.9)),
                ],
              ),
            ),
          ),
          CustomPaint(painter: _FlapShadePainter(fold)),
        ],
      ),
    );
  }
}

/// The fold for a corner at (width, [cornerY]) dragged to [touch].
class CurlGeometry {
  CurlGeometry._(this.size, this.mid, this.normal, this.touch);

  final Size size;

  /// A point on the fold line, and the unit normal pointing to the corner's
  /// side of it.
  final Offset mid;
  final Offset normal;
  final Offset touch;

  static CurlGeometry? of(Size size, Offset touch, double cornerY) {
    final corner = Offset(size.width, cornerY);
    // The sheet is held at its spine: no point on it can be dragged further
    // from the spine than the page is wide.
    final spine = Offset(0, cornerY);
    var t = touch;
    final reach = t - spine;
    if (reach.distance > size.width) {
      t = spine + reach / reach.distance * size.width;
    }
    final v = corner - t;
    if (v.distance < 0.5) return null;
    return CurlGeometry._(size, (corner + t) / 2, v / v.distance, t);
  }

  double side(Offset p) =>
      (p.dx - mid.dx) * normal.dx + (p.dy - mid.dy) * normal.dy;

  Offset reflect(Offset p) => p - normal * (2 * side(p));

  Matrix4 get reflection {
    final nx = normal.dx;
    final ny = normal.dy;
    final c = 2 * (mid.dx * nx + mid.dy * ny);
    return Matrix4.identity()
      ..setEntry(0, 0, 1 - 2 * nx * nx)
      ..setEntry(0, 1, -2 * nx * ny)
      ..setEntry(1, 0, -2 * nx * ny)
      ..setEntry(1, 1, 1 - 2 * ny * ny)
      ..setEntry(0, 3, c * nx)
      ..setEntry(1, 3, c * ny);
  }

  /// The page cut by the fold: the corner's side, or the other one.
  List<Offset> half({required bool corner}) {
    final rect = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(size.width, size.height),
      Offset(0, size.height),
    ];
    final out = <Offset>[];
    for (var i = 0; i < rect.length; i++) {
      final a = rect[i];
      final b = rect[(i + 1) % rect.length];
      final sa = corner ? side(a) : -side(a);
      final sb = corner ? side(b) : -side(b);
      if (sa >= 0) out.add(a);
      if ((sa >= 0) != (sb >= 0)) {
        out.add(Offset.lerp(a, b, sa / (sa - sb))!);
      }
    }
    return out;
  }

  /// The back of the sheet where it lies on screen.
  List<Offset> get flap => [for (final p in half(corner: true)) reflect(p)];

  /// How far the sheet has turned, 0 flat to 1 over.
  double get progress =>
      ((size.width - touch.dx) / (2 * size.width)).clamp(0, 1);
}

Path _polygon(List<Offset> points) {
  final path = Path();
  if (points.isEmpty) return path;
  path.moveTo(points.first.dx, points.first.dy);
  for (final p in points.skip(1)) {
    path.lineTo(p.dx, p.dy);
  }
  return path..close();
}

class _HalfClipper extends CustomClipper<Path> {
  _HalfClipper(this.fold, {required this.keepCorner});

  final CurlGeometry fold;
  final bool keepCorner;

  @override
  Path getClip(Size size) => _polygon(fold.half(corner: keepCorner));

  @override
  bool shouldReclip(_HalfClipper old) =>
      old.fold.touch != fold.touch || old.keepCorner != keepCorner;
}

/// Darkens the uncovered page along the fold, where the lifted sheet shades it.
class _UnderShadePainter extends CustomPainter {
  _UnderShadePainter(this.fold);
  final CurlGeometry fold;

  @override
  void paint(Canvas canvas, Size size) {
    final reach = size.width * 0.18 * (1 - fold.progress * 0.5);
    canvas.save();
    canvas.clipPath(_polygon(fold.half(corner: true)));
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          fold.mid,
          fold.mid + fold.normal * reach,
          [
            Colors.black.withValues(alpha: 0.38),
            Colors.black.withValues(alpha: 0),
          ],
        ),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_UnderShadePainter old) => old.fold.touch != fold.touch;
}

/// The sheet's shadow on the part of the page still lying flat.
class _DropShadowPainter extends CustomPainter {
  _DropShadowPainter(this.fold);
  final CurlGeometry fold;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipPath(_polygon(fold.half(corner: false)));
    canvas.drawShadow(_polygon(fold.flap), Colors.black, 8, false);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DropShadowPainter old) => old.fold.touch != fold.touch;
}

/// Light at the fold and shade toward the edge, so the back of the sheet
/// reads as curved paper rather than a flat mirror.
class _FlapShadePainter extends CustomPainter {
  _FlapShadePainter(this.fold);
  final CurlGeometry fold;

  @override
  void paint(Canvas canvas, Size size) {
    final flap = fold.flap;
    if (flap.length < 3) return;
    final reach = flap
        .map((p) => -fold.side(p))
        .fold<double>(1, (a, b) => math.max(a, b));
    canvas.save();
    canvas.clipPath(_polygon(flap));
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          fold.mid,
          fold.mid - fold.normal * reach,
          [
            Colors.black.withValues(alpha: 0.22),
            Colors.white.withValues(alpha: 0.10),
            Colors.black.withValues(alpha: 0.06),
            Colors.black.withValues(alpha: 0.16),
          ],
          const [0, 0.12, 0.6, 1],
        ),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FlapShadePainter old) => old.fold.touch != fold.touch;
}
