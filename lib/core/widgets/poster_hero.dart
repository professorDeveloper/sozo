import 'dart:ui' show lerpDouble;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/network/image_headers.dart';

/// The shared flight for a poster travelling from a grid into a detail header.
///
/// ## Why the flight needs its own widget
///
/// A plain `Hero` at each end looks wrong here, for a reason that is easy to
/// miss. During a flight Flutter does not fly the image you were looking at —
/// it builds the DESTINATION's subtree and animates its rectangle. The
/// destination poster is a `CachedNetworkImage` on a grey placeholder with a
/// 240 ms fade-in, so what crosses the screen is a grey box that turns into
/// artwork somewhere near the end. The poster appears to vanish on takeoff and
/// reappear on landing.
///
/// So the shuttle is built here instead: one image, no placeholder, no fade,
/// with the corner radius and the crop both accounted for. What lifts off is
/// what lands.
///
/// ## Two things that have to match exactly
///
/// **The image-cache key.** A first attempt asked for a bare
/// `CachedNetworkImage(url)` and claimed in its own doc that the picture was
/// already in memory. It was not. The grid renders through `HomeNetworkImage`,
/// which passes `memCacheWidth` — and that turns into a `ResizeImage` wrapper,
/// which is a DIFFERENT `ImageCache` key. The shuttle was a guaranteed cache
/// miss on every flight, and since its placeholder was `SizedBox.shrink()`,
/// what actually crossed the screen for the first frames was nothing at all.
/// [memCacheWidth] and [httpHeaders] exist so the caller can hand over the
/// exact key the grid already resolved.
///
/// **The crop.** The two ends have different aspect ratios — a grid poster is
/// roughly 3:4, the header is close to square — and `BoxFit.cover` recomputes
/// its crop from whatever rectangle it is given. Left alone the artwork pushes
/// inward about 13% on a 393-wide phone and 26% on a 360×640 one, sliding
/// inside its own frame while the frame is still moving. [_coverScale] cancels
/// that: the shuttle is scaled by the ratio between the two ends' cover
/// factors, lerped to 1 on arrival, so the visible crop holds still.
class PosterHero extends StatelessWidget {
  /// The flight is currently OFF, app-wide.
  ///
  /// It looked right in isolation and wrong in use: the shuttle is a
  /// full-resolution poster, and the detail page is doing its first layout,
  /// its first image decode and its first network call in the same frames the
  /// flight occupies. What should have been a 300 ms glide arrived as a stall
  /// and then a jump — reported as "detailga hero o'tishni qotayotgandek".
  ///
  /// Turned off here rather than by unpicking `heroTag` from the thirty-odd
  /// call sites that thread it: every end of every flight goes through this
  /// widget, so this is the one place that decides, and turning it back on is
  /// one word. A page that simply opens is not as pretty as a flight that
  /// works, and much prettier than one that does not.
  static const bool flightEnabled = false;

  const PosterHero({
    super.key,
    required this.tag,
    required this.url,
    required this.child,
    this.fromRadius = 10,
    this.toRadius = 0,
    this.memCacheWidth,
    this.httpHeaders,
    this.imageAspect = _posterAspect,
  });

  /// A poster's own width/height, used to work out where `cover` crops.
  ///
  /// Not measured: the flight starts before the image's intrinsic size is
  /// necessarily resolved, and a wrong guess for one frame is worse than a
  /// fixed value. Every catalogue this app talks to serves 2:3 artwork —
  /// TMDB's w500 is 500×750 — so that is the assumption, and it is a parameter
  /// rather than a constant so a landscape card can pass 16/9 without
  /// rewriting this.
  static const double _posterAspect = 2 / 3;

  /// Null disables the flight entirely, which is right for a page opened from
  /// a deeplink, a search result or the player — there is nothing to fly from.
  final String? tag;

  /// Used only by the shuttle. The two ends keep their own widgets, which is
  /// what lets the grid poster carry its badges and the header carry its
  /// gradients without either of them travelling.
  final String? url;

  final Widget child;

  /// Corner radius at the grid end and at the header end, interpolated across
  /// the flight so the corners do not pop square on takeoff and back on
  /// landing.
  final double fromRadius;
  final double toRadius;

  /// The decode width the SOURCE end used. Must be byte-identical to it or the
  /// shuttle misses the cache — see the class doc.
  final int? memCacheWidth;

  /// Defaults to [posterImageHeaders] for the url. Pass explicitly only when
  /// the calling end sends something different.
  final Map<String, String>? httpHeaders;

  final double imageAspect;

