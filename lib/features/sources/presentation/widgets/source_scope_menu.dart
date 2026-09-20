import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/sources/domain/source_ecosystem.dart';
import 'package:soplay/features/sources/domain/source_scope.dart';

/// One button that says which slice of the sources is showing, and opens a
/// menu to change it.
///
/// This replaces a horizontal row of chips. The row had two problems that got
/// worse the more sources somebody installed: it is a second scrollable strip
/// above a list that already scrolls, so the gesture is ambiguous and the
/// chips beyond the fourth are found by dragging; and it can only ever show one
/// axis. A repository is the second axis — with six CloudStream repos
/// installed, "CloudStream" is two hundred sources and the question is which
/// two hundred — and there is no room for a second row of chips above a list.
///
/// A menu has room for both, costs one line instead of a strip, and states the
/// current selection in words rather than as the one chip that happens to be
/// filled in.
class SourceScopeMenu extends StatelessWidget {
  const SourceScopeMenu({
    super.key,
    required this.counts,
    required this.scope,
    required this.onPick,
    this.dense = false,
  });

  final SourceScopeCounts counts;
  final SourceScope scope;
  final ValueChanged<SourceScope> onPick;

  /// The sheet is tighter than the page and its controls are smaller.
  final bool dense;

  /// The ecosystems worth offering: the ones that are actually here.
  ///
  /// An ecosystem with nothing in it filters to an empty list, which teaches
  /// people the filter is broken.
  List<SourceEcosystem> get _ecosystems => [
    for (final e in SourceEcosystem.values)
      if ((counts.byEcosystem[e] ?? 0) > 0) e,
  ];

  String _label() {
    final e = scope.ecosystem;
    if (e == null) return 'sources.eco_all'.tr();
    final r = scope.repo;
    if (r == null) return e.label;
    return '${e.label} · ${repoLabel(r)}';
  }

  @override
  Widget build(BuildContext context) {
    final ecosystems = _ecosystems;
    // Nothing to choose between. A control with one option is a label, and it
    // would take a line of a list that needs every one it has.
    if (ecosystems.length < 2) return const SizedBox.shrink();

    final count = counts.countFor(scope);
    final active = !scope.isAll;
    return Padding(
      padding: EdgeInsets.fromLTRB(12, dense ? 2 : 4, 12, dense ? 2 : 6),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: '${_label()}, $count',
            child: ExcludeSemantics(
              child: InkWell(
                onTap: () => _open(context, ecosystems),
                borderRadius: BorderRadius.circular(999),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  padding: EdgeInsets.fromLTRB(
                    14,
                    dense ? 7 : 9,
                    10,
                    dense ? 7 : 9,
                  ),
                  decoration: BoxDecoration(
                    color: active
                        ? AppColors.primary.withValues(alpha: 0.16)
                        : AppColors.card,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: active
                          ? AppColors.primary.withValues(alpha: 0.55)
                          : Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _label(),
                        style: TextStyle(
                          color: active
                              ? AppColors.primary
                              : AppColors.textPrimary,
                          fontSize: dense ? 12.5 : 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 7),
                      // The count is the difference between decoration and
                      // something worth reading: it answers "where did the
                      // sources go" without tapping anything.
                      Text(
                        '$count',
                        style: TextStyle(
                          color: active
                              ? AppColors.primary.withValues(alpha: 0.85)
                              : AppColors.textHint,
                          fontSize: dense ? 12 : 12.5,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.expand_more_rounded,
                        size: dense ? 17 : 18,
                        color: active ? AppColors.primary : AppColors.textHint,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const Spacer(),
          // Clearing is one tap from anywhere, rather than opening the menu to
          // find "All" at the top of it.
          if (active)
            TextButton(
              onPressed: () {
                HapticFeedback.selectionClick();
                onPick(SourceScope.all);
              },
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Text(
                'general.clear'.tr(),
                style: TextStyle(
                  color: AppColors.textHint,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _open(
    BuildContext context,
    List<SourceEcosystem> ecosystems,
  ) async {
    HapticFeedback.selectionClick();
    final picked = await showModalBottomSheet<SourceScope>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) =>
          _ScopeSheet(counts: counts, scope: scope, ecosystems: ecosystems),
    );
    if (picked != null) onPick(picked);
  }
}

class _ScopeSheet extends StatelessWidget {
  const _ScopeSheet({
    required this.counts,
    required this.scope,
    required this.ecosystems,
  });

  final SourceScopeCounts counts;
  final SourceScope scope;
  final List<SourceEcosystem> ecosystems;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      _row(
        context,
        label: 'sources.eco_all'.tr(),
        count: counts.total,
        selected: scope.isAll,
        value: SourceScope.all,
        indent: false,
      ),
    ];
    for (final e in ecosystems) {
      rows.add(
        _row(
          context,
          label: e.label,
          count: counts.byEcosystem[e] ?? 0,
          selected: scope.ecosystem == e && scope.repo == null,
          value: SourceScope(ecosystem: e),
          indent: false,
        ),
      );
      // Repositories under the ecosystem they belong to, and only where there
      // is more than one of them — see [SourceScopeCounts.reposIn].
      for (final repo in counts.reposIn(e)) {
        rows.add(
          _row(
            context,
            label: repoLabel(repo.key),
            count: repo.value,
            selected: scope.ecosystem == e && scope.repo == repo.key,
            value: SourceScope(ecosystem: e, repo: repo.key),
            indent: true,
          ),
        );
      }
    }

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 12),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'sources.filter_title'.tr(),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ...rows,
          ],
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context, {
    required String label,
    required int count,
    required bool selected,
    required SourceScope value,
    required bool indent,
  }) => InkWell(
    onTap: () => Navigator.of(context).pop(value),
    child: Padding(
      padding: EdgeInsets.fromLTRB(indent ? 38 : 20, 12, 20, 12),
      child: Row(
        children: [
          if (indent)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: Icon(
                Icons.subdirectory_arrow_right_rounded,
                size: 15,
                color: AppColors.textHint.withValues(alpha: 0.7),
              ),
            ),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? AppColors.primary : AppColors.textPrimary,
                fontSize: indent ? 13.5 : 14.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '$count',
            style: TextStyle(
              color: AppColors.textHint,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          SizedBox(
            width: 28,
            child: selected
                ? Icon(Icons.check_rounded, size: 18, color: AppColors.primary)
                : null,
          ),
        ],
      ),
    ),
  );
}
