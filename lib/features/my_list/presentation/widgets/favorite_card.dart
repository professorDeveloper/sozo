import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/presentation/widgets/kaizoku_badge.dart';
import 'package:soplay/core/presentation/widgets/kaizoku_media_card.dart';
import 'package:soplay/core/theme/kaizoku_colors.dart';
import 'package:soplay/features/my_list/domain/entities/favorite_entity.dart';

class FavoriteCard extends StatelessWidget {
  const FavoriteCard({
    super.key,
    required this.item,
    required this.onTap,
    this.synced = false,
  });

  final FavoriteEntity item;
  final VoidCallback onTap;
  final bool synced;

  @override
  Widget build(BuildContext context) {
    final title =
        item.title.trim().isEmpty ? 'my_list.untitled'.tr() : item.title.trim();
    final description = item.description.trim();
    final meta = description.isNotEmpty ? description : item.provider.trim();

    return Stack(
      children: [
        KaizokuMediaCard(
          title: title,
          imageUrl: item.thumbnail,
          subtitle: meta.isNotEmpty ? meta : null,
          ratio: KaizokuCardRatio.poster,
          badgeText: item.provider.isNotEmpty ? item.provider.toUpperCase() : null,
          badgeVariant: KaizokuBadgeVariant.glass,
          onTap: onTap,
        ),
        Positioned(
          top: 6,
          right: 6,
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
                width: 0.8,
              ),
            ),
            child: const Icon(
              Icons.bookmark_rounded,
              color: KaizokuColors.neonCrimson,
              size: 16,
            ),
          ),
        ),
        Positioned(
          top: 6,
          left: 6,
          child: Tooltip(
            message: (synced
                    ? 'my_list.saved_account'
                    : 'my_list.saved_local')
                .tr(),
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.1),
                  width: 0.8,
                ),
              ),
              child: Icon(
                synced
                    ? Icons.cloud_done_rounded
                    : Icons.cloud_off_rounded,
                color: synced
                    ? KaizokuColors.electricCyan
                    : Colors.white.withValues(alpha: 0.7),
                size: 13,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
