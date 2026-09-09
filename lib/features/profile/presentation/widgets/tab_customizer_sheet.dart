import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/navigation/app_tab.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/system/nav_prefs.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/theme/app_theme.dart';

/// Bottom-bar customizer (Settings → Appearance). Ports satashkent's
/// quick-nav customizer to soplay tokens: a draft copy edited freely, persisted
/// only on Save; reorder by drag; 4–6 tabs; mandatory tabs locked.
Future<void> showTabCustomizer(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const FractionallySizedBox(
      heightFactor: 0.9,
      child: _TabCustomizerSheet(),
    ),
  );
}

class _TabCustomizerSheet extends StatefulWidget {
  const _TabCustomizerSheet();
  @override
  State<_TabCustomizerSheet> createState() => _TabCustomizerSheetState();
}

class _TabCustomizerSheetState extends State<_TabCustomizerSheet> {
  // Draft copy — nothing is persisted until Save.
  late List<TabId> _draft = sanitizeTabOrder(getIt<HiveService>().tabOrder);

  List<AppTabDef> get _available => [
    for (final e in kTabRegistry.entries)
      if (!_draft.contains(e.key)) e.value,
  ];

  bool get _atMax => _draft.length >= kMaxTabs;
  bool get _atMin => _draft.length <= kMinTabs;
  bool get _valid => _draft.length >= kMinTabs && _draft.length <= kMaxTabs;

  void _snack(String key, {Map<String, String>? args}) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(key.tr(namedArgs: args)),
          backgroundColor: AppColors.card,
        ),
      );

  void _pin(TabId id) {
    if (_atMax) {
      return _snack('nav_customize.max_hint', args: {'count': '$kMaxTabs'});
    }
    setState(() => _draft.add(id));
  }

  void _unpin(TabId id) {
    if (kTabRegistry[id]!.mandatory) return; // locked
    if (_atMin) {
      return _snack('nav_customize.min_hint', args: {'count': '$kMinTabs'});
    }
    setState(() => _draft.remove(id));
  }

  void _reorder(int oldI, int newI) =>
      setState(() => _draft.insert(newI, _draft.removeAt(oldI)));

  Future<void> _save() async {
    if (!_valid) {
      return _snack(
        'nav_customize.pick_range',
        args: {'min': '$kMinTabs', 'max': '$kMaxTabs'},
      );
    }
    final encoded = encodeTabOrder(sanitizeTabOrder(encodeTabOrder(_draft)));
    await getIt<HiveService>().setTabOrder(encoded);
    NavPrefs.tabOrder.value = encoded; // shell listener rebuilds the bar live
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 10),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.border,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
          child: Row(
            children: [
              Text(
                'nav_customize.title'.tr(),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                '${_draft.length}/$kMaxTabs',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        // The bar itself, as it will look. A list of names says what the order
        // is; it does not say whether six tabs still fit, whether two icons
        // next to each other are tellable apart, or what the thing you are
        // editing actually looks like — which is the only question anybody
        // opens this sheet with.
        _NavBarPreview(tabs: _draft),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            children: [
              _label('nav_customize.shown'.tr()),
              ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                onReorderItem: _reorder,
                proxyDecorator: (child, i, anim) =>
                    Material(color: Colors.transparent, child: child),
                children: [
                  for (var i = 0; i < _draft.length; i++)
                    // Long-press anywhere on the row picks it up, as well as
                    // the handle. The handle alone is a small target that has
                    // to be found first, and on a list whose whole purpose is
                    // reordering, the row IS the thing you want to grab.
                    ReorderableDelayedDragStartListener(
                      key: ValueKey(_draft[i].name),
                      index: i,
                      child: _PinnedTile(
                        def: kTabRegistry[_draft[i]]!,
                        index: i,
                        onRemove: () => _unpin(_draft[i]),
                      ),
                    ),
                ],
              ),
              if (_available.isNotEmpty) ...[
                const SizedBox(height: 8),
                _label('nav_customize.available'.tr()),
                for (final d in _available)
                  _AvailableTile(
                    def: d,
                    disabled: _atMax,
                    onAdd: () => _pin(d.id),
                  ),
              ],
            ],
          ),
        ),
        _Footer(
          onReset: () => setState(() => _draft = List.of(kDefaultTabs)),
          onCancel: () => Navigator.pop(context),
          onSave: _save,
        ),
      ],
    );
  }

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
    child: Text(
      t.toUpperCase(),
      style: const TextStyle(
        color: AppColors.textHint,
        fontSize: 11.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
      ),
    ),
  );
}

