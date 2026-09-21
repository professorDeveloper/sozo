import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/watch_services/domain/entities/watch_service_entity.dart';

/// One streaming service, as its mark.
///
/// A service is recognised by its logo, not by a poster, so this is square and
/// not a card from the title rails. What it borrows from the Live TV channel
/// tile is the rule that matters: these marks are drawn for a light background
/// as often as not, so the tile is a neutral card with the logo CONTAINED
/// inside it, never tinted, never cropped and never given a colour of its own.
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

  /// Read from the platform rather than passed in, so every surface that shows
  /// a service agrees.
  ///
  /// `isTvPlatform` first, and deliberately: every other card metric in this
  /// app branches on `isDesktopPlatform`, which is FALSE on a television — so a
  /// 1920px screen viewed from three metres quietly inherits the phone's 76pt
  /// marks.
  static double sizeFor() => isTvPlatform ? 112 : (isDesktopPlatform ? 92 : 76);

  /// The rail's height: the tile, the gap, and a line for the name.
  static double railHeight(BuildContext context) {
    final size = sizeFor();
    if (!isTvPlatform && !isDesktopPlatform) {
      return size + 6 + MediaQuery.textScalerOf(context).scale(10.5) * 1.35;
    }
    return size + 6 + MediaQuery.textScalerOf(context).scale(12) * 1.35;
  }

  @override
  Widget build(BuildContext context) {
    final size = sizeFor();
    final radius = isTvPlatform ? 18.0 : 16.0;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final nameSize = isTvPlatform || isDesktopPlatform ? 12.0 : 10.5;

    return HoverTap(
      onTap: () => onTap(service),
      // Traces the tile instead of boxing it.
      borderRadius: radius,
      // The tap leaves the screen, which is worth confirming under the thumb.
      haptic: true,
      child: SizedBox(
        width: size,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: size,
              height: size,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: service.logo == null
                  ? _initials()
                  : CachedNetworkImage(
                      imageUrl: service.logo!,
                      fit: BoxFit.contain,
                      // A row of twelve marks decoded at their 1000px original
                      // is the kind of thing that gets reported as "the app got
                      // slow".
                      memCacheWidth: (size * dpr).round(),
                      errorWidget: (_, _, _) => _initials(),
                      placeholder: (_, _) => const SizedBox.shrink(),
                    ),
            ),
            if (showName) ...[
              const SizedBox(height: 6),
              Text(
                service.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: nameSize,
                  fontWeight: FontWeight.w600,
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
  /// Its initials, never a generic icon: twelve identical glyphs is a row that
  /// says nothing, where "MX" is recognisable and is what the name says anyway.
  /// The same block answers a CDN 404, so a missing logo and a broken one look
  /// alike rather than one of them looking like a bug.
  Widget _initials() => Center(
    child: Text(
      service.initials,
      style: TextStyle(
        color: AppColors.textHint,
        fontSize: 15,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.5,
      ),
    ),
  );
}
