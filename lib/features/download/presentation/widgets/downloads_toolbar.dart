import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/download/presentation/bloc/downloads_state.dart';

/// The filter row.
///
/// Four states, and the one that matters is `problems`: before it existed a
/// failed or missing download was a row somewhere in a list of thirty, found
/// only by scrolling.
class DownloadsToolbar extends StatelessWidget {
  const DownloadsToolbar({
    super.key,
    required this.filter,
    required this.onFilter,
  });

  final DownloadsFilter filter;
  final ValueChanged<DownloadsFilter> onFilter;

  String _label(DownloadsFilter f) => switch (f) {
        DownloadsFilter.all => 'downloads.filter_all'.tr(),
        DownloadsFilter.active => 'downloads.filter_active'.tr(),
        DownloadsFilter.completed => 'downloads.filter_done'.tr(),
        DownloadsFilter.problems => 'downloads.filter_problems'.tr(),
      };

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsetsDirectional.only(start: 16, end: 16),
        children: [
          for (final f in DownloadsFilter.values) ...[
            _Chip(
              label: _label(f),
              selected: f == filter,
              onTap: () => onFilter(f),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: selected
            ? AppColors.primary
            : Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(11),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : AppColors.textSecondary,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