/// A live drawing of the bottom bar the draft would produce.
///
/// Deliberately the real icons and the real labels at the real size, so the
/// crowding at six tabs is visible here rather than discovered after saving.
/// The first tab is drawn selected because a bar with nothing active does not
/// look like this app's bar, and the accent is what makes it recognisable.
class _NavBarPreview extends StatelessWidget {
  const _NavBarPreview({required this.tabs});

  final List<TabId> tabs;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
        // Laid out by position rather than by a Row, so a tab that moves
        // SLIDES to its new place. A Row rebuilt in a new order snaps, and at
        // this size a snap is indistinguishable from the bar being replaced —
        // which is the difference between following the change and losing
        // track of what moved where.
        child: SizedBox(
          height: 46,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final slot = tabs.isEmpty ? 0.0 : constraints.maxWidth / tabs.length;
              return Stack(
                children: [
                  for (var i = 0; i < tabs.length; i++)
                    AnimatedPositioned(
                      // Keyed on the tab, not the slot, so Flutter animates the
                      // same widget to a new place instead of fading one out
                      // and another in.
                      key: ValueKey(tabs[i].name),
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                      left: i * slot,
                      top: 0,
                      width: slot,
                      child: _PreviewTab(
                        def: kTabRegistry[tabs[i]]!,
                        active: i == 0,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PreviewTab extends StatelessWidget {
  const _PreviewTab({required this.def, required this.active});

  final AppTabDef def;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.primary : AppColors.textHint;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Eased, because the tab that becomes first changes colour at the
          // same moment every tab is sliding — a hard colour swap in the middle
          // of that motion reads as a flicker.
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Icon(
              active ? def.activeIcon : def.icon,
              key: ValueKey(active),
              size: 21,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(
              color: color,
              fontSize: 9.5,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
            child: Text(
            def.labelKey.tr(),
            maxLines: 1,
            // Ellipsis rather than shrinking: a label that gets smaller as
            // tabs are added hides the crowding this preview exists to show.
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _PinnedTile extends StatelessWidget {
  const _PinnedTile({
    required this.def,
    required this.index,
    required this.onRemove,
  });
  final AppTabDef def;
  final int index;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(def.activeIcon, color: AppColors.primary, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              def.labelKey.tr(),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // Same 40px box the remove button occupies, so the drag handles stay in
          // one column whether or not a tab is locked.
          if (def.mandatory)
            const SizedBox(
              width: 40,
              height: 40,
              child: Icon(
                Icons.lock_rounded,
                color: AppColors.textHint,
                size: 18,
              ),
            )
          else
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(
                Icons.remove_circle_rounded,
                color: AppColors.error,
                size: 22,
              ),
              onPressed: onRemove,
            ),
          ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsetsDirectional.only(start: 4),
              child: Icon(
                Icons.drag_handle_rounded,
                color: AppColors.textHint,
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AvailableTile extends StatelessWidget {
  const _AvailableTile({
    required this.def,
    required this.disabled,
    required this.onAdd,
  });
  final AppTabDef def;
  final bool disabled;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: disabled ? 0.4 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.textSecondary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(def.icon, color: AppColors.textSecondary, size: 19),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                def.labelKey.tr(),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                ),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(
                Icons.add_circle_rounded,
                color: disabled ? AppColors.textHint : AppColors.primary,
                size: 24,
              ),
              onPressed: disabled ? null : onAdd,
            ),
          ],
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.onReset,
    required this.onCancel,
    required this.onSave,
  });
  final VoidCallback onReset;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        MediaQuery.paddingOf(context).bottom + 12,
      ),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.divider, width: 1)),
      ),
      child: Row(
        children: [
          TextButton(
            onPressed: onReset,
            child: Text(
              'nav_customize.reset'.tr(),
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: onCancel,
            child: Text(
              'nav_customize.cancel'.tr(),
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: onSave,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(kButtonRadius),
              ),
            ),
            child: Text('nav_customize.save'.tr()),
          ),
        ],
      ),
    );
  }
}
