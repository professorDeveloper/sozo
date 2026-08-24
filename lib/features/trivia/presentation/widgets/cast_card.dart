import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/home/presentation/widgets/home_shared_widgets.dart';
import 'package:soplay/features/trivia/domain/entities/cast_person_entity.dart';

/// A single circular cast/character card used by the "Popular now" grid and the
/// as-you-type results grid. The profile photo carries a shared [Hero] tag so it
/// flies into the Actor Hero screen on tap. When [highlight] is non-empty the
/// matched substring of the name is bolded.
///
/// Layout follows the shipped people-grid idiom (detail → Cast): a fixed 64px
/// avatar, an 8px gap, a two-line name and a one-line sub-label. The avatar is a
/// fixed size — never an `AspectRatio` — so a wider tile does not inflate the
/// circle, which is what made the old grid read as "huge circles".
class CastCard extends StatelessWidget {
  const CastCard({
    super.key,
    required this.person,
    required this.onTap,
    this.highlight = '',
  });

  final CastPersonEntity person;
  final VoidCallback onTap;
  final String highlight;

  /// Avatar diameter in the grid — matches `detail_cast_tab.dart`'s 64.
  static const double avatarSize = 64;

  /// Stable Hero tag shared with [ActorHeroPage]'s profile photo.
  static String heroTag(CastPersonEntity p) => 'trivia-cast-${p.kind}-${p.id}';

  @override
  Widget build(BuildContext context) {
    final knownFor = person.knownFor
        .where((e) => e.trim().isNotEmpty)
        .take(2)
        .join(' · ');

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Hero(
            tag: heroTag(person),
            child: CastAvatar(
              url: person.profileUrl,
              name: person.name,
              size: avatarSize,
            ),
          ),
          const SizedBox(height: 8),
          _HighlightedName(name: person.name, query: highlight),
          if (knownFor.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              knownFor,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textHint,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Circular avatar with the app's neutral grey ring + initials placeholder.
/// Reused by the cast grid, the actor hero and the top-fans strip.
///
/// [size] pins the diameter (the shipped idiom — 58 in rails, 64 in grids).
/// When omitted the avatar falls back to filling its parent squarely, which the
/// hero header relies on.
class CastAvatar extends StatelessWidget {
  const CastAvatar({
    super.key,
    required this.url,
    required this.name,
    this.highlightRing = false,
    this.size,
  });

  final String url;
  final String name;

  /// Selected / medal state — a solid brand ring, matching the top-fans medal
  /// precedent. Never a gradient.
  final bool highlightRing;

  final double? size;

  @override
  Widget build(BuildContext context) {
    final avatar = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surfaceVariant,
        border: Border.all(
          color: highlightRing ? AppColors.primary : AppColors.border,
          width: highlightRing ? 2 : 1.2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: _image(),
    );

    if (size != null) return avatar;
    return AspectRatio(aspectRatio: 1, child: avatar);
  }

  Widget _image() {
    if (url.trim().isEmpty) return _Initials(name: name);
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      fadeInDuration: const Duration(milliseconds: 140),
      placeholder: (_, _) =>
          const ShimmerWrapper(child: ColoredBox(color: Colors.white)),
      errorWidget: (_, _, _) => _Initials(name: name),
    );
  }
}

/// Initials on a flat `surfaceVariant` disc — the shipped placeholder
/// (`detail_cast.dart`). Two-word names yield two initials, so far fewer tiles
/// collapse to a lone letter. The glyph is sized off the real diameter (~0.31×,
/// i.e. 18 at 58 and 20 at 64) instead of a `FittedBox`, which is what made the
/// old 100px circles look like broken art next to real photos.
class _Initials extends StatelessWidget {
  const _Initials({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.biggest.shortestSide;
        final fontSize = (side.isFinite ? side * 0.31 : 20.0).clamp(12.0, 22.0);
        return Container(
          color: AppColors.surfaceVariant,
          alignment: Alignment.center,
          child: Text(
            _initials(name),
            style: TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w800,
              fontSize: fontSize,
              height: 1,
            ),
          ),
        );
      },
    );
  }

  String _initials(String value) {
    final parts = value.trim().split(RegExp(r'\s+'));
    if (parts.length > 1 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    final trimmed = value.trim();
    return trimmed.isNotEmpty ? trimmed[0].toUpperCase() : '?';
  }
}

/// The name line, bolding the matched substring of [query] (case-insensitive).
class _HighlightedName extends StatelessWidget {
  const _HighlightedName({required this.name, required this.query});

  final String name;
  final String query;

  @override
  Widget build(BuildContext context) {
    const base = TextStyle(
      color: AppColors.textPrimary,
      fontSize: 12,
      fontWeight: FontWeight.w700,
      height: 1.2,
    );

    final q = query.trim().toLowerCase();
    final lower = name.toLowerCase();
    final start = q.isEmpty ? -1 : lower.indexOf(q);

    if (start < 0) {
      return Text(
        name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: base,
      );
    }
    final end = start + q.length;

    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      text: TextSpan(
        style: base,
        children: [
          TextSpan(text: name.substring(0, start)),
          TextSpan(
            text: name.substring(start, end),
            style: TextStyle(
              color: AppColors.primaryLight,
              fontWeight: FontWeight.w800,
            ),
          ),
          TextSpan(text: name.substring(end)),
        ],
      ),
    );
  }
}

/// Shimmer skeleton mirroring a [CastCard] for the loading grids — same fixed
/// 64 avatar, same gaps, so the grid does not jump when real data lands.
class CastCardSkeleton extends StatelessWidget {
  const CastCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const ShimmerWrapper(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: CastCard.avatarSize,
            height: CastCard.avatarSize,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
          SizedBox(height: 8),
          HomeSkeletonBox(width: 76, height: 11, radius: 4),
          SizedBox(height: 5),
          HomeSkeletonBox(width: 46, height: 9, radius: 4),
        ],
      ),
    );
  }
}
