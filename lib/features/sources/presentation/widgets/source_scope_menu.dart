import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/sources/domain/source_ecosystem.dart';
import 'package:soplay/features/sources/domain/source_scope.dart';

/// Visible ecosystem choices shared by the source hub and quick switcher.
/// Repository selection is a labelled second step, including when only one
/// ecosystem is installed. No horizontal scrolling is needed to find a host.
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

  @override
  Widget build(BuildContext context) {
    final ecosystems = _ecosystems;
    if (ecosystems.isEmpty) return const SizedBox.shrink();
    final ecosystem =
        scope.ecosystem ?? (ecosystems.length == 1 ? ecosystems.single : null);
    final hasRepos = ecosystem != null && counts.reposIn(ecosystem).isNotEmpty;
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune_rounded, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'sources.filter_type'.tr(),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (!scope.isAll)
                TextButton(
                  onPressed: () => onPick(SourceScope.all),
                  child: Text('general.clear'.tr()),
                ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final entry in <(SourceEcosystem?, String, int)>[
                (null, 'sources.eco_all'.tr(), counts.total),
                for (final e in ecosystems)
                  (e, e.label, counts.byEcosystem[e] ?? 0),
              ])
                ChoiceChip(
                  label: Text('${entry.$2} · ${entry.$3}'),
                  selected: scope.ecosystem == entry.$1,
                  showCheckmark: true,
                  selectedColor: colors.primaryContainer,
                  labelStyle: TextStyle(
                    color: scope.ecosystem == entry.$1
                        ? colors.onPrimaryContainer
                        : colors.onSurface,
                  ),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  onSelected: (_) {
                    HapticFeedback.selectionClick();
                    onPick(SourceScope(ecosystem: entry.$1));
                  },
                ),
            ],
          ),
          if (hasRepos)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: TextButton.icon(
                key: const ValueKey('repository-picker'),
                onPressed: () => _open(
                  context,
                  ecosystems,
                  initial: SourceScope(ecosystem: ecosystem, repo: scope.repo),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: scope.repo == null
                      ? AppColors.textSecondary
                      : AppColors.textPrimary,
                  backgroundColor: scope.repo == null
                      ? AppColors.surface
                      : AppColors.primary.withValues(alpha: .08),
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  shape: const StadiumBorder(),
                ),
                icon: Icon(
                  scope.repo == null
                      ? Icons.folder_open_rounded
                      : Icons.check_rounded,
                  size: 16,
                ),
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        scope.repo == null
                            ? 'sources.repo_pick'.tr()
                            : repoLabel(scope.repo!),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.expand_more_rounded, size: 16),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _open(
    BuildContext context,
    List<SourceEcosystem> ecosystems, {
    SourceScope? initial,
  }) async {
    HapticFeedback.selectionClick();
    final picked = await showModalBottomSheet<SourceScope>(
      context: context,
      backgroundColor: AppColors.background,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _ScopeSheet(
        counts: counts,
        scope: initial ?? scope,
        ecosystems: ecosystems,
      ),
    );
    if (picked != null) onPick(picked);
  }
}

/// The sheet, as two levels rather than one long list.
///
/// It used to render every ecosystem AND every repository inside all of them at
/// once, flat, with an arrow glyph as the only sign that the indented rows
/// belonged to the one above. On a real install that is five ecosystems and a
/// dozen repositories in one scrolling column, where the thing being looked for
/// — usually just "CloudStream" — is four rows down among entries for
/// repositories holding a single source.
///
/// So it drills. The first level is the five ecosystems, which is the question
/// almost everybody is actually asking; an ecosystem that has more than one
/// repository offers a second level, and that level opens in place with a back
/// arrow. Every tap does exactly one thing.
class _ScopeSheet extends StatefulWidget {
  const _ScopeSheet({
    required this.counts,
    required this.scope,
    required this.ecosystems,
  });

  final SourceScopeCounts counts;
  final SourceScope scope;
  final List<SourceEcosystem> ecosystems;

  @override
  State<_ScopeSheet> createState() => _ScopeSheetState();
}

class _ScopeSheetState extends State<_ScopeSheet> {
  /// The ecosystem whose repositories are showing, or null for the top level.
  ///
  /// Opens on the one already chosen, so a sheet reopened to change a repo
  /// starts where the viewer left off instead of making them find it again.
  SourceEcosystem? _drilled;

  @override
  void initState() {
    super.initState();
    final e = widget.scope.ecosystem;
    if (e != null && widget.counts.reposIn(e).isNotEmpty) _drilled = e;
  }

