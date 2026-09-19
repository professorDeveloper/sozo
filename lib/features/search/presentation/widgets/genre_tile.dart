import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/network/image_headers.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/tv/tv.dart';

/// A genre as a card: its artwork, a dark scrim, its name.
///
/// A row of names is a form; a grid of covers is a place to go.
///
/// ## No colour of its own
///
/// Every tile used to be washed in a hue taken from a nine-colour wheel keyed
/// on its position — red, orange, yellow, green, teal, blue, purple — laid over
/// real artwork. Two things were wrong with it. A tint that comes from the
/// tile's INDEX means nothing: "Action" was red because it happened to be
/// first, and became orange the moment a source listed one genre before it, so
/// the colour was noise dressed as information. And over a photograph it fought
/// the photograph, leaving the tile neither the artwork's colour nor the app's.
///
/// The scrim is neutral now. The artwork supplies all the colour on this grid,
/// which is what makes a wall of covers look like a catalogue rather than a
/// swatch book.
///
/// A tile whose artwork has not arrived, or never will, gets a plain dark card
/// — one step lighter than the page so it still reads as a surface — rather
/// than a coloured block standing in for a picture.
class GenreTile extends StatelessWidget {
  const GenreTile({
    super.key,
    required this.label,
    required this.image,
    required this.index,
    required this.onTap,
  });

  final String label;
  final String image;

  /// Kept for the entrance stagger. It no longer picks a colour.
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final card = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // What shows through where there is no artwork, and behind it while
          // it loads: a surface, not a colour.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF242426), Color(0xFF151517)],
              ),
            ),
          ),
          if (image.isNotEmpty)
            CachedNetworkImage(
              imageUrl: image,
              httpHeaders: posterImageHeaders(image),
              fit: BoxFit.cover,
              // A cover is portrait and the tile is not: the top of a poster
              // is the face, the bottom is the credits.
              alignment: const Alignment(0, -0.6),
              fadeInDuration: const Duration(milliseconds: 220),
              errorWidget: (_, _, _) => const SizedBox.shrink(),
            ),
          // One wash, black, so the name is readable on any cover.
          //
          // It starts clear and finishes heavy, because the covers behind these
          // tiles are POSTERS and a poster has the film's own title painted
          // across it — so "Action" sat on top of the word JOHN WICK at a
          // similar size and weight and the eye could not tell which of the two
          // was the label. The ramp leaves the top of the artwork alone and
          // takes the bottom third far enough down that whatever is written
          // there stops competing.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x00000000),
                  Color(0x80000000),
                  Color(0xE6000000),
                ],
                stops: [0.0, 0.5, 1],
              ),
            ),
          ),
          PositionedDirectional(
            start: 10,
            end: 10,
            bottom: 8,
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                height: 1.15,
                letterSpacing: -0.2,
                shadows: [Shadow(color: Colors.black87, blurRadius: 6)],
              ),
            ),
          ),
        ],
      ),
    );
    if (isTvPlatform) {
      return TvFocusable(onPressed: onTap, borderRadius: 12, child: card);
    }
    // The same press the posters have, rather than a Material ripple.
    //
    // Two tappable things sat on this screen and answered differently: a
    // poster dipped under the thumb and a genre tile spread a coloured splash
    // from the touch point. The ripple is an Android idiom, and on a browsing
    // surface made of artwork it reads as ink spilt on a picture — where the
    // dip reads as the picture itself being pressed. One surface, one
    // response.
    return HoverTap(
      onTap: onTap,
      haptic: true,
      borderRadius: 12,
      child: card,
    );
  }
}
