import 'dart:async';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:soplay/core/cloudstream/cloudstream_channel.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/extensions/source_language.dart' as srclang;
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/cloudflare/cloudflare_solver.dart';
import 'package:soplay/features/cloudstream/presentation/pages/cloudstream_sources_page.dart';
import 'package:soplay/features/profile/domain/entities/provider_entity.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_bloc.dart';
import 'package:soplay/features/profile/presentation/pages/provider_test_page.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_event.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_state.dart';

String providerGroup(ProviderEntity p) {
  if (p.category == 'cloudstream') return 'cloudstream';
  if (p.category == 'aniyomi') return 'aniyomi';
  if (p.category == 'manga') return 'manga';
  if (p.category == 'mangayomi') return 'mangayomi';
  return switch (p.mode) {
    'hybrid' => 'hybrid',
    'client' => 'local',
    _ => 'cloud',
  };
}

String _providerSheetFilter = 'all';

/// Full-screen provider picker, routed at `/providers` and also pushed
/// imperatively from the home top bar and the outage banner.
class ProvidersPage extends StatefulWidget {
  const ProvidersPage({super.key});

  /// Push carrying an explicit [ProviderBloc], for callers that cannot rely on
  /// an ambient one.
  static void open(BuildContext context, ProviderBloc bloc) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            BlocProvider.value(value: bloc, child: const ProvidersPage()),
      ),
    );
  }

  @override
  State<ProvidersPage> createState() => _ProvidersPageState();
}

class _ProvidersPageState extends State<ProvidersPage> {
  late String _selectedCategory;
  final _searchController = TextEditingController();
  String _query = '';
  Timer? _searchDebounce;

  /// Source languages the user wants, persisted. Empty — the shipped default —
  /// means no preference and filters nothing out, so a user who never touches
  /// the row sees the list exactly as it was before it existed.
  late List<String> _languages;

