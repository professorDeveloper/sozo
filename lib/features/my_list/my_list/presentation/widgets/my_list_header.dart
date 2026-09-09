import 'dart:ui';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/theme/app_colors.dart';

class MyListHeader extends StatelessWidget {
  const MyListHeader({
    super.key,
    required this.topPad,
    required this.blurProgress,
  });

  final double topPad;
  final double blurProgress;

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
