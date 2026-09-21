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
                    // Filtered is a state worth seeing at a glance, but it is
                    // not an alarm: a tinted card and a slightly stronger edge
                    // say it without turning the control into the brightest
                    // thing on the screen.
                    color: active
                        ? AppColors.primary.withValues(alpha: 0.12)
                        : AppColors.card,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: active
                          ? AppColors.primary.withValues(alpha: 0.35)
                          : Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _label(),
                        style: TextStyle(
                          color: AppColors.textPrimary,
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
                          color: AppColors.textHint,
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
  }) => InkWell(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      // A held row rather than coloured text: it marks the selection without
      // competing with every other row for attention.
      color: selected
          ? AppColors.primary.withValues(alpha: 0.08)
          : Colors.transparent,
      padding: EdgeInsets.fromLTRB(20, 13, onDrill == null ? 20 : 6, 13),
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
                ? Icon(Icons.check_rounded, size: 18, color: AppColors.primary)
                : null,
          ),
          if (onDrill != null)
            IconButton(
              onPressed: onDrill,
              visualDensity: VisualDensity.compact,
              icon: Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: drilledInto ? AppColors.primary : AppColors.textHint,
              ),
              tooltip: 'sources.repo_pick'.tr(),
            ),
        ],
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
