import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/network/image_headers.dart';
import 'package:soplay/core/trailer/trailer_query.dart';
import 'package:soplay/core/widgets/poster_hero.dart';
import 'package:soplay/features/detail/presentation/widgets/hero_trailer_preview.dart';

class DetailHeroBackground extends StatelessWidget {
  const DetailHeroBackground({
    super.key,
    required this.thumbnail,
    required this.title,
    this.heroTag,
    this.trailerQuery,
    this.trailerActive = false,
  });

  final String? thumbnail;
  final String title;

  /// Matches the tag on the poster that was tapped, so the image flies here
  /// rather than the page appearing from nothing. Null when there is nothing
  /// to fly from — a deeplink, a search result, the player.
  final String? heroTag;

  /// What to look up for the preview that plays over the poster once the page
  /// has settled. Null only on the skeletons — a placeholder has no title to
  /// look anything up by. Whether the title HAS a trailer is answered later,
  /// by the preview itself, which draws nothing until it has one.
  final TrailerQuery? trailerQuery;

  /// Whether the header is on screen. The preview stops when it is not.
  final bool trailerActive;

  @override
  Widget build(BuildContext context) {
    final trailer = trailerQuery;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Only the image travels; the gradients and the title stay with the
        // page. A gradient in flight is a dark rectangle sliding across the
        // screen, and a title in flight is text scaling from 9pt to 26pt.
        _Bloom(
          child: PosterHero(
            tag: heroTag,
            url: thumbnail,
            child: _ThumbnailImage(url: thumbnail),
          ),
        ),
        // Between the poster and the furniture: the gradients and the title
        // have to sit over the trailer exactly as they sit over the artwork,
        // or the title becomes unreadable the moment a bright frame plays.
        //
        // NOT inside the PosterHero. A video in a hero flight would be
        // interpolated from a grid tile, and it has no business travelling —
        // what flies is the poster the viewer tapped.
        if (trailer != null)
          HeroTrailerPreview(query: trailer, active: trailerActive),
        // Everything else fades in WITH the route rather than being painted at
        // full strength from the first frame.
        //
        // Without this the destination page is already fully drawn while the
        // poster is still crossing the screen: the dark scrims and the 26pt
        // title sit over an empty header, and the artwork lands underneath
        // furniture that arrived before it. Tying them to the route animation
        // means the poster flies into a clean space and the page assembles
        // around it as it settles.
        _HeroOverlayFade(
          hasFlight: heroTag != null,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment(0, 0.4),
                    colors: [Color(0xCC000000), Color(0x00000000)],
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SizedBox(
                  height: 220,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        // All three stops are the page background at falling
                        // opacity — that is what makes the poster dissolve INTO the
                        // page. The middle one used to be the literal #181818, which
                        // left a grey band hanging in mid-air under AMOLED.
                        colors: [
                          AppColors.background,
                          AppColors.background.withValues(alpha: 0.933),
                          AppColors.background.withValues(alpha: 0.0),
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 20,
                child: Text(
                  title.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    height: 1.15,
                    letterSpacing: -0.3,
                    shadows: [
                      Shadow(
                        color: Colors.black87,
                        blurRadius: 20,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ThumbnailImage extends StatelessWidget {
  const _ThumbnailImage({required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return Container(
        color: AppColors.surfaceVariant,
        child: const Center(
          child: Icon(
            Icons.movie_creation_outlined,
            color: AppColors.textHint,
            size: 64,
          ),
        ),
      );
    }
    // Cached, like every other poster in the app: the hero is the largest image
    // on the screen and it was the only one re-downloaded on every visit, so
    // coming back to a title you just left redrew the grey block first.
    //
    // Placeholder underneath rather than swapped in: the artwork used to cut in
    // hard over a flat grey block, and the hard cut is the most visible thing
    // on the page while it happens.
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: AppColors.surfaceVariant),
        CachedNetworkImage(
          imageUrl: url!,
          // The same headers the grid sent. A poster the host served to one
          // widget and refused to the other is a header the hero flies into
          // and then loses.
          httpHeaders: posterImageHeaders(url!),
          fit: BoxFit.cover,
          fadeInDuration: const Duration(milliseconds: 240),
          fadeInCurve: Curves.easeOut,
          placeholder: (_, _) => ColoredBox(color: AppColors.surfaceVariant),
          errorWidget: (_, _, _) => Container(
            color: AppColors.surfaceVariant,
            child: const Center(
              child: Icon(
                Icons.broken_image_outlined,
                color: AppColors.textHint,
                size: 64,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Fades the header's furniture in along the incoming route's animation.
///
/// The curve is deliberately late and short — nothing for the first 45% of the
/// transition, then a quick fade. That window is roughly how long the poster
/// takes to cross, so the gradients and the title appear once it has arrived
/// rather than hanging over the space it is heading for.
///
/// Falls back to fully visible when there is no route animation to read (the
/// first route, a test, an embedded use): a hidden overlay is a worse failure
/// than an unanimated one.
///
/// Stateful only so the [CurvedAnimation] can be disposed. Built inside
/// `build` it looked harmless, but its constructor attaches a status listener
/// to the parent unconditionally and only `dispose()` detaches it — so every
/// rebuild left another listener on the route's animation, for the life of
/// the route, three at a time in this widget.
class _HeroOverlayFade extends StatefulWidget {
  const _HeroOverlayFade({required this.hasFlight, required this.child});

  /// Whether a poster is actually flying into this header.
  ///
  /// The delay is justified entirely by the poster's crossing time, and there
  /// are 21 `DetailArgs(...)` call sites in the app of which exactly one
  /// passes a tag. So on every deeplink, search result, related card and
  /// player hand-off, this was holding the scrims and the 26pt title at zero
  /// for the first 45% of the transition for no reason — a bare unscrimmed
  /// untitled image for half the animation, then furniture popping on over a
  /// page that had already settled. It also skips an ancestor walk that
  /// otherwise runs on the no-flight path.
  final bool hasFlight;

  final Widget child;

  @override
  State<_HeroOverlayFade> createState() => _HeroOverlayFadeState();
}

class _HeroOverlayFadeState extends State<_HeroOverlayFade> {
  CurvedAnimation? _curve;
  Animation<double>? _parent;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Same gate as [_Bloom], for the same reason and on the same animation:
    // on iOS the route is a Cupertino page, so this controller runs backwards
    // under an edge-swipe and the scrims fade out as the finger moves — the
    // header's gradients measurably gone by about halfway through a drag the
    // user may still abandon. The arrival fade belongs to arriving.
    final animation = widget.hasFlight && _Bloom.runsHere
        ? ModalRoute.of(context)?.animation
        : null;
    if (identical(animation, _parent)) return;
    _curve?.dispose();
    _parent = animation;
    _curve = animation == null
        ? null
        : CurvedAnimation(
            parent: animation,
            curve: const Interval(0.45, 1.0, curve: Curves.easeOut),
            reverseCurve: Curves.easeIn,
          );
  }

  @override
  void dispose() {
    _curve?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = _curve;
    if (curve == null) return widget.child;
    return FadeTransition(opacity: curve, child: widget.child);
  }
}

/// The artwork sharpens into place as the page arrives.
///
/// Along the incoming route's animation the image starts blurred and a little
/// larger, and resolves to sharp at full size — a photograph pulling into
/// focus, the same beat as the page rising under it. Nothing once the route
/// has settled: the filter is only in the tree for the run, so a page being
/// scrolled or revisited paints a plain image.
///
/// ## Off on iOS
///
/// This reads `ModalRoute.of(context)?.animation`, and on iOS that animation is
/// not only the arrival. (On Android it is the same object the bloom
/// transition is handed — `CustomTransitionPage` passes `route.animation`
/// straight into its `transitionsBuilder` — so there is no contrast to draw
/// there; the difference is entirely what the route does with it.)
/// `_bloomPage` in `app_router.dart` hands iOS the platform page so
/// the edge swipe survives, and a Cupertino route's back gesture drives that
/// same animation controller backwards as the finger moves. Ungated, dragging
/// in from the left edge blurs and grows the poster under the thumb, frame by
/// frame, at 18px of blur across the largest image on the screen — a beat that
/// belongs to arriving, played over a gesture that is leaving, and one iOS
/// does not draw that way anywhere else.
///
/// So the gate is [defaultTargetPlatform], deliberately the same check
/// `_bloomPage` makes to choose the page type: the two decisions are one
/// decision, and if they ever disagree the platform that gets the Cupertino
/// page is the platform that gets the blur on its back swipe.
class _Bloom extends StatefulWidget {
  const _Bloom({required this.child});

  final Widget child;

  static const double _blur = 18;
  static const double _grow = 0.10;

  /// True wherever the route animation means "arriving" and nothing else.
  ///
  /// Read by [_HeroOverlayFade] too: both ride the route animation, so both
  /// have to be off on exactly the platforms where it is also the back
  /// gesture, and one getter is how they stay that way.
  static bool get runsHere => defaultTargetPlatform != TargetPlatform.iOS;

  @override
  State<_Bloom> createState() => _BloomState();
}

class _BloomState extends State<_Bloom> {
  Animation<double>? _parent;
  CurvedAnimation? _curve;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Also skips the ancestor walk on the platform that has no use for the
    // answer.
    final animation = _Bloom.runsHere
        ? ModalRoute.of(context)?.animation
        : null;
    if (identical(animation, _parent)) return;
    _curve?.dispose();
    _parent = animation;
    _curve = animation == null
        ? null
        : CurvedAnimation(
            parent: animation,
            curve: const Cubic(0.05, 0.7, 0.1, 1.0),
          );
  }

  @override
  void dispose() {
    _curve?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = _curve;
    if (curve == null || MediaQuery.disableAnimationsOf(context)) {
      return widget.child;
    }
    // The same tree before, during and after the run — only the numbers
    // change. Swapping the filter out at the end would remount the image
    // under it, and a poster that blinks as it lands undoes the landing.
    return AnimatedBuilder(
      animation: curve,
      child: widget.child,
      builder: (context, child) {
        final t = curve.value;
        final sigma = _Bloom._blur * (1 - t);
        return ClipRect(
          child: Transform.scale(
            scale: 1 + _Bloom._grow * (1 - t),
            child: ImageFiltered(
              enabled: sigma > 0.1,
              imageFilter: ImageFilter.blur(
                sigmaX: sigma,
                sigmaY: sigma,
                tileMode: TileMode.clamp,
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
