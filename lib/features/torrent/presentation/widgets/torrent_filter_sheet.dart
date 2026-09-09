import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/torrent/data/indexers/torrent_indexer.dart';
import 'package:soplay/features/torrent/data/torrent_search_repository.dart';

/// Quality and tracker filters.
///
/// Everything here is applied *after* the trackers answer, because no anime
/// indexer can filter on any of it — resolution, codec and subtitle style are
/// not fields any of them store, they only exist inside the release name. The
/// tracker narrows by category and text; this narrows the rest.
class TorrentFilterSheet extends StatefulWidget {
  const TorrentFilterSheet({
    super.key,
    required this.filters,
    required this.indexers,
    required this.enabledIndexers,
  });

  final TorrentFilters filters;
  final List<TorrentIndexer> indexers;
  final Set<String> enabledIndexers;

  static Future<({TorrentFilters filters, Set<String> indexers})?> show(
    BuildContext context, {
    required TorrentFilters filters,
    required List<TorrentIndexer> indexers,
    required Set<String> enabledIndexers,
  }) {
    return showModalBottomSheet<({TorrentFilters filters, Set<String> indexers})>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => TorrentFilterSheet(
        filters: filters,
        indexers: indexers,
        enabledIndexers: enabledIndexers,
      ),
    );
  }

  @override
  State<TorrentFilterSheet> createState() => _TorrentFilterSheetState();
}

class _TorrentFilterSheetState extends State<TorrentFilterSheet> {
  late TorrentFilters _filters = widget.filters;
  late Set<String> _enabled = {...widget.enabledIndexers};

  /// Offered as a floor, not an exact match: users think "at least 1080p".
  static const _resolutions = <int?>[null, 720, 1080, 2160];

  void _update(TorrentFilters next) => setState(() => _filters = next);

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _header(),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.fromLTRB(
                20,
                4,
                20,
                MediaQuery.of(context).padding.bottom + 20,
              ),
              children: [
                _label('torrent.quality'.tr()),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final height in _resolutions)
                      ChoiceChip(
                        label: Text(height == null
                            ? 'torrent.any_quality'.tr()
                            : '${height}p+'),
                        selected: _filters.minResolution == height,
                        onSelected: (_) => _update(_copy(minResolution: height)),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                _label('torrent.min_seeders'.tr()),
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: _filters.minSeeders.toDouble().clamp(0, 50),
                        max: 50,
                        divisions: 50,
                        label: '${_filters.minSeeders}',
                        onChanged: (value) =>
                            _update(_copy(minSeeders: value.round())),
                      ),
                    ),
                    SizedBox(
                      width: 34,
                      child: Text(
                        '${_filters.minSeeders}',
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                _switch(
                  'torrent.trusted_only'.tr(),
                  _filters.trustedOnly,
                  (v) => _update(_copy(trustedOnly: v)),
                ),
                _switch(
                  'torrent.exclude_mini'.tr(),
                  _filters.excludeMiniEncodes,
                  (v) => _update(_copy(excludeMiniEncodes: v)),
                ),
                _switch(
                  'torrent.exclude_hardsubs'.tr(),
                  _filters.excludeHardsubs,
                  (v) => _update(_copy(excludeHardsubs: v)),
                ),
                _switch(
                  'torrent.exclude_remakes'.tr(),
                  _filters.excludeRemakes,
                  (v) => _update(_copy(excludeRemakes: v)),
                ),
                _switch(
                  'torrent.require_dual_audio'.tr(),
                  _filters.requireDualAudio,
                  (v) => _update(_copy(requireDualAudio: v)),
                ),
                _switch(
                  'torrent.exclude_batches'.tr(),
                  _filters.excludeBatches,
                  (v) => _update(_copy(excludeBatches: v)),
                ),
                const SizedBox(height: 18),
                _label('torrent.trackers'.tr()),
                for (final indexer in widget.indexers)
                  if (!indexer.isNsfw)
                    _switch(
                      indexer.name,
                      _enabled.contains(indexer.id),
                      (on) => setState(() {
                        if (on) {
                          _enabled.add(indexer.id);
                        } else if (_enabled.length > 1) {
                          // Never let the last tracker be switched off — an
                          // empty selection silently returns no results and
                          // reads as the feature being broken.
                          _enabled.remove(indexer.id);
                        }
                      }),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() => Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 4, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'torrent.filters'.tr(),
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton(
              onPressed: () => setState(() {
                _filters = const TorrentFilters();
                _enabled = widget.indexers
                    .where((i) => !i.isNsfw)
                    .map((i) => i.id)
                    .toSet();
              }),
              child: Text('torrent.reset_filters'.tr()),
            ),
            const SizedBox(width: 4),
            FilledButton(
              onPressed: () => Navigator.of(context)
                  .pop((filters: _filters, indexers: _enabled)),
              child: Text('search.apply'.tr()),
            ),
          ],
        ),
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(
          text,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
      );

  Widget _switch(String label, bool value, ValueChanged<bool> onChanged) =>
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        value: value,
        onChanged: onChanged,
        title: Text(
          label,
          style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
        ),
      );

  /// Sentinel for "argument not supplied".
  ///
  /// [TorrentFilters.minResolution] is nullable and null is *meaningful* there
  /// — it is what "any quality" means. So the usual `value ?? _filters.value`
  /// idiom cannot work: it would be unable to tell "leave the resolution
  /// alone" from "clear the resolution", and every unrelated edit (moving the
  /// seeder slider, flipping a switch) would silently reset it to Any.
  static const Object _unset = Object();

  /// [TorrentFilters] is immutable and has no `copyWith` of its own.
  TorrentFilters _copy({
    int? minSeeders,
    Object? minResolution = _unset,
    bool? excludeHardsubs,
    bool? excludeMiniEncodes,
    bool? trustedOnly,
    bool? excludeRemakes,
    bool? requireDualAudio,
    bool? excludeBatches,
  }) =>
      TorrentFilters(
        minSeeders: minSeeders ?? _filters.minSeeders,
        minResolution: identical(minResolution, _unset)
            ? _filters.minResolution
            : minResolution as int?,
        maxResolution: _filters.maxResolution,
        excludeHardsubs: excludeHardsubs ?? _filters.excludeHardsubs,
        excludeMiniEncodes: excludeMiniEncodes ?? _filters.excludeMiniEncodes,
        trustedOnly: trustedOnly ?? _filters.trustedOnly,
        excludeRemakes: excludeRemakes ?? _filters.excludeRemakes,
        requireDualAudio: requireDualAudio ?? _filters.requireDualAudio,
        excludeBatches: excludeBatches ?? _filters.excludeBatches,
        groups: _filters.groups,
      );
}
