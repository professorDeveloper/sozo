import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/theme/app_colors.dart';

enum DownloadsView { titles, files }

/// Titles (the offline library) or files (the queue and the storage).
class DownloadsViewSwitch extends StatelessWidget {
  const DownloadsViewSwitch({
    super.key,
    required this.view,
    required this.onChanged,
  });

  final DownloadsView view;
  final ValueChanged<DownloadsView> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            for (final v in DownloadsView.values)
              Expanded(
                child: _Segment(
                  icon: v == DownloadsView.titles
                      ? Icons.video_library_rounded
                      : Icons.list_alt_rounded,
                  label: v == DownloadsView.titles
                      ? 'downloads.view_titles'.tr()
                      : 'downloads.view_files'.tr(),
                  selected: v == view,
                  onTap: () => onChanged(v),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.white : AppColors.textSecondary;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? AppColors.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
