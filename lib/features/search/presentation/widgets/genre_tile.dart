import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/network/image_headers.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/tv/tv.dart';

/// A genre as a card: its artwork, a wash of colour, its name.
///
/// A row of names is a form; a grid of covers is a place to go. The image is
/// whatever the catalogue offers — the most popular title's cover on AniList,
/// a known poster on TMDB — and where there is none the tile is a colour of
/// its own, so a source that ships no artwork still gets a grid and not a
/// column of grey boxes.
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

  /// Picks the tint. Neighbouring tiles get neighbouring hues, so the grid
  /// reads as one palette rather than a random handful.
  final int index;
  final VoidCallback onTap;

  static const List<Color> _tints = [
    Color(0xFFE0525C),
    Color(0xFFE08A3C),
    Color(0xFFD6B83A),
    Color(0xFF4CB870),
    Color(0xFF0FB3A6),
    Color(0xFF3D8BF2),
    Color(0xFF6D4AFF),
    Color(0xFFB04AD8),
    Color(0xFFE05C9C),
  ];

  @override
  Widget build(BuildContext context) {
    final tint = _tints[index % _tints.length];
    final card = ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  tint.withValues(alpha: 0.55),
                  tint.withValues(alpha: 0.22),
                ],
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
          // Two washes: the colour so a bright cover still belongs to the
          // grid, and the dark so the name is readable on any of them.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  tint.withValues(alpha: 0.18),
                  Colors.black.withValues(alpha: 0.72),
                ],
                stops: const [0.25, 1],
              ),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 10,
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                height: 1.15,
                letterSpacing: -0.2,
                shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
              ),
            ),
          ),
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                splashColor: tint.withValues(alpha: 0.25),
                highlightColor: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
        ],
      ),
    );
    if (isTvPlatform) {
      return TvFocusable(onPressed: onTap, borderRadius: 14, child: card);
    }
    return card;
  }
}
