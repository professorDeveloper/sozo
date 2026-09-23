import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/home/domain/home_rail.dart';

/// Reorders and hides the bands on the home screen.
///
/// ## A draft, saved on Save
///
/// Every change edits a copy. The alternative — writing as you drag — means
/// closing the sheet with the back gesture leaves whatever half-arrangement
/// was on screen at that moment, and there is nothing to undo it with.
///
/// ## Compact editing rows
///
/// Each row has a visibility switch and a dedicated drag handle. Keeping the
/// list compact lets the complete home order fit without placeholder artwork.
Future<void> showHomeRailCustomizer(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const FractionallySizedBox(
      heightFactor: 0.9,
      child: _HomeRailCustomizerSheet(),
    ),
  );
}

class _HomeRailCustomizerSheet extends StatefulWidget {
  const _HomeRailCustomizerSheet();

  @override
  State<_HomeRailCustomizerSheet> createState() =>
      _HomeRailCustomizerSheetState();
}

class _HomeRailCustomizerSheetState extends State<_HomeRailCustomizerSheet> {
  late List<HomeRail> _order = sanitizeRailOrder(
    getIt<HiveService>().getHomeRailOrder(),
  );
  late Set<String> _hidden = {...getIt<HiveService>().getHomeRailHidden()};

  /// The catalogue cannot be hidden.
  ///
  /// It is the app: hiding it leaves a home screen of chrome around nothing,
  /// and somebody who did it by accident has no reason to look in a customizer
  /// for the way back.
  bool _canHide(HomeRail rail) => rail != HomeRail.catalogue;

  void _toggle(HomeRail rail) {
    if (!_canHide(rail)) return;
    setState(() {
      if (!_hidden.remove(rail.id)) _hidden.add(rail.id);
    });
  }

  /// `onReorderItem` rather than `onReorder`: the newer callback hands back an
  /// index already corrected for the removed row, which is the off-by-one every
  /// hand-written reorder gets wrong in one direction only.
  void _reorder(int from, int to) {
    setState(() => _order.insert(to, _order.removeAt(from)));
  }

  Future<void> _save() async {
    await getIt<HiveService>().saveHomeRails([
      for (final r in _order) r.id,
    ], _hidden);
    if (mounted) Navigator.of(context).pop();
  }

  void _reset() => setState(() {
    _order = List.of(HomeRail.defaults);
    _hidden = {...HomeRail.optIn};
  });

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    return SafeArea(
      top: false,
      child: Column(
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
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'home_rails.title'.tr(),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _reset,
                  child: Text(
                    'nav_customize.reset'.tr(),
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              'home_rails.hint'.tr(),
              style: const TextStyle(
                color: AppColors.textHint,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              buildDefaultDragHandles: false,
              itemCount: _order.length,
              onReorderItem: _reorder,
              proxyDecorator: (child, _, animation) => Material(
                color: Colors.transparent,
                child: Transform.scale(scale: 1.02, child: child),
              ),
              itemBuilder: (context, i) {
                final rail = _order[i];
                return _RailPreviewTile(
                  key: ValueKey(rail.id),
                  rail: rail,
                  index: i,
                  hidden: _hidden.contains(rail.id),
                  canHide: _canHide(rail),
                  onToggle: () => _toggle(rail),
                );
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, bottomPad + 12),
            child: Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('nav_customize.cancel'.tr()),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text('nav_customize.save'.tr()),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One band, drawn roughly as it appears on Home.
class _RailPreviewTile extends StatelessWidget {
  const _RailPreviewTile({
    super.key,
    required this.rail,
    required this.index,
    required this.hidden,
    required this.canHide,
    required this.onToggle,
  });

  final HomeRail rail;
  final int index;
  final bool hidden;
  final bool canHide;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Opacity(
        // Keep the control legible even when the rail is hidden.
        opacity: 1,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.divider),
          ),
          padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(rail.icon, size: 17, color: AppColors.textSecondary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      rail.labelKey.tr(),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (canHide)
                    Switch(
                      value: !hidden,
                      onChanged: (_) => onToggle(),
                      thumbColor: const WidgetStatePropertyAll(Colors.white),
                      trackColor: WidgetStateProperty.resolveWith(
                        (states) => states.contains(WidgetState.selected)
                            ? AppColors.primary
                            : AppColors.surfaceVariant,
                      ),
                      trackOutlineColor: WidgetStateProperty.resolveWith(
                        (states) => states.contains(WidgetState.selected)
                            ? Colors.transparent
                            : AppColors.textHint,
                      ),
                      thumbIcon: WidgetStateProperty.resolveWith(
                        (states) => Icon(
                          states.contains(WidgetState.selected)
                              ? Icons.check_rounded
                              : Icons.remove_rounded,
                          color: states.contains(WidgetState.selected)
                              ? AppColors.primary
                              : AppColors.surfaceVariant,
                          size: 14,
                        ),
                      ),
                    )
                  else
                    // Locked rather than absent: an eye that is simply missing
                    // reads as a rendering bug, where a struck-through one
                    // says this cannot be turned off.
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Icon(
                        Icons.lock_outline_rounded,
                        size: 17,
                        color: AppColors.textHint,
                      ),
                    ),
                  ReorderableDragStartListener(
                    index: index,
                    child: const SizedBox(
                      width: 44,
                      height: 48,
                      child: Icon(
                        Icons.drag_handle_rounded,
                        color: AppColors.textHint,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
