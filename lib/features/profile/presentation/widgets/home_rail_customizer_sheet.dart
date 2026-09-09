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
/// ## A preview, not a list of names
///
/// The rows are shaped like the bands they stand for: a wide block for the
/// hero, a row of cards for a rail, chips for the genres. "Continue Watching"
/// and "Genres" as two identical list rows tell you their order and nothing
/// about what you are ordering — and the whole question here is what the screen
/// will look like.
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
  late List<HomeRail> _order =
      sanitizeRailOrder(getIt<HiveService>().getHomeRailOrder());
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
    await getIt<HiveService>().saveHomeRails(
      [for (final r in _order) r.id],
      _hidden,
    );
    if (mounted) Navigator.of(context).pop();
  }

  void _reset() => setState(() {
        _order = List.of(HomeRail.defaults);
        _hidden = {};
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
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _save,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text('nav_customize.save'.tr()),
              ),
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
        // Dimmed rather than removed: a hidden band keeps its place in the
        // order, so switching it back on puts it where it was instead of at
        // the end.
        opacity: hidden ? 0.42 : 1,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.divider),
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 14),
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
                    IconButton(
                      onPressed: onToggle,
                      tooltip: hidden
                          ? 'general.on'.tr()
                          : 'general.off'.tr(),
                      icon: Icon(
                        hidden
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 19,
                        color: hidden
                            ? AppColors.textHint
                            : AppColors.textSecondary,
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
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(
                        Icons.drag_handle_rounded,
                        color: AppColors.textHint,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 6),
                child: _RailShape(rail: rail),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The silhouette of a band — what it is, not what it is called.
class _RailShape extends StatelessWidget {
  const _RailShape({required this.rail});

  final HomeRail rail;

  static const Color _fill = Color(0x14FFFFFF);

  Widget _block({double? width, double height = 26, double radius = 6}) =>
      Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: _fill,
          borderRadius: BorderRadius.circular(radius),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return switch (rail) {
      // One wide banner.
      HomeRail.hero => _block(height: 54, radius: 10),

      // Wide cards with a progress line, which is what makes Continue
      // Watching recognisable at a glance.
      HomeRail.resume => SizedBox(
          height: 44,
          child: Row(
            children: [
              for (var i = 0; i < 3; i++) ...[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _block(height: 34, radius: 6),
                      const SizedBox(height: 4),
                      Container(
                        height: 3,
                        width: 34.0 - i * 8,
                        color: AppColors.primary.withValues(alpha: 0.7),
                      ),
                    ],
                  ),
                ),
                if (i < 2) const SizedBox(width: 8),
              ],
            ],
          ),
        ),

      // Short pills.
      HomeRail.genres => SizedBox(
          height: 22,
          child: Row(
            children: [
              for (final w in const [58.0, 44.0, 66.0, 38.0]) ...[
                _block(width: w, height: 22, radius: 11),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),

      // Squares — channel logos are square where posters are tall.
      HomeRail.liveTv => SizedBox(
          height: 38,
          child: Row(
            children: [
              for (var i = 0; i < 5; i++) ...[
                _block(width: 38, height: 38, radius: 8),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),

      // Tall posters, twice — the catalogue is several rails, not one.
      HomeRail.catalogue => Column(
          children: [
            for (var row = 0; row < 2; row++) ...[
              SizedBox(
                height: 40,
                child: Row(
                  children: [
                    for (var i = 0; i < 5; i++) ...[
                      _block(width: 28, height: 40, radius: 5),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
              if (row == 0) const SizedBox(height: 8),
            ],
          ],
        ),
    };
  }
}
