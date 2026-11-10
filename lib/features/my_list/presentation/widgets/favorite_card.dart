import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/content/catalogue.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/home/presentation/widgets/home_shared_widgets.dart';
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

  static const double titleFontSize = 12;
  static const double titleLineHeight = 1.18;
  static const double metaFontSize = 10.5;
  static const double metaLineHeight = 1.2;
  static const double metaGap = 3;

  @override
  Widget build(BuildContext context) {
    final title =
        item.title.trim().isEmpty ? 'my_list.untitled'.tr() : item.title.trim();
    final description = item.description.trim();
    final meta = description.isNotEmpty
        ? description
        : Catalogue.displayName(item.provider.trim());

    return HoverTap(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  HomeNetworkImage(
                    url: item.thumbnail,
                    borderRadius: BorderRadius.zero,
                    placeholderIcon: Icons.movie_outlined,
                  ),
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: SizedBox(
                      height: 44,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Color(0xB0000000), Color(0x00000000)],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.52),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.bookmark_rounded,
                        color: Colors.white,
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
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.52),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Icon(
                          synced
                              ? Icons.cloud_done_rounded
                              : Icons.cloud_off_rounded,
                          color: synced
                              ? AppColors.primary
                              : Colors.white.withValues(alpha: 0.8),
                          size: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 7),
          FixedTextLines(
            fontSize: titleFontSize,
            lineHeight: titleLineHeight,
            lines: 2,
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: titleFontSize,
                fontWeight: FontWeight.w700,
                height: titleLineHeight,
              ),
            ),
          ),
          const SizedBox(height: metaGap),
          FixedTextLines(
            fontSize: metaFontSize,
            lineHeight: metaLineHeight,
            child: meta.isEmpty
                ? null
                : Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: metaFontSize,
                      fontWeight: FontWeight.w500,
                      height: metaLineHeight,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
