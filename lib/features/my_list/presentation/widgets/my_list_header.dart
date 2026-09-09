import 'dart:ui';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';

class MyListHeader extends StatelessWidget {
  const MyListHeader({
    super.key,
    required this.topPad,
    required this.blurProgress,
    this.onRefresh,
  });

  final double topPad;
  final double blurProgress;

  final VoidCallback? onRefresh;

  static const double contentHeight = 58.0;

  @override
  Widget build(BuildContext context) {
    final progress = blurProgress.clamp(0.0, 1.0);

    final content = Container(
      padding: EdgeInsetsDirectional.fromSTEB(20, topPad + 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.navBackground.withValues(alpha: 0.78 * progress),
        border: progress > 0.05
            ? Border(
                bottom: BorderSide(
                  color: Colors.white.withValues(alpha: 0.07 * progress),
                  width: 0.5,
                ),
              )
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              'home.my_list'.tr(),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 28,
                fontWeight: FontWeight.w900,
                height: 1.05,
              ),
            ),
          ),
          // Entry point to the curated lists (Watch Later / Watched). They live
          // on their own page rather than as modes of this one — see
          // UserListsPage — so this is the only way in.
          IconButton(
            tooltip: 'user_lists.title'.tr(),
            icon: const Icon(
              Icons.playlist_add_check_rounded,
              color: AppColors.textSecondary,
            ),
            onPressed: () => context.push('/my-lists'),
          ),
          if (onRefresh != null)
            DesktopRefreshButton(
              color: AppColors.textSecondary,
              onRefresh: onRefresh!,
            ),
        ],
      ),
    );

    if (progress < 0.01) return content;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20 * progress, sigmaY: 20 * progress),
        child: content,
      ),
    );
  }
}
