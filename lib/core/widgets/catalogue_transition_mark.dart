import 'package:flutter/material.dart';
import 'package:soplay/core/content/catalogue.dart';
import 'package:soplay/core/content/catalogue_logo.dart';
import 'package:soplay/core/content/content_mode.dart';
import 'package:soplay/core/widgets/mode_destination_artwork.dart';
import 'package:soplay/core/widgets/sozo_dragon_transition.dart';

/// One focal point: a destination-toned Sozo relief hands off to the catalogue
/// logo. Official logos keep their original colours and are never filtered.
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
    final departure = Curves.easeInOut.transform(
      ((progress - .44) / .14).clamp(0, 1),
    );
    final arrival = Curves.easeOutCubic.transform(
      ((progress - .64) / .24).clamp(0, 1),
    );
    // Luminance tint preserves the dragon's relief instead of flattening it
    // with srcIn. The same destination colour also paints the screen reveal.
    final tint = <double>[];
    for (final channel in [accent.r, accent.g, accent.b]) {
      tint.addAll([
        .2126 * channel * .8,
        .7152 * channel * .8,
        .0722 * channel * .8,
        0,
        51 * channel,
      ]);
    }
    tint.addAll([0, 0, 0, 1, 0]);
    return SizedBox.square(
      dimension: 144,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Opacity(
            opacity: 1 - departure,
            child: Transform.scale(
              scale: 1 - .04 * departure,
              child: ColorFiltered(
                colorFilter: ColorFilter.matrix(tint),
                child: SozoDragonTransition(
                  size: 144,
                  progress: (progress / .4).clamp(0, 1),
                ),
              ),
            ),
          ),
          Opacity(
            opacity: arrival,
            child: Transform.scale(
              scale: .98 + .02 * arrival,
              child: catalogue != null
                  ? CatalogueLogo(catalogue: catalogue!, size: 112)
                  : ModeDestinationArtwork(mode: mode, color: accent),
            ),
          ),
        ],
      ),
    );
  }
}