  @override
  Widget build(BuildContext context) {
    final drilled = _drilled;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: PageTransitionSwitcher(
            reverse: drilled == null,
            child: drilled == null ? _top(context) : _repos(context, drilled),
          ),
        ),
      ),
    );
  }

  Widget _top(BuildContext context) => Column(
    key: const ValueKey('top'),
    mainAxisSize: MainAxisSize.min,
    children: [
      _title('sources.filter_title'.tr()),
      Flexible(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 12),
          children: [
            _row(
              label: 'sources.eco_all'.tr(),
              count: widget.counts.total,
              selected: widget.scope.isAll,
              onTap: () => Navigator.of(context).pop(SourceScope.all),
            ),
            for (final e in widget.ecosystems)
              _row(
                label: e.label,
                count: widget.counts.byEcosystem[e] ?? 0,
                selected: widget.scope.ecosystem == e,
                // The whole row picks the ecosystem. Narrowing further is the
                // chevron's job, so neither gesture has to be guessed at.
                onTap: () =>
                    Navigator.of(context).pop(SourceScope(ecosystem: e)),
                onDrill: widget.counts.reposIn(e).isEmpty
                    ? null
                    : () => setState(() => _drilled = e),
                drilledInto:
                    widget.scope.ecosystem == e && widget.scope.repo != null,
              ),
          ],
        ),
      ),
    ],
  );

  Widget _repos(BuildContext context, SourceEcosystem e) {
    final repos = widget.counts.reposIn(e);
    return Column(
      key: ValueKey('repos:${e.name}'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 20, 8),
          child: Row(
            children: [
              IconButton(
                onPressed: () => setState(() => _drilled = null),
                icon: const Icon(Icons.arrow_back_rounded, size: 20),
                color: AppColors.textSecondary,
                tooltip: 'general.back'.tr(),
              ),
              Expanded(
                child: Text(
                  e.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 12),
            children: [
              _row(
                label: 'sources.repo_any'.tr(),
                count: widget.counts.byEcosystem[e] ?? 0,
                selected:
                    widget.scope.ecosystem == e && widget.scope.repo == null,
                onTap: () =>
                    Navigator.of(context).pop(SourceScope(ecosystem: e)),
              ),
              for (final repo in repos)
                _row(
                  label: repoLabel(repo.key),
                  count: repo.value,
                  selected:
                      widget.scope.ecosystem == e &&
                      widget.scope.repo == repo.key,
                  onTap: () => Navigator.of(
                    context,
                  ).pop(SourceScope(ecosystem: e, repo: repo.key)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _title(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );

  Widget _row({
    required String label,
    required int count,
    required bool selected,
    required VoidCallback onTap,
    VoidCallback? onDrill,
    bool drilledInto = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
    child: Semantics(
      selected: selected,
      child: Material(
        color: selected
            ? AppColors.primary.withValues(alpha: .08)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            constraints: const BoxConstraints(minHeight: 48),
            padding: EdgeInsets.fromLTRB(12, 12, onDrill == null ? 12 : 4, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      // Weight, not colour — see the note on the pill above.
                      color: AppColors.textPrimary,
                      fontSize: 14.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '$count',
                  style: const TextStyle(
                    color: AppColors.textHint,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                SizedBox(
                  width: 26,
                  child: selected
                      ? Icon(
                          Icons.check_rounded,
                          size: 18,
                          color: AppColors.primary,
                        )
                      : null,
                ),
                if (onDrill != null)
                  IconButton(
                    onPressed: onDrill,
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: drilledInto
                          ? AppColors.primary
                          : AppColors.textHint,
                    ),
                    tooltip: 'sources.repo_pick'.tr(),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// A horizontal slide between the sheet's two levels.
///
/// Written here rather than pulled in: `animations` is not a dependency, and
/// what this needs is one axis and 220ms.
class PageTransitionSwitcher extends StatelessWidget {
  const PageTransitionSwitcher({
    super.key,
    required this.child,
    required this.reverse,
  });

  final Widget child;
  final bool reverse;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 220),
    switchInCurve: Curves.easeOutCubic,
    switchOutCurve: Curves.easeInCubic,
    layoutBuilder: (current, previous) => Stack(
      alignment: Alignment.topCenter,
      children: [...previous, ?current],
    ),
    transitionBuilder: (child, animation) => FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset(reverse ? -0.06 : 0.06, 0),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    ),
    child: child,
  );
}
