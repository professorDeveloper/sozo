import 'package:flutter/material.dart';

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
    Catalogue.tmdb => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF0D253F),
        borderRadius: BorderRadius.circular(size * 0.22),
      ),
      alignment: Alignment.center,
      child: ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) => const LinearGradient(
          colors: [Color(0xFF90CEA1), Color(0xFF01B4E4)],
        ).createShader(bounds),
        // flutter_svg cannot render the <text> in the old badge asset.
        child: Text(
          'TMDB',
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            fontFamily: 'sans-serif',
            fontSize: size * .22,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            height: 1,
            letterSpacing: 0,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    ),
    _ => AnilistLogo(size: size, radius: size * 0.22),
  };
}
