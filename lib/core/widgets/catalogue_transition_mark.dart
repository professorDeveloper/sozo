import 'package:flutter/material.dart';
import 'package:soplay/core/content/catalogue.dart';
import 'package:soplay/core/content/catalogue_logo.dart';
import 'package:soplay/core/content/content_mode.dart';
import 'package:soplay/core/widgets/mode_destination_artwork.dart';

/// The destination is visible throughout the switch; no intermediary brand.
class CatalogueTransitionMark extends StatelessWidget {
  const CatalogueTransitionMark({
    super.key,
    required this.mode,
    required this.accent,
    required this.progress,
    this.catalogue,
  });
  final ContentMode mode;
  final Catalogue? catalogue;
  final Color accent;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final t = MediaQuery.disableAnimationsOf(context)
        ? 1.0
        : progress.clamp(0.0, 1.0);
    final arrival = Curves.easeOutCubic.transform((t / .8).clamp(0, 1));
    final parts = catalogue == Catalogue.tmdb ? 4 : 2;
    return SizedBox.square(
      dimension: 144,
      child: Center(
        child: Transform.scale(
          scale: .92 + .08 * arrival,
          child: catalogue == null
              ? Opacity(
                  opacity: (t / .16).clamp(0, 1),
                  child: ModeDestinationArtwork(
                    mode: mode,
                    color: accent,
                    progress: t,
                  ),
                )
              : SizedBox.square(
                  dimension: 112,
                  child: Stack(
                    children: [
                      for (var i = 0; i < parts; i++)
                        _LogoPart(
                          catalogue: catalogue!,
                          index: i,
                          parts: parts,
                          progress: t,
                        ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _LogoPart extends StatelessWidget {
  const _LogoPart({
    required this.catalogue,
    required this.index,
    required this.parts,
    required this.progress,
  });
  final Catalogue catalogue;
  final int index;
  final int parts;
  final double progress;
  @override
  Widget build(BuildContext context) {
    final t = Curves.easeOutCubic.transform(
      ((progress - index * .09) / .65).clamp(0, 1),
    );
    return Opacity(
      opacity: t,
      child: Transform.translate(
        offset: Offset(0, (1 - t) * (10 + index * 2)),
        child: ClipRect(
          clipper: _PartClipper(index, parts),
          child: ExcludeSemantics(
            child: CatalogueLogo(catalogue: catalogue, size: 112),
          ),
        ),
      ),
    );
  }
}

class _PartClipper extends CustomClipper<Rect> {
  const _PartClipper(this.index, this.parts);
  final int index;
  final int parts;
  @override
  Rect getClip(Size size) => Rect.fromLTRB(
    size.width * index / parts,
    0,
    size.width * (index + 1) / parts,
    size.height,
  );
  @override
  bool shouldReclip(_PartClipper old) =>
      old.index != index || old.parts != parts;
}
