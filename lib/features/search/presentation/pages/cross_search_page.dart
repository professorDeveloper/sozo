import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/detail/domain/entities/detail_args.dart';
import 'package:soplay/features/profile/domain/entities/provider_entity.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_bloc.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_state.dart';
import 'package:soplay/features/search/domain/entities/cross_search_result.dart';
import 'package:soplay/features/search/domain/entities/cross_search_scope.dart';
import 'package:soplay/features/search/domain/services/cross_search_engine.dart';
import 'package:soplay/features/search/presentation/blocs/cross_search_controller.dart';
import 'package:soplay/features/search/presentation/blocs/search_query_policy.dart';
import 'package:soplay/features/search/presentation/widgets/search_result_card.dart';
import 'package:soplay/features/search/presentation/widgets/search_set_sheet.dart';
import 'package:soplay/features/search/presentation/widgets/source_scope_bar.dart';

class CrossSearchPage extends StatefulWidget {
  const CrossSearchPage({super.key, this.initialQuery, this.initialProviderIds});

  final String? initialQuery;

  /// Start narrowed to these sources. Used when the caller already knows which
  /// one it wants — picking a source on an AniList title, say. It is a starting
  /// point, not a setting: it is never persisted, and the "All sources" chip
  /// sits next to it so widening back is one tap.
  final Set<String>? initialProviderIds;

  @override
  State<CrossSearchPage> createState() => _CrossSearchPageState();
}

class _CrossSearchPageState extends State<CrossSearchPage> {
  final _textController = TextEditingController();
  late final CrossSearchController _controller;

  CrossSearchScope _scope = const CrossSearchScope.all();
  List<ProviderEntity> _providers = const [];

  /// Chip order, recomputed only when the provider list or the picker changes
  /// it — never on a chip tap, so a chip cannot move out from under the finger.
  List<String> _railOrder = const [];
  bool _offline = false;
  bool _loadingProviders = true;
  bool _grouped = false;

  /// Searching every source can mean hundreds of legs, so the per-source list
  /// is only built while it is open.
  bool _statusOpen = false;

