import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/tv/tv.dart';

class DetailHeroBackground extends StatelessWidget {
  const DetailHeroBackground({
    super.key,
    required this.thumbnail,
    required this.title,
  });

  final String? thumbnail;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _ThumbnailImage(url: thumbnail),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment(0, 0.4),
              colors: [Color(0xCC000000), Color(0x00000000)],
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SizedBox(
            height: 220,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  // All three stops are the page background at falling
                  // opacity — that is what makes the poster dissolve INTO the
                  // page. The middle one used to be the literal #181818, which
                  // left a grey band hanging in mid-air under AMOLED.
                  colors: [
                    AppColors.background,
                    AppColors.background.withValues(alpha: 0.933),
                    AppColors.background.withValues(alpha: 0.0),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 20,
          child: Text(
            title.trim(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              height: 1.15,
              letterSpacing: -0.3,
              shadows: [
                Shadow(
                  color: Colors.black87,
                  blurRadius: 20,
                  offset: Offset(0, 2),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ThumbnailImage extends StatelessWidget {
  const _ThumbnailImage({required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return Container(
        color: AppColors.surfaceVariant,
        child: const Center(
          child: Icon(
            Icons.movie_creation_outlined,
            color: AppColors.textHint,
            size: 64,
          ),
        ),
      );
    }
    // Cached, like every other poster in the app: the hero is the largest image
    // on the screen and it was the only one re-downloaded on every visit, so
    // coming back to a title you just left redrew the grey block first.
    //
    // Placeholder underneath rather than swapped in: the artwork used to cut in
    // hard over a flat grey block, and the hard cut is the most visible thing
    // on the page while it happens.
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: AppColors.surfaceVariant),
        CachedNetworkImage(
          imageUrl: url!,
          fit: BoxFit.cover,
          fadeInDuration: const Duration(milliseconds: 240),
          fadeInCurve: Curves.easeOut,
          placeholder: (_, _) => ColoredBox(color: AppColors.surfaceVariant),
          errorWidget: (_, _, _) => Container(
            color: AppColors.surfaceVariant,
            child: const Center(
              child: Icon(
                Icons.broken_image_outlined,
                color: AppColors.textHint,
                size: 64,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class DetailFloatingTopBar extends StatelessWidget {
  const DetailFloatingTopBar({
    super.key,
    required this.onBack,
    this.onBookmark,
    this.isBookmarked = false,
  });

  final VoidCallback onBack;
  final VoidCallback? onBookmark;
  final bool isBookmarked;

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    return Padding(
      padding: EdgeInsets.only(top: topPad + 8, left: 8, right: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _TopBarButton(
            icon: Icons.arrow_back_ios_new_rounded,
            onTap: onBack,
          ),
          if (onBookmark != null)
            _TopBarButton(
              icon: isBookmarked
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_border_rounded,
              onTap: onBookmark!,
            ),
        ],
      ),
    );
  }
}

class _TopBarButton extends StatelessWidget {
  const _TopBarButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final button = ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          width: 38,
          height: 38,
          color: Colors.black.withValues(alpha: 0.38),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      ),
    );

    // Android TV: back and bookmark are the detail page's only chrome; on a
    // bare GestureDetector the D-pad could never reach either. Off TV: unchanged.
    if (isTvPlatform) {
      return TvFocusable(
        onPressed: onTap,
        borderRadius: 19,
        child: button,
      );
    }

    return GestureDetector(onTap: onTap, child: button);
  }
}
