import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'app_glass.dart';
import 'glass_surface.dart';

/// The plate a control stands on over video — the player's buttons, its
/// pills — as an iPhone draws controls over a picture: clear glass.
///
/// iOS 26 uses its clear glass over media (WWDC25 219): no frost, next to no
/// tint, the picture seen through it bent at its rim — with a dimming laid in
/// it, because a white glyph over clear glass over a white sky is no glyph.
/// [glyphDim] is the black the player's discs have always been, so on an
/// iPhone the controls keep their contrast and gain the glass.
///
/// Everywhere else — Android, TV, desktop — it is that black plate alone, as
/// before: glass over 60 fps video is a read of the screen every frame, and
/// those devices have no system glass for it to match.
///
/// Glass is never laid on glass: the pieces of one row stand in one
/// [MediaGlassLayer] and share its read of the picture; a piece standing
/// alone is a layer of its own.
class MediaGlass extends StatelessWidget {
  const MediaGlass({super.key, required this.child, this.radius, this.dim});

  /// The piece's corners; null is a capsule — a circle when it is square.
  final double? radius;

  /// What is laid in the glass under [child]: black at [glyphDim] when null.
  /// A control showing an active state passes its accent here instead.
  final Color? dim;

  final Widget child;

  /// The dimming in a glass that carries a white glyph, from the worst
  /// picture — a blown-out white one — with the clear glass's own white
  /// (0.04) counted over it. WCAG asks 3:1 of a glyph, so the glass over
  /// white may be at most the sRGB grey 0.584. Black at 0.45 under a 0.04
  /// white leaves 0.568: 3.16:1, and over a real frame the picture still
  /// shows through.
  static const double glyphDim = 0.45;

  static const Color _plate = Color(0xFF000000);

  /// Whether controls over video are drawn as glass here.
  static bool get drawsGlass => defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Widget build(BuildContext context) {
    final fill = dim ?? _plate.withValues(alpha: glyphDim);
    final plate = Positioned.fill(
      child: _Plate(radius: radius, color: fill, glass: drawsGlass),
    );
    if (!drawsGlass) {
      return Stack(children: [plate, child]);
    }
    final piece = Stack(
      children: [
        // Laid before the shape: the renderer paints its layer's glass first
        // whatever the order, so the dimming lands over the bent picture and
        // under the glass's tint and its lit rim — the rim stays a light.
        plate,
        Positioned.fill(child: GlassShape(radius: radius)),
        child,
      ],
    );
    if (_InLayer.of(context)) return piece;
    return MediaGlassLayer(child: piece);
  }
}

/// One read of the picture for the [MediaGlass] pieces of one row: on an
/// iPhone a group of the clear glass ([GlassGroup], [GlassKind.clear]);
/// elsewhere nothing at all.
///
/// The whole row fades as one: the renderer draws a group's glass through
/// the group, not through an opacity between the group and a piece, so a
/// piece faded on its own inside a row would leave its glass behind.
class MediaGlassLayer extends StatelessWidget {
  const MediaGlassLayer({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!MediaGlass.drawsGlass) return child;
    return GlassGroup(
      kind: GlassKind.clear,
      child: _InLayer(child: child),
    );
  }
}

/// Marks what stands in a [MediaGlassLayer], so a piece in it is a shape of
/// that layer rather than a layer — glass on glass — of its own.
class _InLayer extends InheritedWidget {
  const _InLayer({required super.child});

  static bool of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_InLayer>() != null;

  @override
  bool updateShouldNotify(_InLayer oldWidget) => false;
}

/// The dimming: in the glass's own shape on an iPhone, and the plain circle
/// or rounded plate the player has always drawn everywhere else.
class _Plate extends StatelessWidget {
  const _Plate({
    required this.radius,
    required this.color,
    required this.glass,
  });

  final double? radius;
  final Color color;
  final bool glass;

  @override
  Widget build(BuildContext context) {
    final r = radius;
    if (!glass) {
      return DecoratedBox(
        decoration: ShapeDecoration(
          color: color,
          shape: r == null
              ? const StadiumBorder()
              : RoundedRectangleBorder(borderRadius: BorderRadius.circular(r)),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, box) => DecoratedBox(
        decoration: ShapeDecoration(
          color: color,
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(
              r ?? box.biggest.shortestSide / 2,
            ),
          ),
        ),
      ),
    );
  }
}
