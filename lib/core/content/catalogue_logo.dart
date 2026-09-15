import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:soplay/core/content/catalogue.dart';
import 'package:soplay/features/anilist/presentation/widgets/anilist_logo.dart';

/// A catalogue's own mark, at chip size.
///
/// Its own artwork rather than a sparkle: "found through TMDB" should look
/// like TMDB, the way "tracked on AniList" already looks like AniList.
class CatalogueLogo extends StatelessWidget {
  const CatalogueLogo({super.key, required this.catalogue, this.size = 20});

  final Catalogue catalogue;
  final double size;

  @override
  Widget build(BuildContext context) => switch (catalogue) {
    Catalogue.anilist => AnilistLogo(size: size, radius: size * 0.22),
    Catalogue.tmdb => ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: SvgPicture.asset(
        'assets/icons/tmdb.svg',
        width: size,
        height: size,
      ),
    ),
  };
}
