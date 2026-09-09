import 'package:cached_network_image/cached_network_image.dart';
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
        PosterHero(
          tag: heroTag,
          url: thumbnail,
          child: _ThumbnailImage(url: thumbnail),
        ),
        // Between the poster and the furniture: the gradients and the title
        // have to sit over the trailer exactly as they sit over the artwork,
        // or the title becomes unreadable the moment a bright frame plays.
        //
        // NOT inside the PosterHero. A video in a hero flight would be
        // interpolated from a grid tile, and it has no business travelling —
        // what flies is the poster the viewer tapped.
        if (trailer != null)
          HeroTrailerPreview(
            query: trailer,
            active: trailerActive,
          ),
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
          child: Stack(fit: StackFit.expand, children: [
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
          ]),
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
    final animation = widget.hasFlight
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

