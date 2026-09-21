import 'package:flutter/material.dart';

/// Dissolves a scrollable into its own edges instead of slicing it.
///
/// A list inside a sheet ends where the sheet's box ends, which means a row cut
/// in half across the middle: half an icon, half a name, hard against the
/// filter field above it. That cut is what makes a long list feel crammed
/// rather than long — nothing says the list continues, only that it was
/// truncated, and the half-row reads as a rendering fault.
///
/// The fade is only ever on the side there is something beyond. At rest at the
/// top of a list, a fade over the first row would be dimming a row for no
/// reason; it comes in over the first [extent] scrolled and goes out the same
/// way, so the edge is soft exactly while there is something behind it.
///
/// One `saveLayer` for the whole scrollable, which is why the rows themselves
/// must not each be given an [Opacity] — see the scale-only treatment callers
/// use for per-row falloff.
class EdgeFade extends StatefulWidget {
  const EdgeFade({
    super.key,
    required this.child,
    this.extent = 28,
    this.axis = Axis.vertical,
  });

  final Widget child;

  /// How deep the fade runs, and the distance over which it comes in.
  final double extent;

  final Axis axis;

  @override
  State<EdgeFade> createState() => _EdgeFadeState();
}

class _EdgeFadeState extends State<EdgeFade> {
  /// How much of each edge's fade is showing, 0 to 1.
  double _before = 0;
  double _after = 0;

  bool _read(ScrollMetrics m) {
    // A scrollable that is not the one being wrapped — a horizontal row inside
    // a row, say — must not drive this one's edges.
    if (m.axis != widget.axis) return false;
    final before = (m.extentBefore / widget.extent).clamp(0.0, 1.0);
    final after = (m.extentAfter / widget.extent).clamp(0.0, 1.0);
    if (before == _before && after == _after) return false;
    setState(() {
      _before = before;
      _after = after;
    });
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final vertical = widget.axis == Axis.vertical;
    return NotificationListener<ScrollMetricsNotification>(
      // Fires when the metrics change without a scroll — first layout, the
      // keyboard opening, the filter narrowing the list to four rows. Without
      // it the fade would be stale until something was dragged, which for a
      // list that has just been filtered down to nothing is a fade over an
      // empty box.
      onNotification: (n) => _read(n.metrics),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) => _read(n.metrics),
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) {
            final length = vertical ? rect.height : rect.width;
            // A fade deeper than a third of the viewport stops reading as an
            // edge and starts reading as a vignette.
            final depth = (widget.extent / length).clamp(0.0, 0.33);
            return LinearGradient(
              begin: vertical ? Alignment.topCenter : Alignment.centerLeft,
              end: vertical ? Alignment.bottomCenter : Alignment.centerRight,
              colors: [
                Colors.white.withValues(alpha: 1 - _before),
                Colors.white,
                Colors.white,
                Colors.white.withValues(alpha: 1 - _after),
              ],
              stops: [0, depth, 1 - depth, 1],
            ).createShader(rect);
          },
          child: widget.child,
        ),
      ),
    );
  }
}

/// Settles a fixed-extent list's rows in as they arrive at the middle of the
/// viewport, and lets them go as they leave.
///
/// Scale only, deliberately. The dissolve at the edges is [EdgeFade]'s job and
/// it costs one layer for the whole list; an [Opacity] per row would be one
/// layer per row for the same effect, on a list that is already scrolling.
///
/// [index] and [extent] are what make this cheap: the row's position is
/// arithmetic rather than a measurement, so nothing has to be laid out to know
/// where it is, and the row subtree itself is never rebuilt — only the
/// transform around it.
class ScrollSettle extends StatelessWidget {
  const ScrollSettle({
    super.key,
    required this.controller,
    required this.index,
    required this.extent,
    required this.child,
    this.minScale = 0.94,
  });

  final ScrollController controller;
  final int index;
  final double extent;
  final Widget child;

  /// How small a row gets at the very edge. Small differences read as the list
  /// having depth; large ones read as a carousel, which this is not.
  final double minScale;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      child: child,
      builder: (context, built) {
        // `position` throws outright when a controller is attached to more
        // than one scrollable, which is a thing that happens for a frame while
        // a sheet's list is being replaced. A row at full size for that frame
        // is the right answer; an exception is not.
        if (controller.positions.length != 1) return built!;
        final position = controller.position;
        if (!position.haveDimensions) return built!;
        final top = index * extent - position.pixels;
        final bottom = position.viewportDimension - (top + extent);
        // Distance from whichever edge is nearer, in rows. A row fully inside
        // is untouched; the treatment is entirely about the two rows at the
        // ends.
        final t = ((top < bottom ? top : bottom) / extent).clamp(0.0, 1.0);
        final k = Curves.easeOut.transform(t);
        return Transform.scale(
          scale: minScale + (1 - minScale) * k,
          child: built,
        );
      },
    );
  }
}
