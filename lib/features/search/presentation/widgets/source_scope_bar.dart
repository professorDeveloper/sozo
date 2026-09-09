import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/profile/domain/entities/provider_entity.dart';
import 'package:soplay/features/search/domain/entities/cross_search_scope.dart';

/// The scope control for all-source search: a scrolling rail of source chips
/// with "All sources" pinned at the front.
///
/// A rail rather than a dropdown or the old bottom sheet, because the two
/// things that matter here — *what is being searched right now* and *changing
/// it* — both have to be on screen. A menu shows neither until it is opened,
/// and the sheet it replaces reported the whole selection as the string
/// "1 selected", which is how a user searched one source without noticing.
/// The full list still lives one tap away behind the last chip; a rail is a
/// bad way to pick from two hundred sources, and a good way to see and undo
/// the handful you actually narrowed to.
class SourceScopeBar extends StatelessWidget {
  const SourceScopeBar({
    super.key,
    required this.providers,
    required this.order,
    required this.scope,
    required this.onToggle,
    required this.onSelectAll,
    required this.onOpenPicker,
    this.loading = false,
  });

  final List<ProviderEntity> providers;

  /// Chip order, held by the page so a chip never moves out from under the
  /// finger that just toggled it.
  final List<String> order;

  final CrossSearchScope scope;
  final ValueChanged<String> onToggle;
  final VoidCallback onSelectAll;
  final VoidCallback onOpenPicker;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final byId = {for (final p in providers) p.id: p};
    final ids = [for (final id in order) if (byId.containsKey(id)) id];

    return SizedBox(
      height: 40,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(width: 16),
          // Outside the scroll view, not merely first in it: "widen back to
          // everything" has to stay one tap away after the user has scrolled
          // the rail, which is exactly when a narrowed search looks broken.
          _Chip(
            label: loading
                ? 'search.loading_sources'.tr()
                : 'search.all_sources_n'.tr(args: ['${providers.length}']),
            selected: scope.isAll,
            icon: Icons.travel_explore,
            onTap: loading ? null : onSelectAll,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsetsDirectional.only(end: 16),
              itemCount: ids.length + 1,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                if (i == ids.length) {
                  return _Chip(
                    label: 'search.more_sources'.tr(),
                    selected: false,
                    icon: Icons.tune,
                    onTap: loading ? null : onOpenPicker,
                  );
                }
                final p = byId[ids[i]]!;
                // In "all" mode no individual chip reads as picked, so a tap on
                // one narrows to it instead of subtracting it from everything.
                final on = !scope.isAll && scope.includes(p.id);
                return _Chip(
                  label: p.name,
                  selected: on,
                  icon: on ? Icons.check : null,
                  onTap: () => onToggle(p.id),
                );
              },
            ),
          ),
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
    this.icon,
  });

  final String label;
  final bool selected;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : AppColors.textSecondary;
    return Material(
      color: selected ? AppColors.primary : AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: fg),
                const SizedBox(width: 6),
              ],
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
