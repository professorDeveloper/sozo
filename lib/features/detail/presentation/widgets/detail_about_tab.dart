import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/detail/domain/entities/ani_info.dart';

/// What the catalogue knows and a source does not, as its own tab.
///
/// It was a grid under the Play button and filled the page before the tabs
/// were reached; a title's record is worth a tab of its own, and only a
/// title that came with a record gets one. Studio, what it was adapted
/// from, how many episodes, where it ranks, its status — each in its own
/// cell, so the eye can find one without reading the others.
class DetailAboutTab extends StatelessWidget {
  const DetailAboutTab({super.key, required this.ani});

  final AniInfo ani;

  @override
  Widget build(BuildContext context) {
    final cells = <(String, String)>[
      if (ani.studio != null) ('detail.about_studio'.tr(), ani.studio!),
      if (ani.source != null) ('detail.about_source'.tr(), _word(ani.source!)),
      if (ani.episodes != null)
        ('detail.about_episodes'.tr(), '${ani.episodes}'),
      if (ani.rankText != null) ('detail.about_rank'.tr(), ani.rankText!),
      if (ani.status != null) ('detail.about_status'.tr(), _word(ani.status!)),
      if (ani.format != null) ('detail.about_format'.tr(), _word(ani.format!)),
    ];
    if (cells.isEmpty && ani.tags.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, c) {
              final columns = c.maxWidth >= 520 ? 3 : 2;
              final width = (c.maxWidth - (columns - 1) * 12) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final (label, value) in cells)
                    SizedBox(
                      width: width,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label.toUpperCase(),
                              style: const TextStyle(
                                color: AppColors.textHint,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              value,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          if (ani.tags.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in ani.tags)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      t,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// LIGHT_NOVEL → Light novel; RELEASING → Releasing.
  static String _word(String raw) {
    final w = raw.toLowerCase().replaceAll('_', ' ');
    return w.isEmpty ? raw : w[0].toUpperCase() + w.substring(1);
  }
}
