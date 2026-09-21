import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/watch_services/domain/entities/watch_region_entity.dart';
import 'package:soplay/features/watch_services/domain/watch_region.dart';

/// Which country's line-ups are showing, and a way to change it.
///
/// Shaped after `SourceScopeMenu` on purpose: one pill that states the current
/// choice with its count, opening a searchable sheet of rows. Two controls that
/// answer "which slice of this am I looking at" should not be two different
/// gestures.
///
/// There is no "Clear" here, unlike that one. A region is always set — there is
/// no all-countries state to clear to — and the equivalent affordance is the
/// "use my device region" row at the top of the sheet.
class WatchRegionMenu extends StatelessWidget {
  const WatchRegionMenu({
    super.key,
    required this.region,
    required this.regionName,
    required this.serviceCount,
    required this.onOpen,
    required this.onPick,
    this.regions = const [],
    this.loadingRegions = false,
    this.deviceRegion = '',
    this.dense = false,
  });

  final String region;
  final String regionName;

  /// How many services this country has, right now.
  ///
  /// On the button rather than beside each row in the sheet, and that is a
  /// TMDB constraint rather than a preference: the regions endpoint returns
  /// names only, so a count per country would mean ninety-odd extra requests to
  /// fill one sheet. The button answers the question that actually gets asked,
  /// from data already on screen.
  final int serviceCount;

  /// Fetches the country list. Called when the sheet is about to open, because
  /// until then nothing has needed it.
  final VoidCallback onOpen;

  final ValueChanged<String> onPick;
  final List<WatchRegionEntity> regions;
  final bool loadingRegions;

  /// The country the device says it is in, offered as a shortcut when it is not
  /// the one being shown.
  final String deviceRegion;

  final bool dense;

  @override
  Widget build(BuildContext context) {
    final flag = regionFlag(region);
    // Regional-indicator pairs render as two letterboxed letters on Windows
    // rather than a flag, so the name carries it there.
    final showFlag = flag.isNotEmpty && !isDesktopPlatform;
    // Worth flagging, quietly: the shelf is a claim about a country, and one
    // that is not the viewer's own is the state most likely to confuse.
    final elsewhere = deviceRegion.isNotEmpty && deviceRegion != region;

    return Padding(
      padding: EdgeInsets.fromLTRB(12, dense ? 2 : 4, 12, dense ? 2 : 6),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: '$regionName, $serviceCount',
            child: ExcludeSemantics(
              child: InkWell(
                onTap: () => _open(context),
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
                    color: elsewhere
                        ? AppColors.primary.withValues(alpha: 0.12)
                        : AppColors.card,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: elsewhere
                          ? AppColors.primary.withValues(alpha: 0.35)
                          : Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (showFlag) ...[
                        Text(flag, style: const TextStyle(fontSize: 15)),
                        const SizedBox(width: 7),
                      ],
                      Text(
                        regionName,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: dense ? 12.5 : 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        '$serviceCount',
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
                        color: elsewhere
                            ? AppColors.primary
                            : AppColors.textHint,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    HapticFeedback.selectionClick();
    onOpen();
    // `showAdaptiveModal`, never a raw bottom sheet: it is what turns this into
    // a centred dialog on TV and moves the remote's focus into it. A raw sheet
    // appears and leaves focus on the control behind it.
    final picked = await showAdaptiveModal<String>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _RegionSheet(
        regions: regions,
        selected: region,
        deviceRegion: deviceRegion,
        loading: loadingRegions,
      ),
    );
    if (picked != null && picked != region) onPick(picked);
  }
}

class _RegionSheet extends StatefulWidget {
  const _RegionSheet({
    required this.regions,
    required this.selected,
    required this.deviceRegion,
    required this.loading,
  });

  final List<WatchRegionEntity> regions;
  final String selected;
  final String deviceRegion;
  final bool loading;

  @override
  State<_RegionSheet> createState() => _RegionSheetState();
}

class _RegionSheetState extends State<_RegionSheet> {
  String _query = '';

  List<WatchRegionEntity> get _shown {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.regions;
    return [
      for (final r in widget.regions)
        if (r.name.toLowerCase().contains(q) ||
            r.code.toLowerCase().contains(q) ||
            r.nativeName.toLowerCase().contains(q))
          r,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final rows = _shown;
    final offerDevice =
        widget.deviceRegion.isNotEmpty &&
        widget.deviceRegion != widget.selected &&
        widget.regions.any((r) => r.code == widget.deviceRegion) &&
        _query.isEmpty;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  'watch.region_sheet_title'.tr(),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            // Ninety-odd rows is past the point where scrolling is a search.
            if (widget.regions.length > 12)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'watch.region_search_hint'.tr(),
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  ),
                ),
              ),
            if (widget.loading && widget.regions.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: CircularProgressIndicator(),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 12),
                  children: [
                    if (offerDevice)
                      _row(
                        context,
                        code: widget.deviceRegion,
                        label: 'watch.region_detect'.tr(),
                        selected: false,
                        accent: true,
                      ),
                    for (final r in rows)
                      _row(
                        context,
                        code: r.code,
                        label: r.name,
                        selected: r.code == widget.selected,
                      ),
                    if (rows.isEmpty && !widget.loading)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            'watch.no_region_match'.tr(),
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context, {
    required String code,
    required String label,
    required bool selected,
    bool accent = false,
  }) {
    final flag = regionFlag(code);
    return InkWell(
      // The selected row takes focus, so a remote lands on the current value
      // rather than on Andorra.
      autofocus: selected,
      onTap: () => Navigator.of(context).pop(code),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        color: selected
            ? AppColors.primary.withValues(alpha: 0.08)
            : Colors.transparent,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Row(
          children: [
            if (accent)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: Icon(
                  Icons.my_location_rounded,
                  size: 15,
                  color: AppColors.primary,
                ),
              )
            else if (flag.isNotEmpty && !isDesktopPlatform) ...[
              Text(flag, style: const TextStyle(fontSize: 15)),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  // Weight carries the selection; the accent is spent on the
                  // one row that is an ACTION rather than a value.
                  color: accent ? AppColors.primary : AppColors.textPrimary,
                  fontSize: 14.5,
                  fontWeight: selected || accent
                      ? FontWeight.w700
                      : FontWeight.w500,
                ),
              ),
            ),
            SizedBox(
              width: 28,
              child: selected
                  ? Icon(
                      Icons.check_rounded,
                      size: 18,
                      color: AppColors.primary,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