  @override
  void initState() {
    super.initState();
    final state = context.read<ProviderBloc>().state;
    _adoptProviders(state);
    _scope = _initialScope(_providers);
    _railOrder = _orderedIds(_providers, _scope);
    _controller = CrossSearchController(
      engine: getIt<CrossSearchEngine>(),
      set: _refs(),
    );
    final q = widget.initialQuery?.trim() ?? '';
    if (q.isNotEmpty) {
      _textController.text = q;
      _controller.submit(q);
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Offline this yields only the on-device plugins: fanning out to server
  /// providers with the API down would just add a row of failed legs.
  List<ProviderEntity> _providersOf(ProviderState state) =>
      state is ProviderLoaded ? state.usableProviders : const [];

  void _adoptProviders(ProviderState state) {
    _providers = _providersOf(state);
    _offline = state is ProviderLoaded && state.offline;
    _loadingProviders = state is! ProviderLoaded && state is! ProviderError;
  }

  /// The page used to snapshot ProviderBloc once in initState, so opening it
  /// before the providers had loaded left it permanently empty.
  void _syncProviders(ProviderState state) {
    final next = _providersOf(state);
    final sameList = next.length == _providers.length &&
        next.every((p) => _providers.any((e) => e.id == p.id));
    final offline = state is ProviderLoaded && state.offline;
    final loading = state is! ProviderLoaded && state is! ProviderError;
    if (sameList && offline == _offline && loading == _loadingProviders) return;

    final hadNone = _providers.isEmpty;
    _adoptProviders(state);
    // The stored scope can only be read once the list it refers to exists;
    // before that a "these three sources" choice would prune away to nothing.
    _scope = hadNone ? _initialScope(_providers) : _scope.pruned(_providers);
    _railOrder = _orderedIds(_providers, _scope);
    setState(() {});
    _controller.setProviderSet(_refs());
  }

  /// Every usable source, unless the user (or the caller) narrowed it.
  ///
  /// The old chain fell back to the favourites list and then to the single
  /// "current" provider, so a user who had never opened the picker searched one
  /// source and was told "Found in 0 of 1" — which reads as an empty internet
  /// rather than as a scope of one.
  CrossSearchScope _initialScope(List<ProviderEntity> providers) {
    final requested = widget.initialProviderIds
        ?.where((id) => providers.any((p) => p.id == id));
    if (requested != null && requested.isNotEmpty) {
      return CrossSearchScope.only(requested);
    }
    final stored =
        CrossSearchScope.fromStored(getIt<HiveService>().getCrossSearchProviders());
    return providers.isEmpty ? stored : stored.pruned(providers);
  }

  List<String> _orderedIds(List<ProviderEntity> providers, CrossSearchScope scope) {
    final selected = <String>[];
    final rest = <String>[];
    for (final p in providers) {
      (!scope.isAll && scope.includes(p.id) ? selected : rest).add(p.id);
    }
    return [...selected, ...rest];
  }

  List<ProviderRef> _refs() =>
      _scope.resolve(_providers).map(ProviderRef.fromEntity).toList();

  void _applyScope(CrossSearchScope scope, {bool reorder = false}) {
    if (scope == _scope) return;
    _scope = scope;
    if (reorder) _railOrder = _orderedIds(_providers, scope);
    unawaited(getIt<HiveService>().setCrossSearchProviders(scope.toStored()));
    setState(() {});
    _controller.setProviderSet(_refs());
  }

  Future<void> _openSetSheet() async {
    final result = await SearchSetSheet.show(
      context,
      providers: _providers,
      scope: _scope,
    );
    if (result == null || !mounted) return;
    _applyScope(result, reorder: true);
  }

  void _openDetail(MergedSearchTitle title) {
    if (title.sourceCount <= 1) {
      _push(title.hits.first);
      return;
    }
    // Scrollable and height-capped: the list is as long as the number of sources that
    // matched, which is exactly what all-source search is for, and a fixed Column ran off
    // the bottom of the sheet as soon as it found more than a handful.
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Text(
                'search.open_from'.tr(),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 8),
                itemCount: title.hits.length,
                itemBuilder: (_, i) {
                  final hit = title.hits[i];
                  return ListTile(
                    dense: true,
                    leading: Icon(Icons.play_circle_outline,
                        color: AppColors.primary, size: 20),
                    title: Text(hit.provider.name,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 14)),
                    subtitle: Text(hit.item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.textHint, fontSize: 12)),
                    onTap: () {
                      Navigator.of(context).pop();
                      _push(hit);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _push(TitleHit hit) {
    if (hit.item.url.isEmpty) return;
    context.push(
      '/detail',
      extra: DetailArgs(
        contentUrl: hit.item.url,
        preview: hit.item,
        provider: _providerIdOf(hit),
      ),
    );
  }

  /// The source this hit came from, never the app's "current" provider.
  String? _providerIdOf(TitleHit hit) {
    if (hit.provider.kind == ProviderKind.server &&
        hit.item.provider.isNotEmpty) {
      return hit.item.provider;
    }
    return hit.provider.id;
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ProviderBloc, ProviderState>(
      listener: (_, state) => _syncProviders(state),
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          elevation: 0,
          title: Text('search.all_source_search'.tr(),
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          actions: [
            IconButton(
              tooltip: _grouped
                  ? 'search.merge_titles'.tr()
                  : 'search.group_by_source'.tr(),
              onPressed: () => setState(() => _grouped = !_grouped),
              icon: Icon(
                _grouped ? Icons.grid_view_rounded : Icons.view_agenda_outlined,
                size: 20,
              ),
            ),
          ],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _searchField(),
            SourceScopeBar(
              providers: _providers,
              order: _railOrder,
              scope: _scope,
              loading: _loadingProviders && _providers.isEmpty,
              onToggle: (id) => _applyScope(_scope.toggle(id)),
              onSelectAll: () =>
                  _applyScope(const CrossSearchScope.all(), reorder: true),
              onOpenPicker: _openSetSheet,
            ),
            const SizedBox(height: 10),
            const Divider(height: 1, color: Colors.white10),
            Expanded(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (_, _) => _body(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: TextField(
        controller: _textController,
        autofocus: (widget.initialQuery ?? '').trim().isEmpty,
        style: const TextStyle(color: Colors.white),
        textInputAction: TextInputAction.search,
        onChanged: _controller.onQueryChanged,
        onSubmitted: (value) {
          FocusScope.of(context).unfocus();
          _controller.submit(value);
        },
        decoration: InputDecoration(
          isDense: true,
          hintText: 'search.cross_hint'.tr(),
          hintStyle: const TextStyle(color: AppColors.textHint),
          prefixIcon:
              const Icon(Icons.search, color: AppColors.textHint, size: 20),
          // Driven by the controller: nothing else subscribes to it, so the
          // clear button used to appear only on an unrelated rebuild.
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _textController,
            builder: (_, value, _) => value.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    icon: const Icon(Icons.close, color: AppColors.textHint),
                    onPressed: () {
                      _textController.clear();
                      _controller.onQueryChanged('');
                    },
                  ),
          ),
          filled: true,
          fillColor: AppColors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_providers.isEmpty) {
      return _loadingProviders
          ? _centered(
              icon: Icons.travel_explore,
              text: 'search.loading_sources'.tr(),
              action: const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : _centered(
              icon: Icons.tune,
              text: 'search.no_sources_available'.tr(),
            );
    }
    if (_controller.query.isEmpty) {
      return _centered(
        icon: Icons.travel_explore,
        text: 'search.type_to_search_n'
            .tr(args: ['${_controller.expectedLegs}']),
      );
    }
    if (_controller.awaitingLongerQuery) {
      return _centered(
        icon: Icons.keyboard,
        text: 'search.min_query_n'.tr(args: ['${SearchQueryPolicy.minLength}']),
      );
    }

    final merged = _controller.merged;
    final done = _controller.phase == CrossSearchPhase.done;

    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverToBoxAdapter(child: _summary()),
        if (_offline)
          SliverToBoxAdapter(child: _note('search.offline_note'.tr())),
        if (merged.isEmpty && done)
          SliverToBoxAdapter(child: _emptyResults())
        else if (_grouped)
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, i) => _providerSection(_controller.legsWithItems[i]),
              childCount: _controller.legsWithItems.length,
            ),
          )
        else
          _mergedGrid(merged),
        if (_controller.hasMoreAnywhere && done)
          SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: OutlinedButton(
                  onPressed:
                      _controller.loadingMore ? null : _controller.loadMore,
                  child: _controller.loadingMore
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text('search.load_more'.tr()),
                ),
              ),
            ),
          ),
        SliverToBoxAdapter(child: _sourceStatusList()),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  Widget _mergedGrid(List<MergedSearchTitle> merged) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate(
          (_, i) {
            final title = merged[i];
            return SearchResultCard(
              key: ValueKey('${title.key}|${title.year ?? ''}'),
              movie: title.primary,
              provider: _providerIdOf(title.hits.first),
              sourceLabel: title.sourceCount > 1
                  ? 'search.sources_n'.tr(args: ['${title.sourceCount}'])
                  : title.primaryProvider.name,
              sourceCount: title.sourceCount,
              onTap: () => _openDetail(title),
            );
          },
          childCount: merged.length,
        ),
        gridDelegate: searchGridDelegate(context),
      ),
    );
  }

