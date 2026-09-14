import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:soplay/features/search/presentation/pages/cross_search_page.dart';
import 'package:soplay/features/manga/presentation/pages/manga_source_settings_page.dart';
import 'package:soplay/core/content/content_mode.dart';
import 'package:soplay/core/extensions/source_language.dart' as srclang;
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/widgets/app_tab_bar.dart';
import 'package:soplay/features/home/domain/entities/home_data_entity.dart';
import 'package:soplay/features/home/domain/entities/movie.dart';
import 'package:soplay/features/home/presentation/widgets/view_all_widgets.dart';
import 'package:soplay/features/profile/domain/entities/provider_entity.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_bloc.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_event.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_state.dart';
import 'package:soplay/features/extensions/presentation/pages/source_catalog_page.dart';
import 'package:soplay/features/extensions/domain/entities/catalog_source_entity.dart';
import 'package:soplay/features/profile/presentation/pages/sources_page.dart';
import 'package:soplay/features/sources/data/source_browse_repository.dart';
import 'package:soplay/features/sources/domain/source_ecosystem.dart';
import 'package:soplay/features/sources/domain/source_failure.dart';
import 'package:soplay/features/sources/domain/source_index.dart';

/// Select an installed source with one tap, or preview it without switching.
class SourcesHubPage extends StatefulWidget {
  const SourcesHubPage({super.key});

  @override
  State<SourcesHubPage> createState() => _SourcesHubPageState();
}

