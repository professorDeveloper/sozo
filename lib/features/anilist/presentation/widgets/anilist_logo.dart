import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The official AniList logo, from
/// https://commons.wikimedia.org/wiki/File:AniList_logo.svg
///
/// Rendered in its own colours — the artwork includes its dark tile, so tinting
/// it to a single colour would erase the mark it exists to show.
class AnilistLogo extends StatelessWidget {
  const AnilistLogo({super.key, this.size = 20, this.radius = 5});

  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: SvgPicture.asset(
      'assets/icons/anilist.svg',
      width: size,
      height: size,
    ),
  );
}

/// The logo at badge size, for a settings row or an empty state.
class AnilistLogoBadge extends StatelessWidget {
  const AnilistLogoBadge({super.key, this.size = 44, this.radius = 12});

  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) => AnilistLogo(size: size, radius: radius);
}