  /// Progress first, then one pill per outcome.
  ///
  /// The old single line collapsed four outcomes into "found in X of Y", so a
  /// source that crashed, a source that timed out and a source that genuinely
  /// had nothing were all reported as the same missing Y.
  Widget _summary() {
    final c = _controller;
    final headline = c.searching
        ? (c.pendingSources.isEmpty
            ? 'search.searching'.tr()
            : 'search.waiting_for'.tr(args: [c.pendingSources.take(2).join(', ')]))
        : 'search.found_in'.tr(args: [
            '${c.sourcesWithResults}',
            '${c.expectedLegs}',
          ]);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (c.searching) ...[
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  '$headline · ${'search.results_n'.tr(args: ['${c.totalItems}'])}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12.5),
                ),
              ),
              if (c.failedLegs.isNotEmpty && !c.searching)
                TextButton(
                  onPressed: _controller.retryFailed,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: Text('search.retry_failed'.tr()),
                ),
            ],
          ),
          _statusPills(c),
        ],
      ),
    );
  }

  Widget _statusPills(CrossSearchController c) {
    final pills = <Widget>[
      if (c.runningSources > 0)
        _pill('search.status_searching_n'.tr(args: ['${c.runningSources}']),
            AppColors.textSecondary),
      if (c.sourcesWithResults > 0)
        _pill('search.status_with_results_n'.tr(args: ['${c.sourcesWithResults}']),
            AppColors.success),
      if (c.emptySources > 0)
        _pill('search.status_no_match_n'.tr(args: ['${c.emptySources}']),
            AppColors.textHint),
      if (c.timedOutSources > 0)
        _pill('search.status_timed_out_n'.tr(args: ['${c.timedOutSources}']),
            Colors.orange),
      if (c.erroredSources > 0)
        _pill('search.status_failed_n'.tr(args: ['${c.erroredSources}']),
            AppColors.error),
    ];
    if (pills.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(spacing: 6, runSpacing: 6, children: pills),
    );
  }

  Widget _pill(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      );

  /// Nothing to show — but *why* nothing decides what the user should do next.
  Widget _emptyResults() {
    final c = _controller;
    final broken = c.brokenSources;
    final String text;
    if (c.everySourceBroken) {
      text = broken == 1
          ? 'search.all_sources_failed_one'.tr()
          : 'search.all_sources_failed'.tr(args: ['$broken']);
    } else if (broken > 0) {
      text = 'search.no_results_with_failures'
          .tr(args: ['${c.emptySources}', '$broken']);
    } else {
      text = 'search.no_results_any'.tr();
    }

    // Both offers can apply at once: a narrowed search whose only source broke
    // is exactly the case the user reads as "the app found nothing".
    final buttons = <Widget>[
      if (broken > 0)
        FilledButton.tonal(
          onPressed: c.retryFailed,
          child: Text('search.retry_failed'.tr()),
        ),
      if (!_scope.isAll)
        FilledButton(
          onPressed: () =>
              _applyScope(const CrossSearchScope.all(), reorder: true),
          child: Text('search.search_all_sources'.tr()),
        ),
    ];

    return _centered(
      icon: broken > 0 ? Icons.cloud_off : Icons.search_off,
      text: text,
      action: buttons.isEmpty
          ? null
          : Wrap(spacing: 10, runSpacing: 8, children: buttons),
      padded: false,
    );
  }

  Widget _providerSection(ProviderSearchResult r) {
    return Column(
      key: ValueKey('section-${r.provider.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  r.provider.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('${r.items.length}',
                    style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
        SizedBox(
          height: searchCardHeight(116),
          child: ListView.separated(
            key: PageStorageKey('cross-rail-${r.provider.id}'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: r.items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final m = r.items[i];
              final hit = TitleHit(provider: r.provider, item: m);
              return SearchResultCard(
                width: 116,
                movie: m,
                provider: _providerIdOf(hit),
                sourceLabel: m.year != null ? '${m.year}' : '',
                onTap: () => _push(hit),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Every leg by name with what it did, and a Retry for the ones that failed.
  Widget _sourceStatusList() {
    final legs = _controller.results;
    final pending = _controller.pendingSources;
    if (legs.isEmpty && pending.isEmpty) return const SizedBox.shrink();
    final hasFailures = _controller.failedLegs.isNotEmpty;
    final open = _statusOpen || hasFailures;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        // ExpansionTile reads initiallyExpanded once, at mount. A leg that
        // fails after the first build would otherwise leave the tile collapsed
        // over rows that were built and never shown — the failure detail
        // present in the tree and invisible on screen.
        key: ValueKey('src-status-$hasFailures'),
        initiallyExpanded: open,
        onExpansionChanged: (v) => setState(() => _statusOpen = v),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        title: Text(
          'search.sources'.tr(),
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        children: open ? _statusRows(legs, pending) : const [],
      ),
    );
  }

  List<Widget> _statusRows(
    List<ProviderSearchResult> legs,
    List<String> pending,
  ) {
    return [
          for (final leg in legs)
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.only(left: 16, right: 8),
              title: Text(leg.provider.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 13)),
              subtitle: Text(
                _statusLabel(leg),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: _statusColor(leg), fontSize: 11.5),
              ),
              trailing: leg.status == ProviderSearchStatus.ok ||
                      leg.status == ProviderSearchStatus.empty
                  ? null
                  : _controller.isRetrying(leg.provider.id)
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : TextButton(
                          onPressed: () =>
                              _controller.retryProvider(leg.provider.id),
                          child: Text('general.retry'.tr()),
                        ),
            ),
          // Legs that have not answered are listed too: an absent row is what
          // made a still-running source look like a source with no results.
          for (final name in pending)
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.only(left: 16, right: 8),
              title: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 13)),
              subtitle: Text('search.status_searching'.tr(),
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 11.5)),
              trailing: const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
    ];
  }

  String _statusLabel(ProviderSearchResult leg) => switch (leg.status) {
        ProviderSearchStatus.ok =>
          'search.results_n'.tr(args: ['${leg.items.length}']),
        ProviderSearchStatus.empty => 'search.no_results'.tr(),
        ProviderSearchStatus.timeout => 'errors.timeout'.tr(),
        ProviderSearchStatus.error => leg.message.isEmpty
            ? 'search.source_failed'.tr()
            : leg.message,
      };

  Color _statusColor(ProviderSearchResult leg) => switch (leg.status) {
        ProviderSearchStatus.ok => AppColors.success,
        ProviderSearchStatus.empty => AppColors.textHint,
        ProviderSearchStatus.timeout => Colors.orange,
        ProviderSearchStatus.error => AppColors.error,
      };

  Widget _note(String text) => Container(
        margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text,
            style: const TextStyle(
                color: Colors.orange, fontSize: 11.5, height: 1.3)),
      );

  Widget _centered({
    required IconData icon,
    required String text,
    Widget? action,
    bool padded = true,
  }) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: AppColors.textHint.withValues(alpha: 0.5), size: 56),
        const SizedBox(height: 14),
        Text(text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textHint, fontSize: 14)),
        if (action != null) ...[const SizedBox(height: 16), action],
      ],
    );
    if (!padded) {
      return Padding(
          padding: const EdgeInsets.symmetric(vertical: 60),
          child: Center(child: content));
    }
    return Center(
      child: Padding(padding: const EdgeInsets.all(32), child: content),
    );
  }
}

/// What to search, and where.
///
/// A record rather than more positional route arguments: `/cross-search` is
/// pushed from several screens and a bare String had no room for the source a
/// caller already decided on.
class CrossSearchRequest {
  const CrossSearchRequest({required this.query, this.providerIds});

  final String query;
  final Set<String>? providerIds;
}
