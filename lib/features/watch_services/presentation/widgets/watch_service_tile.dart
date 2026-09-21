import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/watch_services/domain/entities/watch_service_entity.dart';

/// One streaming service, as its mark.
///
/// TMDB's service logos are app icons: square, full-bleed, and carrying their
/// own background — Netflix is a black square, Prime Video a white one. So the
/// mark IS the tile here rather than sitting inside it, clipped to the tile's
/// own radius. Inset on a card the way a channel logo is, they read as stickers
/// stuck onto a box: two corner radii, one inside the other, neither matching.
///
/// The logo is never tinted or recoloured for the same reason it is never
/// cropped by `contain` elsewhere — these marks are owned artwork and half of
/// them are drawn for a light background.
class WatchServiceTile extends StatelessWidget {
  const WatchServiceTile({
    super.key,
    required this.service,
    required this.onTap,
    this.showName = true,
  });

  final WatchServiceEntity service;
  final ValueChanged<WatchServiceEntity> onTap;
  final bool showName;

  /// Read from the platform rather than passed in, so every surface showing a
  /// service agrees on the size.
  ///
  /// `isTvPlatform` first, and deliberately: every other card metric in this
  /// app branches on `isDesktopPlatform`, which is FALSE on a television — so a
  /// 1920px screen viewed from three metres quietly inherits the phone's marks.
  static double sizeFor() => isTvPlatform ? 104 : (isDesktopPlatform ? 88 : 72);

  static double radiusFor() => sizeFor() * 0.235;

  /// How tall the name's line box is, exactly.
  ///
  /// Pinned rather than left to the font, and it is the only reason a rail or a
  /// grid can be measured at all: a `Text` with no `height` takes whatever line
  /// box its typeface asks for, which is not `fontSize` and is not the same
  /// across the fallback fonts a device picks for CJK or Arabic. Computing the
  /// extent from a guess at that number is what made the tiles overflow.
  static const double _nameHeight = 1.3;
  static const double _gap = 8;

  static double _nameSize() => isTvPlatform || isDesktopPlatform ? 12 : 11;

  /// The full height of a tile with its name, for whatever lays them out.
  static double extentFor(BuildContext context) =>
      sizeFor() +
      _gap +
      MediaQuery.textScalerOf(context).scale(_nameSize()) * _nameHeight;

  @override
  Widget build(BuildContext context) {
    final size = sizeFor();
    final radius = radiusFor();
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final nameSize = _nameSize();

    return HoverTap(
      onTap: () => onTap(service),
      borderRadius: radius,
      haptic: true,
      child: SizedBox(
        width: size,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The shadow sits on the container and the clip on the child, so
            // the mark takes the radius without the shadow being clipped away
            // with it.
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(radius),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (service.logo == null)
                      _initials()
                    else
                      CachedNetworkImage(
                        imageUrl: service.logo!,
                        // Cover, not contain: these are square app icons that
                        // already carry their own padding, and containing them
                        // inside another box leaves a ring of card colour that
                        // makes every mark look shrunken.
                        fit: BoxFit.cover,
                        // Twelve marks decoded at their 1000px original is the
                        // kind of thing that gets reported as "the app got
                        // slow".
                        memCacheWidth: (size * dpr).round(),
                        fadeInDuration: const Duration(milliseconds: 220),
                        errorWidget: (_, _, _) => _initials(),
                        placeholder: (_, _) => const SizedBox.shrink(),
                      ),
                    // A hairline inside the clip rather than a border outside
                    // it: half these marks are white, and without it a light
                    // one dissolves into a light background on the picker
                    // sheet.
                    IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(radius),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.10),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (showName) ...[
              const SizedBox(height: _gap),
              Text(
                service.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: nameSize,
                  fontWeight: FontWeight.w600,
                  height: _nameHeight,
                ),
                // Belt and braces with [_nameHeight]: a fallback font chosen
                // for a name in another script must not be allowed to make the
                // line taller than the grid was measured for.
                strutStyle: StrutStyle(
                  fontSize: nameSize,
                  height: _nameHeight,
                  forceStrutHeight: true,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// What a service with no mark on file shows.
  ///
  /// Its initials, never a generic icon: twelve identical glyphs is a grid that
  /// says nothing, where "MX" is recognisable and is what the name says anyway.
  /// The same block answers a CDN 404, so a missing mark and a broken one look
  /// alike rather than one of them looking like a bug.
  Widget _initials() => ColoredBox(
    color: AppColors.card,
    child: Center(
      child: Text(
        service.initials,
        style: TextStyle(
          color: AppColors.textHint,
          fontSize: sizeFor() * 0.28,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    ),
  );
}