  @override
  void initState() {
    super.initState();
    _languages = getIt<HiveService>().getProviderLanguages();
    final hasFavorites = getIt<HiveService>().getFavoriteProviders().isNotEmpty;
    var initial = _providerSheetFilter;
    if (initial == 'favorites' && !hasFavorites) initial = 'all';
    if (initial == 'all' && hasFavorites) initial = 'favorites';
    _selectedCategory = initial;
    _providerSheetFilter = initial;
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _toggleFavorite(String id) async {
    await getIt<HiveService>().toggleFavoriteProvider(id);
    if (!mounted) return;
    if (_selectedCategory == 'favorites' &&
        getIt<HiveService>().getFavoriteProviders().isEmpty) {
      _selectedCategory = 'all';
      _providerSheetFilter = 'all';
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        title: Text('profile.choose_provider'.tr()),
        actions: [
          // Next to the list it reports on, because that is where someone
          // already is when a source stops working for them.
          BlocBuilder<ProviderBloc, ProviderState>(
            builder: (context, state) => state is ProviderLoaded
                ? IconButton(
                    tooltip: 'provider_test.entry'.tr(),
                    onPressed: () => ProviderTestPage.open(
                      context,
                      _filteredProviders(state.providers),
                    ),
                    icon: const Icon(Icons.network_check_rounded, size: 21),
                    color: Colors.white70,
                  )
                : const SizedBox.shrink(),
          ),
          BlocBuilder<ProviderBloc, ProviderState>(
            builder: (context, state) => state is ProviderLoaded
                ? Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6),
                    child: _CategoryFilterButton(
                      providers: state.providers,
                      selected: _selectedCategory,
                      onSelected: (cat) => setState(() {
                        _selectedCategory = cat;
                        _providerSheetFilter = cat;
                      }),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
      body: BlocBuilder<ProviderBloc, ProviderState>(
        builder: (context, state) {
          final filtered = state is ProviderLoaded
              ? _filteredProviders(state.providers)
              : const <ProviderEntity>[];
          final favorites = getIt<HiveService>().getFavoriteProviders().toSet();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) {
                    _searchDebounce?.cancel();
                    _searchDebounce = Timer(
                      const Duration(milliseconds: 200),
                      () {
                        if (mounted) setState(() => _query = v.trim());
                      },
                    );
                  },
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'profile.search_providers_hint'.tr(),
                    hintStyle: const TextStyle(color: AppColors.textHint),
                    prefixIcon: const Icon(
                      Icons.search,
                      color: AppColors.textHint,
                      size: 20,
                    ),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(
                              Icons.clear,
                              color: AppColors.textHint,
                              size: 20,
                            ),
                            onPressed: () => setState(() {
                              _searchController.clear();
                              _query = '';
                            }),
                          ),
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              if (state is ProviderLoaded)
                _LanguageFilterRow(
                  // Built from the languages the INSTALLED sources actually
                  // carry, not from a fixed list. A repo that ships Kazakh
                  // tomorrow shows Kazakh tomorrow, with no app release.
                  //
                  // One pass for both the row and its counts. The obvious
                  // shape — a count per chip, each scanning the provider list —
                  // is quadratic over a list that reaches four figures once the
                  // extension hosts are installed, and it runs on every rebuild
                  // of a page that rebuilds on every keystroke in the search
                  // box.
                  counts: _languageCounts(state.providers),
                  languages: srclang.orderedLanguages(
                    _languageCounts(state.providers).keys,
                    _languages,
                  ),
                  selected: _languages,
                  onToggle: _toggleLanguage,
                  onClear: _languages.isEmpty ? null : _clearLanguages,
                ),
              if (state is ProviderLoaded && state.offline)
                _ProvidersOfflineBanner(
                  usableCount: state.usableProviders.length,
                  cachedAt: state.cachedAt,
                  onRetry: () =>
                      context.read<ProviderBloc>().add(const ProviderLoad()),
                ),
              if (state is ProviderLoaded)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 16, 6),
                    child: Text(
                      _query.isEmpty
                          ? 'profile.count_of_total_shown'.tr(
                              args: [
                                '${filtered.length}',
                                '${state.providers.length}',
                              ],
                            )
                          // A query ignores the category chip, so say so —
                          // otherwise a hit from a hidden group looks like a bug.
                          : '${filtered.length} / ${state.providers.length} · '
                                '${'profile.searching_all_sources'.tr()}',
                      style: const TextStyle(
                        color: AppColors.textHint,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: switch (state) {
                  ProviderLoaded() =>
                    filtered.isEmpty
                        ? const _ProvidersEmpty()
                        : _ProvidersList(
                            providers: filtered,
                            currentProviderId: state.currentProviderId,
                            bottomPad: bottomPad,
                            favorites: favorites,
                            onToggleFavorite: _toggleFavorite,
                            unavailableIds: {
                              for (final p in state.providers)
                                if (!state.isUsable(p)) p.id,
                            },
                          ),
                  ProviderError() => _ProvidersError(
                    onRetry: () =>
                        context.read<ProviderBloc>().add(const ProviderLoad()),
                  ),
                  _ => const _ProvidersLoading(),
                },
              ),
            ],
          );
        },
      ),
    );
  }

  /// Providers matching the current category + query.
  ///
  /// **A query searches every provider, not just the active category.** The
  /// category chips are a browsing aid; "All" deliberately hides the 260+
  /// CloudStream/Aniyomi/Manga extension sources so the default list stays
  /// short. Scoping the search box to that same subset meant typing an
  /// installed extension's name in the default view found nothing at all —
  /// the one place a user with hundreds of sources actually needs search.
  /// How many providers carry each language, computed once per provider list.
  ///
  /// Cached on identity: `ProviderLoaded` hands out the same list instance
  /// until providers are reloaded, so a rebuild driven by typing, favouriting
  /// or toggling a chip re-uses the tally instead of walking a four-figure
  /// list again.
  List<ProviderEntity>? _countsFor;
  Map<String, int> _countsCache = const {};

  Map<String, int> _languageCounts(List<ProviderEntity> providers) {
    if (identical(_countsFor, providers)) return _countsCache;
    final out = <String, int>{};
    for (final p in providers) {
      final key = srclang.normalizeLang(p.lang);
      if (key.isEmpty) continue;
      out[key] = (out[key] ?? 0) + 1;
    }
    _countsFor = providers;
    _countsCache = out;
    return out;
  }

  Future<void> _clearLanguages() async {
    await getIt<HiveService>().setProviderLanguages(const []);
    if (!mounted) return;
    setState(() => _languages = const []);
    context.read<ProviderBloc>().add(const ProviderLoad());
  }

  /// Toggling a language writes through immediately.
  ///
  /// The same list also decides which variant of a same-named source survives
  /// collapsing inside the hosts, and that happens the next time providers are
  /// loaded — so the write has to land before the reload, not after it.
  Future<void> _toggleLanguage(String code) async {
    final next = List<String>.from(_languages);
    if (next.remove(code) == false) next.add(code);
    await getIt<HiveService>().setProviderLanguages(next);
    if (!mounted) return;
    setState(() => _languages = next);
    // Mangayomi collapses by language at list time, so the set of rows itself
    // changes with this preference — a rebuild of the current list is not
    // enough, the list has to be rebuilt.
    context.read<ProviderBloc>().add(const ProviderLoad());
  }

  List<ProviderEntity> _filteredProviders(List<ProviderEntity> every) {
    final q = _query.trim().toLowerCase();
    // The language row narrows a search too, unlike the category chips. A
    // category is a place to browse and a search deliberately escapes it; a
    // language is a statement about what the user can actually watch, and a
    // result they cannot read is not a better result for being findable.
    final all = [
      for (final p in every)
        if (srclang.langMatches(p.lang, _languages)) p,
    ];
    if (q.isNotEmpty) {
      return all
          .where(
            (p) =>
                p.name.toLowerCase().contains(q) ||
                p.id.toLowerCase().contains(q),
          )
          .toList();
    }

    Iterable<ProviderEntity> list;
    if (_selectedCategory == 'favorites') {
      final favs = getIt<HiveService>().getFavoriteProviders().toSet();
      list = all.where((p) => favs.contains(p.id));
    } else if (_selectedCategory == 'all') {
      list = all.where(
        (p) =>
            providerGroup(p) != 'cloudstream' &&
            providerGroup(p) != 'aniyomi' &&
            providerGroup(p) != 'manga' &&
            providerGroup(p) != 'mangayomi',
      );
    } else if (_selectedCategory.startsWith('repo:')) {
      final repo = _selectedCategory.substring(5);
      list = all.where(
        (p) => providerGroup(p) == 'cloudstream' && p.description == repo,
      );
    } else {
      list = all.where((p) => providerGroup(p) == _selectedCategory);
    }
    return list.toList();
  }
}

