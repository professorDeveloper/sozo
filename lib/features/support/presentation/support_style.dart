import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/support/data/support_models.dart';

/// Labels and glyphs the support screens share.
extension SupportCategoryUi on SupportCategory {
  String get label => 'support.cat_$name'.tr();

  IconData get icon => switch (this) {
    SupportCategory.playback => Icons.play_circle_outline_rounded,
    SupportCategory.account => Icons.person_outline_rounded,
    SupportCategory.content => Icons.video_library_outlined,
    SupportCategory.bug => Icons.bug_report_outlined,
    SupportCategory.idea => Icons.lightbulb_outline_rounded,
    SupportCategory.other => Icons.help_outline_rounded,
  };
}

class SupportStatusChip extends StatelessWidget {
  const SupportStatusChip({super.key, required this.status});

  final SupportStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      SupportStatus.open => AppColors.textSecondary,
      SupportStatus.answered => AppColors.success,
      SupportStatus.closed => AppColors.textHint,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'support.status_${status.name}'.tr(),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// "14:05" today, "26.09" this year, "26.09.2025" before.
String supportTime(DateTime at) {
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  if (at.year == now.year && at.month == now.month && at.day == now.day) {
    return '${two(at.hour)}:${two(at.minute)}';
  }
  final date = '${two(at.day)}.${two(at.month)}';
  return at.year == now.year ? date : '$date.${at.year}';
}
