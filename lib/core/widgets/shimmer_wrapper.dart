import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// The app's one skeleton shimmer.
///
/// Wrap a whole placeholder tree in this ONCE, at its root, and leave the
/// blocks inside as plain filled containers. Two things go wrong when each
/// block carries its own:
///
/// * Every `Shimmer.fromColors` is an `AnimationController` on repeat and a
///   `ShaderMaskLayer` per paint. A detail skeleton with thirty placeholders
///   ran thirty of each, on the same frames as the Hero flight it exists to
///   cover.
/// * Each one sizes its gradient to its own bounds and starts on its own
///   phase, so nothing sweeps — a poster cell glints at one rate, a
///   full-width synopsis bar at another, and the page reads as a wall of
///   flickering rectangles instead of one wave crossing it.
///
/// The colours and the period live here rather than at each call site because
/// two skeletons one navigation apart shimmering at different brightnesses and
/// tempos is more noticeable than either of them being slightly off.
class ShimmerWrapper extends StatelessWidget {
  const ShimmerWrapper({super.key, required this.child});

  final Widget child;

  /// Subtle, but not invisible: eleven levels of separation on a dark panel
  /// reads as a frozen screen rather than as loading, which is the one thing a
  /// skeleton exists to avoid.
  ///
  /// The highlight must be LIGHTER than the base. The package composites the
  /// gradient with `srcIn`, so a highlight darker than its base — which is what
  /// `surfaceVariant` at alpha 0.45 produced — travels across the placeholder
  /// as a dark notch, i.e. the sweep runs backwards.
  static const Color base = Color(0xFF1E1E1E);
  static const Color highlight = Color(0xFF333333);

  /// Slower than the package default of 1500ms, which reads as urgency on a
  /// screen that is only waiting.
  static const Duration period = Duration(milliseconds: 1650);

  /// The one fade a decoded image gets as it replaces the skeleton underneath
  /// it. It lives here, next to the skeleton's own colours, because the two are
  /// halves of the same hand-off and the app currently spells it eleven
  /// different ways — 120ms in one grid, 240ms in the poster beside it, so a
  /// single screen dissolves at three speeds. 180ms is long enough to read as a
  /// dissolve rather than a pop, short enough not to look like the image is
  /// still loading once it is already there.
  static const Duration imageFade = Duration(milliseconds: 180);

  @override
  Widget build(BuildContext context) {
    // The skeleton's whole job is to say "content is coming", and the colour
    // blocks alone still say it. What reduce-motion removes is the sweep — and
    // with it an AnimationController on infinite repeat plus a ShaderMaskLayer
    // per paint, on a screen that by definition has nothing else to show yet.
    //
    // It has to be the same `srcIn` composite the package uses, not a colour
    // painted behind the blocks: the placeholders inside are plain white
    // rectangles, and the only reason they ever read as [base] is that the
    // sweep paints THROUGH them. A ColoredBox underneath leaves the white
    // showing, i.e. reduce-motion turns every skeleton into a wall of white
    // slabs on a near-black app. A colour filter is the sweep's still frame:
    // one layer, painted once, with nothing ticking behind it.
    if (MediaQuery.disableAnimationsOf(context)) {
      return ColorFiltered(
        colorFilter: const ColorFilter.mode(base, BlendMode.srcIn),
        child: child,
      );
    }
    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      period: period,
      child: child,
    );
  }
}