class _SourcesHubPageState extends State<SourcesHubPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: ContentMode.values.length,
    initialIndex: ContentMode.fromId(
      getIt<HiveService>().getContentMode(),
    ).index,
    vsync: this,
  );
  final TextEditingController _search = TextEditingController();

  /// The source being browsed, or null while the list is showing. Held here
  /// rather than pushed as a route so "back" returns to the list this page is,
  /// which is what "from that one page" means.
  ProviderEntity? _open;

  /// See [_tabFor].
  final Map<String, _TabSources> _tabCache = {};

  /// null is "all". Which runtime a source comes from is the axis people
  /// actually filter on here — "the one I added from CloudStream" — and it was
  /// visible only as a word in grey under each of several hundred names.
  SourceEcosystem? _eco;
  List<String> get _languages => getIt<HiveService>().getProviderLanguages();

  @override
  void initState() {
    super.initState();
    _lastTab = _tabs.index;
    // The search field, the language filter and the ecosystem chips sit ABOVE
    // the tabs now and describe whichever tab is showing, so they have to
    // follow a swipe as well as a tap. Only on arrival: rebuilding through the
    // animation would re-sort three tabs' worth of sources on every frame of
    // it, which is the cost this page was already paying before.
    _tabs.addListener(_onTabMoved);
  }

  void _onTabMoved() {
    if (_tabs.indexIsChanging || _tabs.index == _lastTab) return;
    _lastTab = _tabs.index;
    setState(() => _eco = null);
  }

  Future<void> _filterLanguage(String code) async {
    await getIt<HiveService>().setProviderLanguages(
      code == '*' ? const [] : [code],
    );
    if (!mounted) return;
    setState(() {
      _tabCache.clear();
    });
    context.read<ProviderBloc>().add(const ProviderLoad(localOnly: true));
  }

  /// What this tab is for, shown only when it is empty.
  ///
  /// Novels are the one mode nobody arrives already understanding: the word
  /// does not say that it means text rather than pictures, and nothing on
  /// screen said where a novel source comes from — so the tab read as a
  /// feature that does not work.
  static String? _modeHint(ContentMode mode) => switch (mode) {
    ContentMode.novel => 'mode.novels_hint'.tr(),
    ContentMode.manga => 'mode.manga_hint'.tr(),
    _ => null,
  };

  @override
  void dispose() {
    _tabs.removeListener(_onTabMoved);
    for (final c in _scrolls.values) {
      c.dispose();
    }
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  void _close() => setState(() => _open = null);

  /// Installing and removing extensions is a different job from browsing them,
  /// and it keeps its own screen.
  void _openExtensions() => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const SourcesPage()));

  /// One per tab. A shared controller would carry the Manga tab's offset into
  /// the Watch tab the moment the two were alive at once, which is every
  /// swipe.
  late final Map<ContentMode, ScrollController> _scrolls = {
    for (final m in ContentMode.values) m: ScrollController(),
  };

  /// The row for the source in use, so each list can be corrected onto it once
  /// it has actually been built.
  final Map<ContentMode, GlobalKey> _currentRows = {
    for (final m in ContentMode.values) m: GlobalKey(),
  };

  int _lastTab = -1;

  /// Opening on the source in use is a one-time move, per tab. Re-running it
  /// after a keystroke in the search field would drag the list out from under
  /// the typing.
  final Set<ContentMode> _aligned = {};

  /// Puts the list on the source in use rather than at the alphabetical top.
  ///
  /// Two steps, because the rows are cards whose height follows the text
  /// scale and the list is lazy — a row far down has not been built, so
  /// `ensureVisible` alone has nothing to aim at. The estimate gets close
  /// enough to build it, and the second pass corrects whatever the estimate
  /// got wrong. Neither step animates: this is where the list opens, not a
  /// journey the user should watch.
  void _alignToCurrent(ContentMode mode, List<ProviderEntity> rows, String id) {
    if (_aligned.contains(mode)) return;
    if (_search.text.trim().isNotEmpty) return;
    final index = rows.indexWhere((p) => p.id == id);
    if (index < 0) return;
    _aligned.add(mode);
    if (index < 3) return; // already on screen; moving would be noise
    final scroll = _scrolls[mode]!;
    final key = _currentRows[mode]!;
    final extent = 74 * MediaQuery.textScalerOf(context).scale(1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scroll.hasClients) return;
      // Two rows of lead-in, so it reads as one entry in a list rather than as
      // the first thing in it.
      scroll.jumpTo(
        ((index - 2) * extent).clamp(0.0, scroll.position.maxScrollExtent),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = key.currentContext;
        if (ctx == null) return;
        Scrollable.ensureVisible(ctx, alignment: 0.18);
      });
    });
  }

  Future<void> _openInstaller(ContentMode mode) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SourceCatalogPage(
          initialItemType: switch (mode) {
            ContentMode.manga => CatalogItemType.manga,
            ContentMode.novel => CatalogItemType.novel,
            ContentMode.video => null,
          },
        ),
      ),
    );
    if (!mounted) return;
    // "Use this source" can choose a different content type in the catalog.
    // Return to its tab so the newly selected source is actually visible.
    _tabs.index = ContentMode.fromId(
      getIt<HiveService>().getContentMode(),
    ).index;
    setState(() => _eco = null);
  }

  @override
  Widget build(BuildContext context) {
    final open = _open;
    return PopScope(
      canPop: open == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: open == null ? _hubBar() : _browseBar(open),
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: open == null
              ? _hub()
              : _SourceBrowseView(key: ValueKey(open.id), source: open),
        ),
      ),
    );
  }

  /// The title and the tabs, in a real app bar.
  ///
  /// They used to be a `SliverAppBar` INSIDE the list, and there was no
  /// `TabBarView` under them at all — the body was one scroll view rebuilt
  /// from `_tabs.index`. So swiping did nothing, changing tab threw the whole
  /// list away and rebuilt it, and the app bar scrolled with the content it
  /// was supposed to be above.
  PreferredSizeWidget _hubBar() {
    return AppBar(
      surfaceTintColor: Colors.transparent,
      title: Text('profile.sources_title'.tr()),
      backgroundColor: AppColors.background,
      actions: [
        // Labelled, not a sliders icon with a tooltip nobody long-presses.
        // Installing a source is the reason most people open this screen, and
        // it was the one thing on it with no words — indistinguishable from a
        // settings button, which is what a tune icon means everywhere else.
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: TextButton.icon(
            onPressed: () => _openInstaller(ContentMode.values[_tabs.index]),
            icon: const Icon(Icons.add_rounded, size: 20),
            label: Text('manga.add_source'.tr()),
          ),
        ),
        PopupMenuButton<String>(
          onSelected: (_) => _openExtensions(),
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'manage',
              child: Text('source_manager.manage_repositories'.tr()),
            ),
          ],
        ),
      ],
      bottom: AppTabBar(
        controller: _tabs,
        onChanged: (_) => setState(() => _eco = null),
        isScrollable: false,
        labels: [for (final m in ContentMode.values) m.labelKey.tr()],
      ),
    );
  }

  PreferredSizeWidget _browseBar(ProviderEntity source) {
    return AppBar(
      backgroundColor: AppColors.background,
      leading: BackButton(onPressed: _close),
      titleSpacing: 0,
      title: Row(
        children: [
          _SourceMark(url: source.image, size: 24),
          const SizedBox(width: 10),
          Expanded(child: Text(source.name, overflow: TextOverflow.ellipsis)),
        ],
      ),
      actions: [
        if (source.id.startsWith('mn:'))
          IconButton(
            tooltip: 'general.settings'.tr(),
            icon: const Icon(Icons.tune),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => MangaSourceSettingsPage(
                  sourceId: source.id.substring(3),
                  name: source.name,
                ),
              ),
            ),
          ),
        IconButton(
          tooltip: 'general.search'.tr(),
          icon: const Icon(Icons.search),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => CrossSearchPage(initialProviderIds: {source.id}),
            ),
          ),
        ),
        BlocBuilder<ProviderBloc, ProviderState>(
          builder: (context, state) {
            final current =
                state is ProviderLoaded && state.currentProviderId == source.id;
            return Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: TextButton(
                onPressed: current ? null : () => _use(source),
                child: Text(current ? 'ux.in_use'.tr() : 'ux.use_source'.tr()),
              ),
            );
          },
        ),
      ],
    );
  }

  /// Makes the browsed source the app's source.
  ///
  /// The mode moves with it. Home is driven by whichever source is current, so
  /// leaving a video source selected in manga mode shows an empty screen and
  /// reads as the switch having failed — the same reason the quick switcher
  /// carries the mode across.
  Future<void> _use(ProviderEntity source) async {
    final hive = getIt<HiveService>();
    final mode = source.id.contentMode;
    if (ContentMode.fromId(hive.getContentMode()) != mode) {
      await hive.setContentMode(mode.id);
    }
    if (!mounted) return;
    context.read<ProviderBloc>().add(ProviderSelect(source.id));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('ux.now_using'.tr(args: [source.name]))),
    );
  }

  /// One tab's providers, filtered and sorted, remembered until an input
  /// changes.
  ///
  /// This used to run inside the builder, which meant a full filter and a
  /// comparator sort of every installed source on EVERY frame — and a
  /// TabBarView builds all three tabs, so a swipe was doing it three times a
  /// frame over several hundred providers. That is what made the swipe crawl;
  /// the work itself is milliseconds, sixty times a second is not.
  _TabSources _tabFor(ProviderLoaded state, ContentMode mode, String needle) {
    final languages = _languages;
    final key =
        '${identityHashCode(state.providers)}'
        '|${state.providers.length}|${state.offline}|${mode.id}|$needle|${languages.join(',')}';
    final cached = _tabCache[key];
    if (cached != null) return cached;

    final all = [
      for (final p in state.providers)
        if (state.isUsable(p) &&
            p.id.contentMode == mode &&
            (needle.isEmpty || p.name.toLowerCase().contains(needle)))
          p,
    ];
    // Sorted here, not upstream: the quick switcher shows the same providers in
    // the order the backend sent them, because there the list is short and its
    // order is the recommendation. This page is the whole catalogue, and an
    // alphabetical list is the only kind you can find a name in.
    all.sort((a, b) => compareForIndex(a.name, b.name));

    // A chosen language SPLITS the list rather than filtering it.
    //
    // Half the sources here declare no language at all, and the old filter let
    // every one of them through — so picking English left the list almost as
    // long as it was and read as a filter that did nothing. Hiding them is the
    // other wrong answer: it would take away Sozo's own two dozen providers,
    // which are the ones most people came for.
    //
    // So: match on what the source declares, or on what its name, id and host
    // give away. What is left says nothing either way, and it goes to the end
    // under a heading that admits as much.
    final matched = <ProviderEntity>[];
    final unstated = <ProviderEntity>[];
    for (final p in all) {
      if (languages.isEmpty) {
        matched.add(p);
        continue;
      }
      final lang = srclang.inferLang(
        lang: p.lang,
        name: p.name,
        id: p.id,
        url: p.url,
      );
      if (lang == null) {
        unstated.add(p);
      } else if (languages.any((l) => srclang.normalizeLang(l) == lang)) {
        matched.add(p);
      }
    }

    final counts = <SourceEcosystem, int>{};
    for (final p in [...matched, ...unstated]) {
      final e = SourceEcosystem.of(p.id);
      counts[e] = (counts[e] ?? 0) + 1;
    }
    final built = _TabSources(
      matched: matched,
      unstated: unstated,
      counts: counts,
    );
    // Bounded: three tabs times a few search terms, and a new provider list
    // changes the key anyway. Cleared wholesale rather than aged out, because
    // the cost of a miss is one sort.
    if (_tabCache.length > 12) _tabCache.clear();
    _tabCache[key] = built;
    return built;
  }

  /// The fixed half of the page, over the three lists.
  ///
  /// Search, the language filter and the ecosystem chips describe whichever
  /// tab is showing and are shared by all three, so they sit here rather than
  /// inside each list. Inside, they scrolled away with the content and, on a
  /// swipe, slid sideways out of line with the tabs they belonged to.
  Widget _hub() {
    return BlocBuilder<ProviderBloc, ProviderState>(
      builder: (context, state) {
        if (state is ProviderError) {
          return _Message(
            text: 'profile.providers_error'.tr(),
            actionLabel: 'general.retry'.tr(),
            onAction: () =>
                context.read<ProviderBloc>().add(const ProviderLoad()),
          );
        }
        if (state is! ProviderLoaded) {
          return const Center(child: CircularProgressIndicator());
        }
        final mode = ContentMode.values[_tabs.index];
        final needle = _search.text.trim().toLowerCase();
        final counts = _tabFor(state, mode, needle).counts;
        final eco = counts.containsKey(_eco) ? _eco : null;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  'source_manager.selection_hint'.tr(),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            _searchField(state, mode),
            if (counts.length > 1)
              _EcosystemFilter(
                counts: counts,
                active: eco,
                onPick: (picked) => setState(() => _eco = picked),
              ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  for (final m in ContentMode.values)
                    _tabList(state, m, needle),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _searchField(ProviderLoaded state, ContentMode mode) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        controller: _search,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          suffixIcon: PopupMenuButton<String>(
            tooltip: 'profile.all_languages'.tr(),
            icon: Icon(
              Icons.translate,
              color: _languages.isEmpty ? null : AppColors.primary,
            ),
            onSelected: _filterLanguage,
            itemBuilder: (_) => [
              PopupMenuItem(
                value: '*',
                child: Text('profile.all_languages'.tr()),
              ),
              for (final language
                  in srclang
                      .orderedLanguages(
                        state.providers
                            .where((p) => p.id.contentMode == mode)
                            .map((p) => p.lang),
                        _languages,
                      )
                      .where((language) => language != 'all'))
                CheckedPopupMenuItem(
                  value: language,
                  checked: _languages.contains(language),
                  child: Text(srclang.labelFor(language)),
                ),
            ],
          ),
          hintText: 'general.search'.tr(),
          filled: true,
          fillColor: AppColors.card,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _tabList(ProviderLoaded state, ContentMode mode, String needle) {
    final tab = _tabFor(state, mode, needle);
    final eco = tab.counts.containsKey(_eco) ? _eco : null;
    List<ProviderEntity> narrow(List<ProviderEntity> rows) => eco == null
        ? rows
        : [
            for (final p in rows)
              if (SourceEcosystem.of(p.id) == eco) p,
          ];
    final matched = narrow(tab.matched);
    final unstated = narrow(tab.unstated);

    if (matched.isEmpty && unstated.isEmpty) {
      return _Message(
        text: needle.isEmpty && _languages.isEmpty
            ? 'mode.none_installed'.tr(args: [mode.labelKey.tr()])
            : 'profile.no_providers_in_category'.tr(),
        hint: needle.isEmpty ? _modeHint(mode) : null,
        // An empty mode is a dead end without this. Manga and novels are both
        // extension ecosystems, so a fresh install has nothing in either tab
        // and the only way out is a gear icon the message never mentions.
        actionLabel: needle.isEmpty ? 'manga.add_source'.tr() : null,
        onAction: needle.isEmpty ? () => _openInstaller(mode) : null,
      );
    }

    _alignToCurrent(mode, matched, state.currentProviderId);
    return CustomScrollView(
      key: PageStorageKey(
        'sources|${mode.id}|$needle|$eco|${_languages.join(",")}',
      ),
      controller: _scrolls[mode],
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(12, 4, 12, unstated.isEmpty ? 24 : 4),
          sliver: _rows(matched, state, mode),
        ),
        if (unstated.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'sources.language_not_stated'.tr(args: ['${unstated.length}']),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            sliver: _rows(unstated, state, mode),
          ),
        ],
      ],
    );
  }

  Widget _rows(
    List<ProviderEntity> rows,
    ProviderLoaded state,
    ContentMode mode,
  ) {
    return SliverList.separated(
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _SourceTile(
        key: rows[i].id == state.currentProviderId ? _currentRows[mode] : null,
        source: rows[i],
        current: rows[i].id == state.currentProviderId,
        onTap: () => _use(rows[i]),
        onBrowse: () => setState(() => _open = rows[i]),
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    super.key,
    required this.source,
    required this.onTap,
    required this.onBrowse,
    this.current = false,
  });

  final ProviderEntity source;

  /// Whether this is the currently selected source.
  final bool current;
  final VoidCallback onTap;
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      if (source.lang.isNotEmpty && source.lang != 'all')
        source.lang.toUpperCase(),
      if (source.category.isNotEmpty) source.category,
      if (source.browseOnly) 'profile.provider'.tr(),
    ].join(' · ');

    return HoverTap(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          // The list opens on this row, and a row you were scrolled to but
          // cannot pick out is the same as not having been scrolled at all.
          border: current
              ? Border.all(color: AppColors.primary.withValues(alpha: 0.55))
              : null,
        ),
        child: Row(
          children: [
            _SourceMark(url: source.image, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          source.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      if (current) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: AppColors.primary,
                        ),
                      ],
                    ],
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            TextButton(
              onPressed: onBrowse,
              child: Text('source_manager.browse'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}

/// One source's catalogue, rendered where the list was.
class _SourceBrowseView extends StatefulWidget {
  const _SourceBrowseView({super.key, required this.source});

  final ProviderEntity source;

  @override
  State<_SourceBrowseView> createState() => _SourceBrowseViewState();
}

class _SourceBrowseViewState extends State<_SourceBrowseView> {
  late Future<HomeDataEntity> _future = _load();

  Future<HomeDataEntity> _load() =>
      getIt<SourceBrowseRepository>().load(widget.source.id);

  void _retry() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<HomeDataEntity>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          final error = snap.error;
          // The raw object used to go straight to the screen, so a source the
          // backend does not know answered with eleven lines of DioException
          // about `validateStatus` and a link to MDN's page for HTTP 400.
          //
          // Even trimmed to the extension's own message it was still the
          // extension's vocabulary — "HttpException: HTTP error 404",
          // "InvocationTargetException: null" — which does not distinguish a
          // site that shut down from a phone with no signal. SourceFailure
          // says which, and keeps the original underneath for a bug report.
          final failure = SourceFailure.of(
            error is SourceBrowseException ? error.message : null,
          );
          return _Message(
            text: failure.headline,
            hint: failure.detail,
            actionLabel: 'general.retry'.tr(),
            onAction: _retry,
          );
        }
        final data = snap.data;
        final sections = [
          for (final s in data?.sections ?? const [])
            if (s.items.isNotEmpty) s,
        ];
        if (sections.isEmpty) {
          return _Message(
            text: 'profile.no_providers_in_category'.tr(),
            actionLabel: 'general.retry'.tr(),
            onAction: _retry,
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: sections.length,
          itemBuilder: (_, i) => _Rail(
            label: sections[i].label,
            items: sections[i].items,
            provider: widget.source.id,
          ),
        );
      },
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.label,
    required this.items,
    required this.provider,
  });

  final String label;
  final List<MovieEntity> items;
  final String provider;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width / 3.2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        SizedBox(
          height: width * 1.5 + 46,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) => SizedBox(
              width: width,
              child: ViewAllMovieCard(
                movie: items[i],
                // The source this card came from, never the app's current
                // one — browsing here must not move anything global.
                provider: provider,
                showYear: false,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SourceMark extends StatelessWidget {
  const _SourceMark({required this.url, required this.size});

  final String url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final box = SizedBox(width: size, height: size);
    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 4),
      child: url.isEmpty
          ? Container(color: AppColors.surfaceVariant, child: box)
          : CachedNetworkImage(
              imageUrl: url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              placeholder: (_, _) => box,
              errorWidget: (_, _, _) =>
                  Container(color: AppColors.surfaceVariant, child: box),
            ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.text,
    this.hint,
    this.actionLabel,
    this.onAction,
  });

  final String text;

  /// What this kind of source IS, for a tab somebody arrived at without
  /// knowing. "No novel sources installed" answers nothing if the reader does
  /// not know a novel source is a thing you install, or from where.
  final String? hint;

  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            if (hint != null) ...[
              const SizedBox(height: 10),
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textHint,
                  fontSize: 12.5,
                  height: 1.45,
                ),
              ),
            ],
            if (onAction != null) ...[
              const SizedBox(height: 16),
              TextButton(
                onPressed: onAction,
                child: Text(actionLabel ?? 'general.retry'.tr()),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Which runtime a source comes from, as a row of small chips.
///
/// Only the ecosystems this tab actually contains, and only when there is more
/// than one of them: a chip that filters to nothing teaches people the filter
/// is broken, and a single chip is a label pretending to be a control.
///
/// Each carries its count. The row costs a strip of the screen either way, and
/// a number is the difference between decoration and something worth reading —
/// "Aniyomi 214" answers where the sources went without tapping anything.
class _EcosystemFilter extends StatelessWidget {
  const _EcosystemFilter({
    required this.counts,
    required this.active,
    required this.onPick,
  });

  final Map<SourceEcosystem, int> counts;
  final SourceEcosystem? active;
  final ValueChanged<SourceEcosystem?> onPick;

  @override
  Widget build(BuildContext context) {
    final chips = <SourceEcosystem?>[
      null,
      for (final e in SourceEcosystem.values)
        if (counts.containsKey(e)) e,
    ];
    final total = counts.values.fold(0, (a, b) => a + b);
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final e = chips[i];
          final selected = e == active;
          final count = e == null ? total : counts[e] ?? 0;
          return Center(
            child: Material(
              color: selected ? AppColors.primary : AppColors.card,
              borderRadius: BorderRadius.circular(999),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onPick(e),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        e?.label ?? 'sources.eco_all'.tr(),
                        style: TextStyle(
                          color: selected
                              ? Colors.white
                              : AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '$count',
                        style: TextStyle(
                          color: selected
                              ? Colors.white70
                              : AppColors.textSecondary.withValues(alpha: 0.55),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// One tab's sources, split by whether they answer the language filter, and
/// how many come from each ecosystem.
class _TabSources {
  const _TabSources({
    required this.matched,
    required this.unstated,
    required this.counts,
  });

  /// Everything, when no language is chosen; otherwise what matched one.
  final List<ProviderEntity> matched;

  /// Sources with no language to go on. Empty unless a language is chosen.
  final List<ProviderEntity> unstated;

  final Map<SourceEcosystem, int> counts;
}
