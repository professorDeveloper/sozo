import 'package:easy_localization/easy_localization.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/detail/domain/entities/cast_entity.dart';
import 'package:soplay/features/detail/presentation/pages/actor_page.dart';
import 'package:soplay/features/detail/presentation/widgets/detail_empty_state.dart';

class DetailCastTab extends StatelessWidget {
  const DetailCastTab({super.key, required this.cast, this.director});

  final List<CastEntity> cast;
  final String? director;

  @override
  Widget build(BuildContext context) {
    final hasDirector = director != null && director!.trim().isNotEmpty;

    if (cast.isEmpty && !hasDirector) {
      return DetailEmptyState(
        icon: Icons.people_outline_rounded,
        message: 'detail.no_cast'.tr(),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasDirector)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _DirectorTile(director: director!.trim()),
            ),
          if (hasDirector && cast.isNotEmpty) const SizedBox(height: 16),
          if (cast.isNotEmpty)
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: cast.length,
              // 0.78 left the cell exactly as tall as its contents, so any
              // two-line name or a bumped system font size overflowed it.
              gridDelegate: responsiveGridDelegate(
                mobileCrossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 14,
                childAspectRatio: 0.70,
              ),
              itemBuilder: (_, i) => _CastGridCard(cast: cast[i]),
            ),
        ],
      ),
    );
  }
}

class _DirectorTile extends StatelessWidget {
  const _DirectorTile({required this.director});
  final String director;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border, width: 0.6),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.movie_creation_outlined,
            color: AppColors.textHint,
            size: 18,
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              'movie.director'.tr(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textHint,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              director,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CastGridCard extends StatelessWidget {
  const _CastGridCard({required this.cast});
  final CastEntity cast;

  @override
  Widget build(BuildContext context) {
    return HoverTap(
      onTap: () {
        if (cast.name.trim().isEmpty) return;
        context.push(
          '/actor',
          extra: ActorArgs(name: cast.name.trim(), image: cast.image),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border, width: 0.6),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _CastAvatar(name: cast.name, imageUrl: cast.image),
            const SizedBox(height: 8),
            Flexible(
              child: Text(
                cast.name.trim().isNotEmpty ? cast.name : '—',
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'detail.actor'.tr(),
              style: const TextStyle(
                color: AppColors.textHint,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CastAvatar extends StatelessWidget {
  const _CastAvatar({required this.name, required this.imageUrl});
  final String name;
  final String imageUrl;

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length > 1 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    final t = name.trim();
    return t.isNotEmpty ? t[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surfaceVariant,
        border: Border.all(color: AppColors.border, width: 1.2),
      ),
      clipBehavior: Clip.antiAlias,
      child: imageUrl.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.cover,
              fadeInDuration: const Duration(milliseconds: 160),
              errorWidget: (_, _, _) => _Initials(initials: _initials),
              placeholder: (_, _) => _Initials(initials: _initials),
            )
          : _Initials(initials: _initials),
    );
  }
}

class _Initials extends StatelessWidget {
  const _Initials({required this.initials});
  final String initials;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceVariant,
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
