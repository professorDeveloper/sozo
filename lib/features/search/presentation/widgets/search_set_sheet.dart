import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/profile/domain/entities/provider_entity.dart';
import 'package:soplay/features/search/domain/entities/cross_search_scope.dart';

/// The full source list, for narrowing when the chip rail on the page is not
/// enough — a couple of hundred providers need a filter box.
///
/// Returns a [CrossSearchScope] via `Navigator.pop`, or `null` if dismissed.
/// Selecting nothing is not "search nothing": it resolves back to every source,
/// which is the default this feature is supposed to have.
class SearchSetSheet extends StatefulWidget {
  const SearchSetSheet({
    super.key,
    required this.providers,
    required this.scope,
  });

  final List<ProviderEntity> providers;
  final CrossSearchScope scope;

  static Future<CrossSearchScope?> show(
    BuildContext context, {
    required List<ProviderEntity> providers,
    required CrossSearchScope scope,
  }) {
    return showModalBottomSheet<CrossSearchScope>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => SearchSetSheet(providers: providers, scope: scope),
    );
  }

  @override
  State<SearchSetSheet> createState() => _SearchSetSheetState();
}

class _SearchSetSheetState extends State<SearchSetSheet> {
  late final Set<String> _selected = {
    if (!widget.scope.isAll) ...widget.scope.ids!,
  };
  String _query = '';

  bool get _isAll => _selected.isEmpty || _selected.length == widget.providers.length;

  CrossSearchScope get _result =>
      _isAll ? const CrossSearchScope.all() : CrossSearchScope.only(_selected);

  static const int _softCap = 15;

  List<ProviderEntity> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.providers;
    return widget.providers
        .where((p) =>
            p.name.toLowerCase().contains(q) || p.id.toLowerCase().contains(q))
        .toList();
  }

  String _tag(ProviderEntity p) {
    if (p.id.startsWith('cs:')) return 'CS';
    if (p.id.startsWith('an:')) return 'AN';
    if (p.id.startsWith('mn:')) return 'MN';
    if (p.id.startsWith('my:')) return 'JS';
    return p.scopesAll ? 'JS' : 'SOZO';
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final items = _filtered;
    final effective = _isAll ? widget.providers.length : _selected.length;
    final overCap = effective > _softCap;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textHint.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('search.search_sources'.tr(),
                              style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800)),
                          Text(
                              _isAll
                                  ? 'search.all_sources_n'
                                      .tr(args: ['${widget.providers.length}'])
                                  : 'search.selected_n_of_m'.tr(args: [
                                      '${_selected.length}',
                                      '${widget.providers.length}',
                                    ]),
                              style: const TextStyle(
                                  color: AppColors.textHint, fontSize: 12)),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: _isAll ? null : () => setState(_selected.clear),
                      child: Text('search.select_all_sources'.tr()),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  style: const TextStyle(color: Colors.white),
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'search.filter_providers'.tr(),
                    hintStyle: const TextStyle(color: AppColors.textHint),
                    prefixIcon: const Icon(Icons.search,
                        color: AppColors.textHint, size: 20),
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              if (overCap)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'search.many_sources_warning'.tr(args: ['$effective']),
                    style: const TextStyle(
                        color: Colors.orange, fontSize: 11.5, height: 1.3),
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final p = items[i];
                    final on = _isAll || _selected.contains(p.id);
                    return CheckboxListTile(
                      value: on,
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: AppColors.primary,
                      onChanged: (_) => setState(() {
                        // Unchecking a row while every source is in scope has
                        // to materialise the full set first, or it would read
                        // as a no-op.
                        if (_isAll) {
                          _selected
                            ..clear()
                            ..addAll(widget.providers.map((e) => e.id))
                            ..remove(p.id);
                        } else if (on) {
                          _selected.remove(p.id);
                        } else {
                          _selected.add(p.id);
                        }
                      }),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(p.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 14)),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceVariant,
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(_tag(p),
                                style: const TextStyle(
                                    color: AppColors.textHint,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                  child: SizedBox(
                    height: 48,
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary),
                      onPressed: () => Navigator.of(context).pop(_result),
                      child: Text(_isAll
                          ? 'search.apply_all'.tr()
                          : 'search.apply_n'.tr(args: ['${_selected.length}'])),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