  /// How much `BoxFit.cover` has to scale the image to fill [box].
  ///
  /// The larger of the two ratios, which is the definition of cover: the axis
  /// that would leave a gap decides.
  static double _coverScale(double imageAspect, Size box) {
    if (box.width <= 0 || box.height <= 0) return 1;
    final boxAspect = box.width / box.height;
    return boxAspect > imageAspect
        ? boxAspect / imageAspect // box is wider — width decides
        : imageAspect / boxAspect; // box is taller — height decides
  }

  static Size? _sizeOf(BuildContext context) {
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize) return box.size;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final t = tag;
    if (t == null || !flightEnabled) return child;

    return Hero(
      tag: t,
      flightShuttleBuilder: (_, animation, direction, fromContext, toContext) {
        // `animation` runs 0→1 on a push and 1→0 on a pop; normalising here
        // means the rest reads in one direction only.
        final push = direction == HeroFlightDirection.push;

        // Both ends are laid out by the time a flight starts, so their sizes
        // are readable. When one is not — a hero whose end was rebuilt out
        // from under the flight — fall back to no scaling rather than to a
        // guess: an uncorrected crop is the old behaviour, and a wrong
        // correction is worse than none.
        final fromSize = _sizeOf(fromContext);
        final toSize = _sizeOf(toContext);
        final cropRatio = (fromSize != null && toSize != null)
            ? _coverScale(imageAspect, fromSize) /
                  _coverScale(imageAspect, toSize)
            : 1.0;

        return AnimatedBuilder(
          animation: animation,
          builder: (_, _) {
            final progress = push ? animation.value : 1 - animation.value;
            return ClipRRect(
              borderRadius: BorderRadius.circular(
                lerpDouble(fromRadius, toRadius, progress)!,
              ),
              child: Transform.scale(
                // Starts at the source's crop and relaxes to the
                // destination's, so the visible framing does not move while
                // the frame does.
                //
                // A uniform scale is exact here because every pair this app
                // ships crops on the same axis — portrait card into a portrait
                // header. A landscape card into a wide tablet header would
                // crop on the other axis, and that needs the source rects
                // lerped rather than a single factor. Not built, because
                // nothing ships that shape.
                scale: lerpDouble(cropRatio, 1.0, progress)!,
                child: _ShuttleImage(
                  url: url,
                  memCacheWidth: memCacheWidth,
                  httpHeaders: httpHeaders,
                ),
              ),
            );
          },
        );
      },
      child: child,
    );
  }
}

/// The image that actually crosses the screen.
///
/// Deliberately not the widget from either end: no placeholder, no fade, no
/// error frame. Built as a raw `Image` over `CachedNetworkImageProvider` so
/// the `ResizeImage` wrapper — and therefore the cache key — is under this
/// widget's control rather than inferred from a `LayoutBuilder` that measures
/// a rectangle which is changing every frame.
class _ShuttleImage extends StatelessWidget {
  const _ShuttleImage({
    required this.url,
    required this.memCacheWidth,
    required this.httpHeaders,
  });

  final String? url;
  final int? memCacheWidth;
  final Map<String, String>? httpHeaders;

  @override
  Widget build(BuildContext context) {
    final u = url;
    if (u == null || u.isEmpty) return const SizedBox.shrink();

    return Image(
      image: ResizeImage.resizeIfNeeded(
        memCacheWidth,
        null,
        CachedNetworkImageProvider(
          u,
          headers: httpHeaders ?? posterImageHeaders(u),
        ),
      ),
      fit: BoxFit.cover,
      // Holds the last frame while a new one resolves, so a cache miss shows
      // the old picture rather than a hole.
      gaplessPlayback: true,
      // Nothing on a miss rather than a grey block: an empty frame for the
      // 260 ms of a flight is invisible, and a grey one is the exact artefact
      // this class exists to remove.
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );
  }
}

/// The height of the detail header, and the single definition of it.
///
/// This is the VISIBLE height, status bar included. `SliverAppBar` wants that
/// number minus the inset — it adds `topPadding` to `expandedHeight` itself —
/// so the page subtracts it at the one place that needs to. Passing this
/// straight to `expandedHeight` counts the inset twice, which is what it used
/// to do: the header came out ~50dp taller than the rectangle both skeletons
/// draw, and therefore ~50dp taller than the rectangle the poster had just
/// been animated into.
double detailHeroHeight(BuildContext context) {
  final screenH = MediaQuery.sizeOf(context).height;
  final topPad = MediaQuery.paddingOf(context).top;
  return (screenH * 0.55).clamp(320.0, 440.0) + topPad;
}