/// Horizontal language chips over the provider list.
///
/// Multi-select and sticky: it is a statement about the user ("I watch in
/// French"), not a transient view toggle, so it persists and it also decides
/// which variant of a same-named source survives collapsing in the hosts.
///
/// Nothing here is hardcoded. The row is the set of languages the installed
/// sources report, which is the only list that can be right — the ecosystems
/// between them publish well over thirty languages and add more without asking.
class _LanguageFilterRow extends StatelessWidget {
  const _LanguageFilterRow({
    required this.languages,
    required this.selected,
    required this.counts,
    required this.onToggle,
    required this.onClear,
  });

  final List<String> languages;
  final List<String> selected;
  final Map<String, int> counts;
  final ValueChanged<String> onToggle;

  /// Null while nothing is selected — there is then nothing to clear, and a
  /// live-looking button that does nothing is worse than no button.
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    // One language across every installed source is not a choice, it is the
    // answer. Drawing a row the user cannot act on only costs them height.
    if (languages.length < 2) return const SizedBox.shrink();
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        itemCount: languages.length + (onClear == null ? 0 : 1),
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          if (onClear != null && i == 0) {
            return _chip(
              label: 'profile.all_languages'.tr(),
              active: false,
              onTap: onClear!,
            );
          }
          final code = languages[i - (onClear == null ? 0 : 1)];
          final count = counts[code] ?? 0;
          return _chip(
            label: srclang.labelFor(code),
            // Zero means the language is only in the row because the user
            // picked it and then removed every source that had it. Saying so
            // beats a chip that silently empties the list when tapped.
            count: count,
            active: selected.any((c) => srclang.normalizeLang(c) == code),
            onTap: () => onToggle(code),
          );
        },
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool active,
    required VoidCallback onTap,
    int? count,
  }) {
    return Material(
      color: active ? AppColors.primary.withValues(alpha: 0.18) : AppColors.surface,
      borderRadius: BorderRadius.circular(19),
      child: InkWell(
        borderRadius: BorderRadius.circular(19),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(19),
            border: Border.all(
              color: active
                  ? AppColors.primary.withValues(alpha: 0.55)
                  : Colors.white.withValues(alpha: 0.07),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: active ? AppColors.primaryLight : AppColors.textSecondary,
                  fontSize: 12.5,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 5),
                Text(
                  '$count',
                  style: TextStyle(
                    color: active
                        ? AppColors.primaryLight.withValues(alpha: 0.75)
                        : AppColors.textHint,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryFilterButton extends StatelessWidget {
  const _CategoryFilterButton({
    required this.providers,
    required this.selected,
    required this.onSelected,
  });

  final List<ProviderEntity> providers;
  final String selected;
  final ValueChanged<String> onSelected;

  static const _canonicalOrder = [
    'favorites',
    'cloud',
    'hybrid',
    'local',
    'cloudstream',
    'aniyomi',
    'manga',
    'mangayomi',
  ];

  static const _meta = <String, (String, IconData)>{
    'all': ('All', Icons.apps_rounded),
    'favorites': ('Favorites', Icons.star),
    'cloud': ('Cloud', Icons.cloud_outlined),
    'hybrid': ('Hybrid', Icons.sync_rounded),
    'local': ('Local', Icons.smartphone_outlined),
    'cloudstream': ('CloudStream', Icons.extension_outlined),
    'aniyomi': ('Aniyomi', Icons.play_circle_outline),
    'manga': ('Manga', Icons.menu_book_outlined),
    'mangayomi': ('Mangayomi', Icons.javascript_outlined),
  };

  String _label(String key) =>
      key == 'favorites' ? 'profile.favorites'.tr() : (_meta[key]?.$1 ?? key);

  String _repoShort(String repo) {
    final seg = repo.contains('/') ? repo.split('/').last : repo;
    return seg.length > 18 ? '${seg.substring(0, 17)}…' : seg;
  }

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    for (final p in providers) {
      final g = providerGroup(p);
      counts[g] = (counts[g] ?? 0) + 1;
    }
    final favIds = getIt<HiveService>().getFavoriteProviders().toSet();
    final favoriteCount = providers.where((p) => favIds.contains(p.id)).length;
    if (favoriteCount > 0) counts['favorites'] = favoriteCount;
    final repoCounts = <String, int>{};
    for (final p in providers) {
      if (providerGroup(p) != 'cloudstream') continue;
      final r = p.description;
      if (r.isEmpty || r == 'CloudStream') continue;
      repoCounts[r] = (repoCounts[r] ?? 0) + 1;
    }
    final available = _canonicalOrder.where(counts.containsKey).toList();
    final repos = repoCounts.keys.toList()..sort();
    if (available.length < 2 && repos.isEmpty) return const SizedBox.shrink();

    final (String, IconData) selectedMeta = selected.startsWith('repo:')
        ? (_repoShort(selected.substring(5)), Icons.folder_outlined)
        : (_label(selected), (_meta[selected] ?? _meta['all']!).$2);
    final selectedCount = selected == 'all'
        ? providers.length
        : selected.startsWith('repo:')
        ? (repoCounts[selected.substring(5)] ?? 0)
        : (counts[selected] ?? 0);

    final entries = <(String, String, IconData, int)>[
      ('all', _meta['all']!.$1, _meta['all']!.$2, providers.length),
      ...available.map((cat) {
        final meta = _meta[cat] ?? (cat, Icons.label_outline);
        return (cat, _label(cat), meta.$2, counts[cat] ?? 0);
      }),
      ...repos.map(
        (r) => (
          'repo:$r',
          _repoShort(r),
          Icons.folder_outlined,
          repoCounts[r] ?? 0,
        ),
      ),
    ];

    return PopupMenuButton<String>(
      tooltip: 'search.filter'.tr(),
      offset: const Offset(0, 44),
      color: AppColors.surfaceVariant,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
      ),
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final (id, label, icon, count) in entries)
          PopupMenuItem<String>(
            value: id,
            height: 42,
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: selected == id
                      ? AppColors.primary
                      : AppColors.textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: TextStyle(
                      color: selected == id
                          ? AppColors.primary
                          : AppColors.textPrimary,
                      fontSize: 13.5,
                      fontWeight: selected == id
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '$count',
                  style: const TextStyle(
                    color: AppColors.textHint,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(10, 7, 8, 7),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(selectedMeta.$2, size: 14, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(
              selectedMeta.$1,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              '$selectedCount',
              style: const TextStyle(
                color: AppColors.textHint,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: AppColors.textHint,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProvidersList extends StatefulWidget {
  const _ProvidersList({
    required this.providers,
    required this.currentProviderId,
    required this.bottomPad,
    required this.favorites,
    required this.onToggleFavorite,
    this.unavailableIds = const {},
  });

  final List<ProviderEntity> providers;
  final String currentProviderId;
  final double bottomPad;
  final Set<String> favorites;
  final ValueChanged<String> onToggleFavorite;

  /// Providers that exist in the list but cannot serve content right now
  /// (server-backed entries while the backend is unreachable).
  final Set<String> unavailableIds;

  @override
  State<_ProvidersList> createState() => _ProvidersListState();
}

class _ProvidersListState extends State<_ProvidersList> {
  static const double _estItemExtent = 72.0;
  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    final i = widget.providers.indexWhere(
      (p) => p.id == widget.currentProviderId,
    );
    final offset = i > 2
        ? (i * _estItemExtent - 80).clamp(0.0, double.infinity)
        : 0.0;
    _controller = ScrollController(initialScrollOffset: offset);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: _controller,
      padding: EdgeInsets.fromLTRB(16, 4, 16, widget.bottomPad + 16),
      addAutomaticKeepAlives: false,
      itemExtent: _estItemExtent,
      itemCount: widget.providers.length,
      itemBuilder: (context, i) {
        final provider = widget.providers[i];
        final selected = provider.id == widget.currentProviderId;
        final unavailable = widget.unavailableIds.contains(provider.id);
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _ProviderListTile(
            provider: provider,
            selected: selected,
            isFavorite: widget.favorites.contains(provider.id),
            unavailable: unavailable,
            onToggleFavorite: () => widget.onToggleFavorite(provider.id),
            onTap: () {
              // Refuse the selection outright rather than letting it fail
              // three screens later inside a home or detail request.
              if (unavailable) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('profile.provider_needs_server'.tr()),
                    backgroundColor: AppColors.surface,
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 3),
                  ),
                );
                return;
              }
              context.read<ProviderBloc>().add(ProviderSelect(provider.id));
              Navigator.of(context).pop();
            },
          ),
        );
      },
    );
  }
}

class _ProvidersEmpty extends StatelessWidget {
  const _ProvidersEmpty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 44,
              color: AppColors.textHint.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 12),
            Text(
              'profile.no_providers_in_category'.tr(),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'profile.try_select_all'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textHint.withValues(alpha: 0.85),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProviderListTile extends StatelessWidget {
  const _ProviderListTile({
    required this.provider,
    required this.selected,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.onTap,
    this.unavailable = false,
  });

  final ProviderEntity provider;
  final bool selected;
  final bool isFavorite;
  final bool unavailable;
  final VoidCallback onToggleFavorite;
  final VoidCallback onTap;

  bool get _canSolveCloudflare =>
      provider.id.startsWith('an:') ||
      provider.id.startsWith('mn:') ||
      provider.id.startsWith('cs:');

  Future<void> _solveCloudflare(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await requestCloudflareSolve(context, provider.id);
    messenger.showSnackBar(
      SnackBar(
        content: Text(ok ? '${'general.done'.tr()} ✓' : 'general.cancel'.tr()),
        backgroundColor: AppColors.surface,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(opacity: unavailable ? 0.45 : 1, child: _tile(context));
  }

  Widget _tile(BuildContext context) {
    return Material(
      color: selected
          ? AppColors.primary.withValues(alpha: 0.10)
          : AppColors.surfaceVariant,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: selected
              ? Border.all(color: AppColors.primary, width: 1.2)
              : null,
        ),
        child: InkWell(
          onTap: onTap,
          onLongPress: _canSolveCloudflare
              ? () => _solveCloudflare(context)
              : null,
          onSecondaryTap: _canSolveCloudflare
              ? () => _solveCloudflare(context)
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                _ProviderLogo(provider: provider, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              provider.name,
                              style: TextStyle(
                                color: selected
                                    ? AppColors.textPrimary
                                    : AppColors.textSecondary,
                                fontSize: 14,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                height: 1.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          // Before the mode badge on purpose. With the language
                          // filter cleared a multi-language aggregator now
                          // occupies several rows under one name, and the code
                          // is the only thing telling them apart.
                          if (provider.lang.isNotEmpty &&
                              !provider.isAllLanguages) ...[
                            _ProviderLangBadge(lang: provider.lang),
                            const SizedBox(width: 4),
                          ],
                          if (unavailable)
                            const _ServerDownBadge()
                          else
                            _ProviderModeBadge(mode: provider.mode),
                          if (provider.browseOnly) ...[
                            const SizedBox(width: 4),
                            const _BrowseOnlyBadge(),
                          ],
                          if (provider.requiresCfBypass) ...[
                            const SizedBox(width: 4),
                            const _CfBypassBadge(),
                          ],
                          if (provider.nsfw) ...[
                            const SizedBox(width: 4),
                            const _NsfwBadge(),
                          ],
                        ],
                      ),
                      // A browse-only source says why in place of its blurb:
                      // the reason is the one thing a user needs before they
                      // pick it, and the blurb is still one tap away.
                      if (provider.browseOnly &&
                          (provider.browseOnlyReason?.isNotEmpty ?? false)) ...[
                        const SizedBox(height: 2),
                        Text(
                          provider.browseOnlyReason!,
                          style: const TextStyle(
                            color: Color(0xFFD08A3E),
                            fontSize: 11,
                            height: 1.25,
                          ),
                          // One line, like the description it replaces: the row
                          // is a fixed 44px and a second line overflows it.
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ] else if (provider.description.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          provider.description,
                          style: const TextStyle(
                            color: AppColors.textHint,
                            fontSize: 11,
                            height: 1.25,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: onToggleFavorite,
                  icon: Icon(
                    isFavorite ? Icons.star : Icons.star_border,
                    color: isFavorite ? Colors.amber : AppColors.textHint,
                    size: 20,
                  ),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 34,
                    minHeight: 34,
                  ),
                  tooltip: isFavorite
                      ? 'profile.remove_favorite'.tr()
                      : 'profile.add_favorite'.tr(),
                ),
                const SizedBox(width: 2),
                if (selected)
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 12,
                    ),
                  )
                else
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textHint,
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Replaces the mode badge on a server-backed provider while the API is down,
/// so the reason it is greyed out is readable at a glance.
class _ServerDownBadge extends StatelessWidget {
  const _ServerDownBadge();

  @override
  Widget build(BuildContext context) {
    const color = AppColors.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.45), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 9, color: color),
          const SizedBox(width: 3),
          Text(
            'profile.offline_badge'.tr(),
            style: const TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// Explains the outage in place, above a list that is still partly usable.
class _ProvidersOfflineBanner extends StatelessWidget {
  const _ProvidersOfflineBanner({
    required this.usableCount,
    required this.cachedAt,
    required this.onRetry,
  });

  final int usableCount;
  final DateTime? cachedAt;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 2, 16, 10),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 0.6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            color: AppColors.textSecondary,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'profile.offline_title'.tr(),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  usableCount > 0
                      ? 'profile.offline_local_available'.tr(
                          args: ['$usableCount'],
                        )
                      : 'profile.offline_no_local'.tr(),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                if (cachedAt != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'profile.offline_cached_at'.tr(args: [_stamp(cachedAt!)]),
                    style: const TextStyle(
                      color: AppColors.textHint,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            child: Text('general.retry'.tr()),
          ),
        ],
      ),
    );
  }

  static String _stamp(DateTime at) {
    final l = at.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(l.day)}.${two(l.month)} ${two(l.hour)}:${two(l.minute)}';
  }
}

/// `FR`, `PT-BR`, `ES` — the source's own language tag.
///
/// Drawn only when the ecosystem actually reported one and it is not `all`:
/// "this source is in every language" is not information worth a badge, and an
/// empty tag means the ecosystem declined to say rather than that the source
/// has no language.
class _ProviderLangBadge extends StatelessWidget {
  const _ProviderLangBadge({required this.lang});
  final String lang;

  static const Color _color = Color(0xFF8B5CF6);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _color.withValues(alpha: 0.45), width: 0.8),
      ),
      child: Text(
        srclang.shortLabelFor(lang),
        style: const TextStyle(
          color: _color,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _ProviderModeBadge extends StatelessWidget {
  const _ProviderModeBadge({required this.mode});
  final String mode;

  @override
  Widget build(BuildContext context) {
    final normalized = mode.toLowerCase();
    final (label, color) = switch (normalized) {
      'client' => ('Local', const Color(0xFF34A853)),
      'hybrid' => ('Hybrid', const Color(0xFFF59E0B)),
      'server' => ('Cloud', const Color(0xFF6B7280)),
      _ => (mode.isEmpty ? 'Cloud' : mode, const Color(0xFF6B7280)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.45), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _BrowseOnlyBadge extends StatelessWidget {
  const _BrowseOnlyBadge();

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFFD08A3E);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.45), width: 0.8),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.visibility_outlined, size: 9, color: color),
          SizedBox(width: 3),
          Text(
            'FAQAT KO\'RISH',
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _CfBypassBadge extends StatelessWidget {
  const _CfBypassBadge();

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFFF38020);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.45), width: 0.8),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shield_outlined, size: 9, color: color),
          SizedBox(width: 3),
          Text(
            'CF',
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _NsfwBadge extends StatelessWidget {
  const _NsfwBadge();

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFFE53935);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.45), width: 0.8),
      ),
      child: const Text(
        '18+',
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _ProvidersLoading extends StatelessWidget {
  const _ProvidersLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: AppColors.textHint,
      ),
    );
  }
}

