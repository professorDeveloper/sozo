import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../system/platform_utils.dart';
import '../../theme/kaizoku_colors.dart';
import '../desktop/desktop_interaction.dart';
import '../tv/tv_focus_node.dart';
import 'kaizoku_badge.dart';

enum KaizokuCardRatio {
  poster, // 2:3
  backdrop, // 16:9
  square, // 1:1
}

/// Unified media card across all platforms with responsive hover zoom and TV D-pad focus ring.
class KaizokuMediaCard extends StatelessWidget {
  const KaizokuMediaCard({
    super.key,
    required this.title,
    required this.imageUrl,
    this.subtitle,
    this.ratio = KaizokuCardRatio.poster,
    this.badgeText,
    this.badgeVariant = KaizokuBadgeVariant.glass,
    this.tagText,
    this.progress, // 0.0 to 1.0
    this.onTap,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
  });

  final String title;
  final String? imageUrl;
  final String? subtitle;
  final KaizokuCardRatio ratio;
  final String? badgeText;
  final KaizokuBadgeVariant badgeVariant;
  final String? tagText;
  final double? progress;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;

  double get _aspectRatio {
    switch (ratio) {
      case KaizokuCardRatio.poster:
        return 2 / 3;
      case KaizokuCardRatio.backdrop:
        return 16 / 9;
      case KaizokuCardRatio.square:
        return 1 / 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget card = AspectRatio(
      aspectRatio: _aspectRatio,
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Media Image or Fallback Background
            _buildImage(),
            // Bottom Title Scrim
            const DecoratedBox(decoration: BoxDecoration(gradient: KaizokuColors.posterScrim)),
            // Top Badges
            if (badgeText != null || tagText != null)
              Positioned(
                top: 8,
                left: 8,
                right: 8,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (badgeText != null)
                      KaizokuBadge(label: badgeText!, variant: badgeVariant)
                    else
                      const SizedBox.shrink(),
                    if (tagText != null)
                      KaizokuBadge(label: tagText!, variant: KaizokuBadgeVariant.glass)
                    else
                      const SizedBox.shrink(),
                  ],
                ),
              ),
            // Bottom Metadata (Title, Subtitle, Progress Bar)
            Positioned(
              left: 10,
              right: 10,
              bottom: progress != null && progress! > 0 ? 12 : 8,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: KaizokuColors.textHigh,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: KaizokuColors.textMedium,
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Watch Progress Bar
            if (progress != null && progress! > 0)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SizedBox(
                  height: 3.5,
                  child: LinearProgressIndicator(
                    value: progress!.clamp(0.0, 1.0),
                    backgroundColor: Colors.white.withAlpha(50),
                    valueColor: const AlwaysStoppedAnimation<Color>(KaizokuColors.crimson),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    // Platform-specific interaction wrapper
    if (isTvPlatform) {
      return KaizokuTvFocusable(
        onTap: onTap,
        borderRadius: borderRadius,
        scaleFactor: 1.06,
        focusColor: KaizokuColors.tvFocusRing,
        child: card,
      );
    }

    if (isDesktopPlatform) {
      return KaizokuDesktopHover(
        hoverScale: 1.03,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: card,
        ),
      );
    }

    // Touch mobile
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: card,
    );
  }

  Widget _buildImage() {
    final url = imageUrl?.trim();
    if (url == null || url.isEmpty) {
      return Container(
        color: KaizokuColors.surfaceElevated,
        child: const Center(
          child: Icon(
            Icons.movie_outlined,
            color: KaizokuColors.textMuted,
            size: 32,
          ),
        ),
      );
    }

    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (_, __) => Container(
        color: KaizokuColors.surface,
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(KaizokuColors.borderSubtle),
            ),
          ),
        ),
      ),
      errorWidget: (_, __, ___) => Container(
        color: KaizokuColors.surfaceElevated,
        child: const Center(
          child: Icon(
            Icons.broken_image_outlined,
            color: KaizokuColors.textMuted,
            size: 28,
          ),
        ),
      ),
    );
  }
}
