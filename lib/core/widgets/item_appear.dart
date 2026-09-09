import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:soplay/core/system/responsive.dart';

/// A card arriving, rather than being already there.
///
/// This is RecyclerView's item animation: a builder-delegate sliver creates a
/// child the moment it scrolls into range — the same moment `onBindViewHolder`
/// fires on Android — so an entrance played on first build reads as the card
/// coming in with the scroll. A grid that simply appears fully formed reads as
/// a screenshot; the same grid whose cards settle into place reads as a list
/// being filled.
///
/// ## Three motions, not one
///
/// A slide alone reads as a card being pushed. A fade alone reads as a card
/// developing. Together with a small scale it reads as a card *arriving*: it
/// comes from slightly behind and slightly off-position and settles. The scale
/// is what does most of that work and it is the part a slide-only entrance is
/// missing.
///
/// ## Why the travel is in pixels
///
/// `SlideTransition` moves a fraction of the child's own size, so the same
/// widget travelled 14px in a View All grid, 11px in a Home rail and less
/// again in a dense list — the motion changed character per screen for no
/// reason anyone chose. [_travel] is a fixed distance, so every surface in the
/// app moves the same way.
///
/// ## Why the stagger is by row
///
/// A three-column grid builds indices 0, 1, 2 as one row. Stepping them by a
/// flat index puts 56ms between the first column and the third, which the eye
/// reads as the row tearing. [columns] makes the row the unit: rows step, and
/// columns within a row are offset by a quarter step — enough to sweep, not
/// enough to tear.
class ItemAppear extends StatefulWidget {
  const ItemAppear({
    super.key,
    required this.index,
    required this.child,
    this.columns = 1,
    this.axis = Axis.vertical,
    this.staggerLimit = staggerLimitDefault,
  });

  /// Roughly a screenful of a three-column grid.
  static const int staggerLimitDefault = 12;

  /// Position in the list. Used for the opening sweep only.
  final int index;

  /// Columns the grid lays out, so the stagger can step by row. 1 for a list
  /// or a rail.
  final int columns;

  /// Which way the surface scrolls. A rail's cards come in from the trailing
  /// edge — the direction they are travelling from — rather than from below.
  final Axis axis;

  /// How many cards get a staggered start before the delay is dropped. Past
  /// this the delay would be attached to a card the user has already scrolled
  /// to, which reads as the grid lagging the finger.
  final int staggerLimit;

  final Widget child;

  /// Long enough to be a movement, short enough that a fling does not leave a
  /// trail of cards still settling.
  static const Duration duration = Duration(milliseconds: 300);

  /// One row to the next.
  static const Duration rowStep = Duration(milliseconds: 45);

  /// Nothing waits longer than this, however far down it is.
  static const Duration maxDelay = Duration(milliseconds: 200);

  /// How far a card travels before it lands.
  static const double _travel = 16;

  /// How small it starts. Under about 0.94 the card reads as zooming; over
  /// about 0.98 the scale is not doing anything.
  static const double _from = 0.96;

  /// Material 3's emphasized-decelerate: most of the distance is covered
  /// immediately and the last of it eases out, which is what makes a short
  /// entrance feel unhurried rather than clipped.
  static const Curve _curve = Cubic(0.05, 0.7, 0.1, 1.0);

  @override
  State<ItemAppear> createState() => _ItemAppearState();
}

class _ItemAppearState extends State<ItemAppear>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  late final Animation<double> _move;
  late final Animation<double> _fade;

  /// Held so it can be cancelled. A grid disposes cards as fast as it builds
  /// them while a finger is moving, and an uncancelled delay leaves one live
  /// timer behind per card scrolled past.
  Timer? _start;

  Duration get _delay {
    if (widget.index >= widget.staggerLimit) return Duration.zero;
    final columns = math.max(1, widget.columns);
    final row = widget.index ~/ columns;
    final column = widget.index % columns;
    final slots = row + column * 0.25;
    final ms = (ItemAppear.rowStep.inMilliseconds * slots).round();
    return Duration(milliseconds: math.min(ms, ItemAppear.maxDelay.inMilliseconds));
  }

  @override
  void initState() {
    super.initState();
    final controller = AnimationController(
      vsync: this,
      duration: ItemAppear.duration,
    );
    _controller = controller;
    _move = CurvedAnimation(parent: controller, curve: ItemAppear._curve);
    // Faster than the movement and finished well before it: a card that is
    // still translucent while it settles looks unresolved, and one that is
    // opaque for the last third of its travel looks deliberate.
    _fade = CurvedAnimation(
      parent: controller,
      curve: const Interval(0, 0.65, curve: Curves.easeOut),
    );

    final delay = _delay;
    if (delay == Duration.zero) {
      controller.forward();
    } else {
      _start = Timer(delay, () {
        if (mounted) controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _start?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  /// Where the card starts, in pixels. A vertical surface lifts from below; a
  /// rail comes in from the edge it scrolls away towards, which is the right
  /// edge in LTR and the left in RTL.
  Offset _offsetAt(double t, TextDirection direction) {
    final distance = ItemAppear._travel * (1 - t);
    if (widget.axis == Axis.vertical) return Offset(0, distance);
    final sign = direction == TextDirection.rtl ? -1.0 : 1.0;
    return Offset(distance * sign, 0);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    // Someone who has asked the OS to remove animations gets the grid, not a
    // grid that keeps moving under them.
    if (controller == null || MediaQuery.disableAnimationsOf(context)) {
      return widget.child;
    }
    final direction = Directionality.of(context);
    return FadeTransition(
      opacity: _fade,
      child: AnimatedBuilder(
        animation: _move,
        // Passed through rather than rebuilt: the card's own subtree — images,
        // badges, text — is built once and only the transform changes.
        child: widget.child,
        builder: (context, child) {
          final t = _move.value;
          final offset = _offsetAt(t, direction);
          final scale = ItemAppear._from + (1 - ItemAppear._from) * t;
          // One Transform rather than a translate wrapping a scale: the matrix
          // scales about the card's centre and then moves it, which is the
          // order that keeps the travel distance honest at any scale.
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..translateByDouble(offset.dx, offset.dy, 0, 1)
              ..scaleByDouble(scale, scale, 1, 1),
            child: child,
          );
        },
      ),
    );
  }
}

/// Columns the responsive grid actually lays out, so a caller can stagger by
/// row rather than by flat index.
int gridColumns(BuildContext context, {int mobile = 3}) =>
    isDesktopPlatform ? 6 : mobile;

/// Columns a `SliverGridDelegateWithMaxCrossAxisExtent` will settle on.
///
/// The delegate divides the available width by the maximum extent and rounds
/// up, which is worth mirroring rather than guessing: a stagger that thinks
/// there are three columns in a four-column grid sweeps diagonally.
int columnsForMaxExtent(double width, double maxExtent, {double spacing = 0}) {
  if (width <= 0 || maxExtent <= 0) return 1;
  return math.max(1, ((width + spacing) / (maxExtent + spacing)).ceil());
}
