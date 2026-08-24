import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/theme/app_theme.dart';
import 'package:soplay/features/anilist/presentation/widgets/anilist_logo.dart';

/// AniList's own blue. Used only for AniList affordances, so a "connect" or
/// "tracked" badge is never mistaken for a Sozo-native action in red.
const Color kAnilistBlue = Color(0xFF02A9FF);
const Color kAnilistBlueDeep = Color(0xFF0073C4);

/// Cover art with a fixed 2:3 poster ratio.
///
/// The ratio is enforced rather than inherited from the image: AniList covers
/// vary by a few pixels, and a grid of almost-aligned posters reads as broken.
class AnilistCover extends StatelessWidget {
  const AnilistCover({
    super.key,
    required this.url,
    this.width,
    this.radius = 10,
  });

  final String? url;
  final double? width;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final image = AspectRatio(
      aspectRatio: 2 / 3,
      child: (url == null || url!.isEmpty)
          ? const _CoverPlaceholder()
          : CachedNetworkImage(
              imageUrl: url!,
              fit: BoxFit.cover,
              fadeInDuration: const Duration(milliseconds: 180),
              placeholder: (_, _) => const _CoverPlaceholder(),
              errorWidget: (_, _, _) => const _CoverPlaceholder(),
            ),
    );
    final clipped = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: image,
    );
    return width == null ? clipped : SizedBox(width: width, child: clipped);
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder();

  @override
  Widget build(BuildContext context) => Container(
        color: AppColors.surfaceVariant,
        child: const Icon(
          Icons.movie_creation_outlined,
          color: AppColors.textHint,
          size: 22,
        ),
      );
}

/// A small filled label — episode counts, formats, "tracked" markers.
class AnilistChip extends StatelessWidget {
  const AnilistChip({
    super.key,
    required this.label,
    this.icon,
    this.color = kAnilistBlue,
    this.filled = false,
  });

  final String label;
  final IconData? icon;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: icon == null ? 8 : 7, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: filled ? 1 : 0.32), width: 0.6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: filled ? Colors.white : color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: filled ? Colors.white : color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// The rounded progress rail used on every entry card.
class AnilistProgressBar extends StatelessWidget {
  const AnilistProgressBar({super.key, required this.value, this.color = kAnilistBlue});

  /// 0..1, or null when the total is unknown — which renders a flat unfilled
  /// rail rather than an indeterminate animation that implies loading.
  final double? value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value ?? 0),
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        builder: (_, v, _) => LinearProgressIndicator(
          value: v,
          minHeight: 4,
          backgroundColor: Colors.white.withValues(alpha: 0.08),
          valueColor: AlwaysStoppedAnimation(color),
        ),
      ),
    );
  }
}

/// "Nothing here" and "that failed", in the one shape every AniList screen
/// uses. Each screen had grown its own icon, its own retry button and its own
/// vertical offset for the same two states.
class AnilistStateMessage extends StatelessWidget {
  const AnilistStateMessage({
    super.key,
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
    this.accent = kAnilistBlue,
  });

  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// The tracker's brand colour. Defaults to AniList's, so every existing call
  /// site is unchanged; MyAnimeList passes its own.
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 46, color: AppColors.textHint.withValues(alpha: 0.6)),
          const SizedBox(height: 14),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textHint,
              fontSize: 13.5,
              height: 1.5,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onAction,
              style: OutlinedButton.styleFrom(
                foregroundColor: accent,
                side: BorderSide(color: accent.withValues(alpha: 0.5)),
                // The app's outlined buttons are full-width page actions; this
                // one sits under a paragraph and should read as an aside.
                minimumSize: const Size(0, 42),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(kButtonRadius),
                ),
              ),
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

/// [AnilistStateMessage] centred in a scroll view, so a screen with nothing in
/// it can still be pulled to refresh and still be dragged where the scrollable
/// drives a sheet.
///
/// Centres on the viewport rather than on a fraction of the screen height: the
/// lists this replaces sit under a tab bar, a day strip or a filter row, and a
/// screen fraction put the message somewhere different on each of them.
class AnilistScrollableMessage extends StatelessWidget {
  const AnilistScrollableMessage({
    super.key,
    required this.message,
    this.controller,
  });

  final AnilistStateMessage message;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        controller: controller,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(child: message),
          ),
        ],
      ),
    );
  }
}

/// The block shown wherever a screen needs an AniList connection it does not
/// have. One widget so the message and the button never drift apart between
/// the library, the upcoming list and the title screen.
class AnilistConnectPrompt extends StatelessWidget {
  const AnilistConnectPrompt({
    super.key,
    required this.message,
    required this.actionLabel,
    required this.onConnect,
    this.busy = false,
    this.accent = kAnilistBlue,
  });

  final String message;
  final String actionLabel;
  final VoidCallback onConnect;
  final bool busy;

  /// See [AnilistStateMessage.accent].
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AnilistLogoBadge(size: 68, radius: 18),
            const SizedBox(height: 18),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: busy ? null : onConnect,
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(kButtonRadius),
                ),
              ),
              icon: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.open_in_new_rounded, size: 18),
              label: Text(
                actionLabel,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