/// Reached only when the backend is unreachable, there is no cached list *and*
/// no plugin is installed — i.e. there is genuinely no working path left. The
/// copy therefore points at installing plugins, which needs no server.
class _ProvidersError extends StatelessWidget {
  const _ProvidersError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                    child: const Icon(
                      Icons.cloud_off_rounded,
                      color: AppColors.textSecondary,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'profile.offline_title'.tr(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'profile.offline_no_local'.tr(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    height: 46,
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: onRetry,
                      child: Text('general.retry'.tr()),
                    ),
                  ),
                  if (CloudStreamChannel.isSupported) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 46,
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const CloudStreamSourcesPage(),
                          ),
                        ),
                        child: Text('profile.offline_install_plugins'.tr()),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProviderLogo extends StatelessWidget {
  const _ProviderLogo({required this.provider, this.size = 42});
  final ProviderEntity provider;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cache = (size * MediaQuery.devicePixelRatioOf(context)).round();
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: provider.image.isEmpty
          ? _ProviderFallback(name: provider.name, size: size)
          : CachedNetworkImage(
              imageUrl: provider.image,
              width: size,
              height: size,
              fit: BoxFit.cover,
              memCacheWidth: cache,
              memCacheHeight: cache,
              fadeInDuration: const Duration(milliseconds: 120),
              placeholder: (_, _) =>
                  _ProviderFallback(name: provider.name, size: size),
              errorWidget: (_, _, _) =>
                  _ProviderFallback(name: provider.name, size: size),
            ),
    );
  }
}

class _ProviderFallback extends StatelessWidget {
  const _ProviderFallback({required this.name, required this.size});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      color: AppColors.surfaceVariant,
      alignment: Alignment.center,
      child: Text(
        name.isEmpty ? '?' : name[0].toUpperCase(),
        style: TextStyle(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.38,
        ),
      ),
    );
  }
}
