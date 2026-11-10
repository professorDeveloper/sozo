import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/extensions/source_language.dart' as srclang;
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/tv/tv.dart';
import 'package:soplay/features/extensions/domain/entities/mangayomi_source.dart';

/// One chip in a [SourceFilterChipRow].
class SourceFilterOption {
  const SourceFilterOption({
    required this.label,
    required this.active,
    required this.onTap,
    this.count,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final int? count;
}

/// A horizontal row of filter chips, styled like the catalog's type and
/// language rows and reachable with a D-pad on TV.
class SourceFilterChipRow extends StatelessWidget {
  const SourceFilterChipRow({
    super.key,
    required this.options,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  final List<SourceFilterOption> options;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) => Center(child: _chip(context, options[i])),
      ),
    );
  }

  Widget _chip(BuildContext context, SourceFilterOption o) {
    return Semantics(
      button: true,
      selected: o.active,
      child: TvFocusable(
        onPressed: o.onTap,
        borderRadius: 17,
        ensureVisibleAlignment: 0.5,
        child: AnimatedContainer(
          duration: Duration(
            milliseconds: MediaQuery.disableAnimationsOf(context) ? 0 : 120,
          ),
          curve: Curves.easeOutCubic,
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: o.active ? AppColors.primary : AppColors.surface,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: o.active
                  ? AppColors.primary.withValues(alpha: 0.55)
                  : Colors.white.withValues(alpha: 0.07),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                o.label,
                style: TextStyle(
                  color: o.active ? Colors.white : AppColors.textSecondary,
                  fontSize: 12.5,
                  fontWeight: o.active ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
              if (o.count != null) ...[
                const SizedBox(width: 5),
                Text(
                  '${o.count}',
                  style: TextStyle(
                    color: o.active
                        ? AppColors.primaryLight.withValues(alpha: 0.75)
                        : AppColors.textHint,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// All / anime / manga / novel.
class MangayomiTypeFilterRow extends StatelessWidget {
  const MangayomiTypeFilterRow({
    super.key,
    required this.selected,
    required this.onSelected,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  final MangayomiItemType? selected;
  final ValueChanged<MangayomiItemType?> onSelected;
  final EdgeInsetsGeometry padding;

  static const _options = <(MangayomiItemType?, String)>[
    (null, 'catalog.type_all'),
    (MangayomiItemType.anime, 'catalog.type_anime'),
    (MangayomiItemType.manga, 'catalog.type_manga'),
    (MangayomiItemType.novel, 'catalog.type_novel'),
  ];

  @override
  Widget build(BuildContext context) => SourceFilterChipRow(
    padding: padding,
    options: [
      for (final (type, key) in _options)
        SourceFilterOption(
          label: key.tr(),
          active: type == selected,
          onTap: () => onSelected(type),
        ),
    ],
  );
}

/// Language chips built from the languages the listed sources carry.
class MangayomiLanguageFilterRow extends StatelessWidget {
  const MangayomiLanguageFilterRow({
    super.key,
    required this.counts,
    required this.selected,
    required this.onToggle,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  final Map<String, int> counts;
  final List<String> selected;
  final ValueChanged<String> onToggle;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final ordered = srclang
        .orderedLanguages(counts.keys, selected)
        .where((c) => c != srclang.kAllLanguages);
    return SourceFilterChipRow(
      padding: padding,
      options: [
        SourceFilterOption(
          label: srclang.labelFor(srclang.kAllLanguages),
          active: selected.isEmpty,
          onTap: () => onToggle(srclang.kAllLanguages),
        ),
        for (final code in ordered)
          SourceFilterOption(
            label: srclang.labelFor(code),
            count: counts[code],
            active: selected.any((c) => srclang.normalizeLang(c) == code),
            onTap: () => onToggle(code),
          ),
      ],
    );
  }
}
