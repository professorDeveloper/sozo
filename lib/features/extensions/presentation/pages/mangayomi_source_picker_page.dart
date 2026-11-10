import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/extensions/data/mangayomi_repo_store.dart';
import 'package:soplay/features/extensions/domain/entities/mangayomi_source.dart';
import 'package:soplay/features/extensions/domain/mangayomi_source_filter.dart';
import 'package:soplay/features/extensions/presentation/widgets/source_filter_chips.dart';

/// Lets the user pick which sources of one or more fetched indexes to install.
///
/// Pops with the chosen ids keyed by index url, or null when cancelled.
class MangayomiSourcePickerPage extends StatefulWidget {
  const MangayomiSourcePickerPage({
    super.key,
    required this.indexes,
    required this.installedIds,
    this.initialLanguages = const [],
    this.includeNsfw = false,
  });

  final List<MangayomiRepoIndex> indexes;
  final Set<String> installedIds;
  final List<String> initialLanguages;
  final bool includeNsfw;

  static Future<Map<String, Set<String>>?> show(
    BuildContext context, {
    required List<MangayomiRepoIndex> indexes,
    required Set<String> installedIds,
    List<String> initialLanguages = const [],
    bool includeNsfw = false,
  }) => Navigator.of(context).push<Map<String, Set<String>>>(
    MaterialPageRoute(
      builder: (_) => MangayomiSourcePickerPage(
        indexes: indexes,
        installedIds: installedIds,
        initialLanguages: initialLanguages,
        includeNsfw: includeNsfw,
      ),
    ),
  );

  @override
  State<MangayomiSourcePickerPage> createState() =>
      _MangayomiSourcePickerPageState();
}

class _MangayomiSourcePickerPageState extends State<MangayomiSourcePickerPage> {
  static const Color _accent = Color(0xFFE5484D);

  final _search = TextEditingController();
  final _chosen = <String>{};
  String _query = '';
  MangayomiItemType? _type;
  late List<String> _languages = widget.initialLanguages;

  late final List<MangayomiSource> _all = [
    for (final index in widget.indexes)
      ...index.sources.where((s) => widget.includeNsfw || !s.isNsfw),
  ];

  static String _key(MangayomiSource s) => '${s.repoUrl}\u0000${s.id}';

  bool _installed(MangayomiSource s) => widget.installedIds.contains(s.id);

  MangayomiSourceFilter get _filter => MangayomiSourceFilter(
    query: _query,
    type: _type,
    languages: _languages,
    includeNsfw: widget.includeNsfw,
  );

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _setAll(List<MangayomiSource> visible, bool selected) {
    setState(() {
      final keys = visible.where((s) => !_installed(s)).map(_key);
      if (selected) {
        _chosen.addAll(keys);
      } else {
        _chosen.removeAll(keys);
      }
    });
  }

  void _submit() {
    final out = <String, Set<String>>{};
    for (final s in _all) {
      if (!_chosen.contains(_key(s))) continue;
      out.putIfAbsent(s.repoUrl, () => <String>{}).add(s.id);
    }
    Navigator.of(context).pop(out);
  }

  @override
  Widget build(BuildContext context) {
    final visible = _filter.apply(_all);
    final langScope = MangayomiSourceFilter(
      type: _type,
      includeNsfw: widget.includeNsfw,
    ).apply(_all);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        title: Text('ext.choose_sources'.tr()),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v),
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'general.search'.tr(),
                hintStyle: const TextStyle(color: AppColors.textHint),
                prefixIcon: const Icon(Icons.search, color: AppColors.textHint),
                isDense: true,
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          MangayomiTypeFilterRow(
            selected: _type,
            onSelected: (t) => setState(() => _type = t),
          ),
          MangayomiLanguageFilterRow(
            counts: MangayomiSourceFilter.languageCounts(langScope),
            selected: _languages,
            onToggle: (code) => setState(
              () => _languages = MangayomiSourceFilter.toggleLanguage(
                _languages,
                code,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Flexible(
                  child: TextButton(
                    onPressed: () => _setAll(visible, true),
                    child: Text(
                      'ext.select_all'.tr(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                Flexible(
                  child: TextButton(
                    onPressed: () => _setAll(visible, false),
                    child: Text(
                      'ext.select_none'.tr(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: Text(
                    '${visible.length}',
                    style: const TextStyle(color: AppColors.textHint),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: visible.isEmpty
                ? Center(
                    child: Text(
                      'ext.no_matches'.tr(),
                      style: const TextStyle(color: AppColors.textHint),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                    itemCount: visible.length,
                    itemBuilder: (_, i) => _tile(visible[i]),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            height: 46,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
              ),
              onPressed: _chosen.isEmpty ? null : _submit,
              icon: const Icon(Icons.download_rounded),
              label: Text(
                'ext.install_selected'.tr(args: ['${_chosen.length}']),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tile(MangayomiSource s) {
    final installed = _installed(s);
    final type = switch (s.itemType) {
      MangayomiItemType.anime => 'ext.type_anime'.tr(),
      MangayomiItemType.novel => 'ext.type_novel'.tr(),
      MangayomiItemType.manga => 'ext.type_manga'.tr(),
    };
    return CheckboxListTile(
      value: installed || _chosen.contains(_key(s)),
      onChanged: installed
          ? null
          : (v) => setState(() {
              if (v == true) {
                _chosen.add(_key(s));
              } else {
                _chosen.remove(_key(s));
              }
            }),
      activeColor: _accent,
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(
        s.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white, fontSize: 13.5),
      ),
      subtitle: Text(
        [
          s.lang.toUpperCase(),
          type,
          'v${s.version}',
          if (s.isNsfw) '18+',
          if (installed) 'ext.already_installed'.tr(),
        ].join(' · '),
        style: const TextStyle(color: AppColors.textHint, fontSize: 11),
      ),
    );
  }
}
