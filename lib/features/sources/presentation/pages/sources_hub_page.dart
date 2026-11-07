import 'dart:async';

import 'package:soplay/core/widgets/quick_return_header.dart';
import 'package:soplay/core/widgets/item_appear.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:soplay/features/search/presentation/pages/cross_search_page.dart';
import 'package:soplay/features/manga/presentation/pages/manga_source_settings_page.dart';
import 'package:soplay/core/content/content_mode.dart';
import 'package:soplay/core/extensions/source_language.dart' as srclang;
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/content/catalogue.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/widgets/app_tab_bar.dart';
import 'package:soplay/features/home/domain/entities/home_data_entity.dart';
import 'package:soplay/features/home/domain/entities/movie.dart';
import 'package:soplay/features/home/presentation/widgets/view_all_widgets.dart';
import 'package:soplay/features/profile/domain/entities/provider_entity.dart';
import 'package:soplay/features/search/data/source_health_store.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_bloc.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_event.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_state.dart';
import 'package:soplay/features/extensions/presentation/pages/source_catalog_page.dart';
import 'package:soplay/features/jellyfin/presentation/pages/jellyfin_servers_page.dart';
import 'package:soplay/features/profile/presentation/pages/sources_page.dart';
import 'package:soplay/features/sources/data/source_browse_repository.dart';
import 'package:soplay/features/sources/presentation/widgets/source_verdict.dart';
import 'package:soplay/features/sources/domain/source_check_service.dart';
import 'package:soplay/features/sources/data/source_check_store.dart';
import 'package:soplay/features/sources/domain/source_scope.dart';
import 'package:soplay/features/sources/domain/source_verdict_policy.dart';
import 'package:soplay/features/sources/presentation/widgets/source_health_badge.dart';
import 'package:soplay/features/sources/presentation/widgets/source_scope_menu.dart';
import 'package:soplay/features/sources/domain/source_failure.dart';
import 'package:soplay/features/sources/domain/source_index.dart';

/// Select an installed source with one tap, or preview it without switching.
class SourcesHubPage extends StatefulWidget {
  const SourcesHubPage({super.key});

  @override
  State<SourcesHubPage> createState() => _SourcesHubPageState();
}

class _SourcesHubPageState extends State<SourcesHubPage>
    with TickerProviderStateMixin {
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
  /// Which slice of the list is showing: an ecosystem, and a repository inside
  /// it. Two axes rather than one — with six CloudStream repos installed,
  /// "CloudStream" is two hundred sources and the question is which two
  /// hundred. See [SourceScope].
  SourceScope _scope = SourceScope.all;

  /// The filters are the user's to fold away; scrolling moves the whole
  /// header instead (see [_header]).
  bool _filtersCollapsed = false;

  /// Search and filters float over the lists and scroll away with them,
  /// coming back the moment the list is pulled down.
  late final QuickReturnController _header = QuickReturnController(vsync: this);

  List<String> get _languages => getIt<HiveService>().getProviderLanguages();

  /// The needle the list is actually filtered by, behind a debounce.
  ///
  /// `onChanged` used to call `setState` on every character. One character
  /// rebuilt this page, which filters and sorts the installed set for ALL
  /// THREE tabs — `_tabList` is a method call inside a list literal, so
  /// TabBarView's laziness cannot defer it — and at a thousand sources that is
  /// several passes of `toLowerCase` plus an n·log n comparator sort per
  /// keystroke, on the UI isolate, while the keyboard is still animating.
  String _query = '';
  Timer? _searchDebounce;

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
    unawaited(sourceHealth().refreshRemote());
  }

  void _onTabMoved() {
    if (_tabs.indexIsChanging || _tabs.index == _lastTab) return;
    _lastTab = _tabs.index;
    _header.show();
    setState(() => _scope = SourceScope.all);
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
    _header.dispose();
    _searchDebounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  /// Null where the checker is not wired up — widget tests of this page.
  final SourceCheckService? _checker = getIt.isRegistered<SourceCheckService>()
      ? getIt<SourceCheckService>()
      : null;

  /// A check run in progress, for the strip under the tabs; null otherwise.
  /// The service holds it, so leaving this screen does not lose the run.
  ValueListenable<SourceCheckProgress?> get _checking =>
      _checker?.progress ?? _idle;
  static final ValueNotifier<SourceCheckProgress?> _idle = ValueNotifier(null);

  /// Only sources with something wrong, for finding the few that need
  /// attention among a thousand.
  bool _problemsOnly = false;

  /// The checkable sources on screen at the last build: the tab, narrowed by
  /// search, scope and language — "check what I am looking at".
  List<String> _shownIds = const [];

  /// The badge this row is entitled to, after [shownVerdict] has thrown out a
  /// server verdict that was never about this phone.
  RemoteVerdict? _badgeFor(ProviderEntity p) =>
      shownVerdict(p.id, sourceHealth().badgeOf(p.id, key: p.healthKey));

  bool _isProblem(ProviderEntity p) {
    if (_badgeFor(p) != null) return true;
    // Anything this phone found that is not "it answered with titles" — an
    // empty catalogue included, which is the one a badge says nothing about.
    return isProblemVerdict(SourceCheckStore.shared.verdictOf(p.id));
  }

  bool _isDown(ProviderEntity p) => _badgeFor(p)?.state == RemoteHealth.dead;

  /// The pill for what this phone found, when the server's badge has none.
  /// Keyed by [ProviderEntity.id] because that is what a check on this device
  /// is recorded under.
  SourceVerdict? _deviceBadgeFor(ProviderEntity p) =>
      deviceBadge(SourceCheckStore.shared.verdictOf(p.id), _badgeFor(p));

  /// The rows of [rows] left after the type and problems-only filters.
  List<ProviderEntity> _inScope(List<ProviderEntity> rows, SourceScope scope) =>
      scope.isAll && !_problemsOnly
      ? rows
      : [
          for (final p in rows)
            if (scope.matches(p) && (!_problemsOnly || _isProblem(p))) p,
        ];

  /// What the "Hide down sources" switch does to one tab's lists.
  ///
  /// The same call the lists themselves make, over the same narrowed rows, so
  /// the number on the chip is the number of rows it takes away. Hiding is
  /// suspended while only problems are shown — that list is asked to contain
  /// the down ones — and the count is then zero because nothing is hidden.
  DownPartition<ProviderEntity> _down(
    List<ProviderEntity> rows,
    SourceScope scope,
    String currentProviderId,
  ) {
    final health = sourceHealth();
    return partitionDown(
      _inScope(rows, scope),
      isDown: _isDown,
      keep: (p) => p.id == currentProviderId,
      hide: health.hideDown && !_problemsOnly,
    );
  }

  /// Every installed source of the tab that is showing.
  List<String> _tabIds() {
    final state = context.read<ProviderBloc>().state;
    if (state is! ProviderLoaded) return const [];
    final mode = ContentMode.values[_tabs.index];
    return [
      for (final p in state.providers)
        if (state.isUsable(p) &&
            p.id.contentMode == mode &&
            !Catalogue.isId(p.id))
          p.id,
    ];
  }

  /// The check menu: which sources to ask, and two settings.
  ///
  /// A thousand sources take the better part of an hour to go through one by
  /// one, so "all of them" is rarely the useful answer. The ones never
  /// checked or gone stale, the ones already in trouble, or just the ones on
  /// screen after a search or a language filter — each a run of minutes.
  Future<void> _onCheckMenu(String choice) async {
    final checker = _checker;
    if (checker == null) return;
    switch (choice) {
      case 'stale':
        await _checkAll(checker.staleOf(_tabIds()));
      case 'troubled':
        await _checkAll(checker.troubledOf(_tabIds()));
      case 'shown':
        await _checkAll(_shownIds);
      case 'problems':
        setState(() => _problemsOnly = !_problemsOnly);
      case 'auto':
        await SourceCheckStore.shared.setAutoSweep(
          !SourceCheckStore.shared.autoSweep,
        );
    }
  }

  List<PopupMenuEntry<String>> _checkMenu() {
    final checker = _checker!;
    final ids = _tabIds();
    final stale = checker.staleOf(ids).length;
    final troubled = checker.troubledOf(ids).length;
    return [
      PopupMenuItem(
        value: 'stale',
        enabled: stale > 0,
        child: Text('sources.check_stale'.tr(args: ['$stale'])),
      ),
      PopupMenuItem(
        value: 'troubled',
        enabled: troubled > 0,
        child: Text('sources.check_troubled'.tr(args: ['$troubled'])),
      ),
      PopupMenuItem(
        value: 'shown',
        enabled: _shownIds.isNotEmpty,
        child: Text('sources.check_shown'.tr(args: ['${_shownIds.length}'])),
      ),
      const PopupMenuDivider(),
      CheckedPopupMenuItem(
        value: 'problems',
        checked: _problemsOnly,
        child: Text('sources.problems_only'.tr()),
      ),
      CheckedPopupMenuItem(
        value: 'auto',
        checked: SourceCheckStore.shared.autoSweep,
        child: Text('sources.auto_sweep'.tr()),
      ),
    ];
  }

  /// Checks [ids] on this device and sums up what it found. The server
  /// sweeps extension sites every night; this runs each source's own code,
  /// which is what breaks when a site changes, and covers sources the server
  /// cannot see.
  Future<void> _checkAll(List<String> ids) async {
    final checker = _checker;
    if (checker == null || checker.running) return;
    final state = context.read<ProviderBloc>().state;
    if (state is! ProviderLoaded) return;
    if (ids.isEmpty) return;
    SourceCheckProgress? last;
    await for (final progress in checker.checkAll(ids)) {
      last = progress;
    }
    if (!mounted || last == null) return;
    setState(() => _tabCache.clear());
    final checks = SourceCheckStore.shared;
    final names = {for (final p in state.providers) p.id: p.name};
    final bad = [
      for (final id in ids)
        if (checks.of(id)?.isBad ?? false) id,
    ];
    final health = sourceHealth();
    await showAdaptiveModal<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheet) => CheckSummarySheet(
        result: last!,
        bad: bad,
        names: names,
        store: checks,
        hidingDown: health.hideDown,
        onHideDown: () async {
          Navigator.of(sheet).pop();
          await health.setHideDown(true);
          if (mounted) setState(() => _tabCache.clear());
        },
      ),
    );
  }

  void _close() => setState(() => _open = null);

  /// Installing and removing extensions is a different job from browsing them,
  /// and it keeps its own screen.
  void _openExtensions() => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const SourcesPage()));

  /// Straight to the installable catalogue, opened on this tab's kind of
  /// source.
  ///
  /// v3.2.0 removed this and left only "Manage", so adding a source meant
  /// Manage, then a settings row called "Sources by language", from the page
  /// people open in order to add one.
  Future<void> _openInstaller() async {
    final hive = getIt<HiveService>();
    final before = hive.getContentMode();
    await SourceCatalogPage.open(
      context,
      initialItemType: SourceCatalogPage.itemTypeFor(
        ContentMode.values[_tabs.index],
      ),
    );
    if (!mounted) return;
    // "Use" in the catalogue can switch mode. Only then land on the tab of
    // the source now in use; otherwise stay on the tab the viewer came from,
    // where what they just installed is listed. _onTabMoved resets the scope.
    final after = hive.getContentMode();
    if (after == before) return;
    final now = ContentMode.fromId(after).index;
    if (_tabs.index != now) _tabs.index = now;
  }

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
    if (_query.isNotEmpty) return;
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
        // The header floats over the top of the list, so the row is moved
        // down by its height to land below it rather than beneath it.
        if (scroll.hasClients) {
          scroll.jumpTo(
            (scroll.offset - _header.extent.value).clamp(
              0.0,
              scroll.position.maxScrollExtent,
            ),
          );
        }
      });
    });
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
          // The default layout stacks the outgoing and incoming children in a
          // Stack that sizes itself to the LARGER of the two and centres both.
          // These are three whole pages of different heights, so for the
          // length of the crossfade you saw two headers overlapping and the
          // shorter one floating in the middle of the taller one's box — which
          // read as the filter row landing on top of the list. Each child gets
          // the whole body and sits at the top, so the only thing that changes
          // during the switch is opacity.
          layoutBuilder: (current, previous) => Stack(
            alignment: AlignmentDirectional.topStart,
            children: [
              for (final child in previous) Positioned.fill(child: child),
              if (current != null) Positioned.fill(child: current),
            ],
          ),
          child: open != null
              ? _SourceBrowseView(key: ValueKey(open.id), source: open)
              : _hub(),
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
        if (_checker != null)
          ValueListenableBuilder<SourceCheckProgress?>(
            valueListenable: _checking,
            builder: (_, progress, _) => PopupMenuButton<String>(
              tooltip: 'sources.check_all'.tr(),
              enabled: progress == null,
              icon: Icon(
                Icons.health_and_safety_outlined,
                color: _problemsOnly ? AppColors.primary : null,
              ),
              onSelected: _onCheckMenu,
              itemBuilder: (_) => _checkMenu(),
            ),
          ),
        PopupMenuButton<String>(
          onSelected: (v) => v == 'jellyfin'
              ? JellyfinServersPage.open(context)
              : _openExtensions(),
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'manage',
              child: Text('source_manager.manage_repositories'.tr()),
            ),
            PopupMenuItem(
              value: 'jellyfin',
              child: Text('jellyfin.connect_server'.tr()),
            ),
          ],
        ),
      ],
      // Two pills rather than a second row of tabs. Tabs below tabs read as
      // one navigation four levels deep; these two are a switch between what
      // you have and what you could have, and they should not look the same
      // as the modes inside one of them.
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(46),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // The primary action, labelled, in the header that never
                // scrolls away. It opens the catalogue directly; "Manage" next
                // to it is for repositories, DNS and ecosystems.
                Flexible(
                  child: FilledButton.icon(
                    onPressed: _openInstaller,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 16, 0),
                    ),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text(
                      'ext.add_source'.tr(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: _LevelPill(
                    label: 'source_manager.manage'.tr(),
                    active: false,
                    onTap: _openExtensions,
                  ),
                ),
              ],
            ),
          ),
        ),
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
        if (MangaSourceSettingsPage.forProvider(source.id, source.name)
            case final settings?)
          IconButton(
            tooltip: 'general.settings'.tr(),
            icon: const Icon(Icons.tune),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => settings)),
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
      // The mode being left keeps its source for the way back.
      final leaving = hive.getCurrentProvider();
      await hive.rememberProviderForMode(leaving.contentMode.id, leaving);
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
  /// The tab's sources, filtered and sorted, memoised.
  ///
  /// The needle is deliberately NOT part of the cache key and not part of the
  /// sort. It used to be both: every character was a guaranteed miss on all
  /// three tabs, so each keystroke re-ran the whole comparator sort. A
  /// substring filter cannot change the ORDER of what survives it, so the
  /// expensive half — mode filter, sort, language split — is cached once per
  /// (providers, mode, languages) and the needle is applied as a linear pass
  /// over the result in [_narrow].
  _TabSources _tabFor(ProviderLoaded state, ContentMode mode, String needle) =>
      _narrow(_tabBase(state, mode), needle);

  /// The chosen scope, or as much of it as still exists here.
  ///
  /// The scope is shared by three tabs and survives a search, so it routinely
  /// names an ecosystem or a repository the current list does not contain —
  /// changing tab, or typing, is enough. Falling back a level at a time keeps
  /// as much of the choice as still means something: a repo that has vanished
  /// leaves its ecosystem selected, and an ecosystem that has vanished shows
  /// everything. Holding a dead filter would show an empty list and blame the
  /// search for it.
  SourceScope _liveScope(SourceScopeCounts counts) {
    final e = _scope.ecosystem;
    if (e == null) return SourceScope.all;
    if ((counts.byEcosystem[e] ?? 0) == 0) return SourceScope.all;
    final r = _scope.repo;
    if (r == null) return _scope;
    return (counts.byRepo[e]?[r] ?? 0) > 0 ? _scope : SourceScope(ecosystem: e);
  }

  static _TabSources _narrow(_TabSources base, String needle) {
    if (needle.isEmpty) return base;
    bool hit(ProviderEntity p) => p.name.toLowerCase().contains(needle);
    final matched = base.matched.where(hit).toList();
    final unstated = base.unstated.where(hit).toList();
    return _TabSources(
      matched: matched,
      unstated: unstated,
      counts: SourceScopeCounts.of([...matched, ...unstated]),
    );
  }

  _TabSources _tabBase(ProviderLoaded state, ContentMode mode) {
    final languages = _languages;
    final key =
        '${identityHashCode(state.providers)}'
        '|${state.providers.length}|${state.offline}|${mode.id}|${languages.join(',')}';
    final cached = _tabCache[key];
    if (cached != null) return cached;

    final all = [
      for (final p in state.providers)
        if (state.isUsable(p) && p.id.contentMode == mode) p,
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
    //
    // The value tested is displayLang — the one the row's own subtitle shows,
    // and the one the filter menu above was built from. `all` is a declaration
    // and matches every selection; it used to reach the guessing stage, find
    // no hint in "KissKH" or "UHD Movies" and land those two under "language
    // not stated", which is the opposite of what they said about themselves.
    final matched = <ProviderEntity>[];
    final unstated = <ProviderEntity>[];
    for (final p in all) {
      if (languages.isEmpty) {
        matched.add(p);
        continue;
      }
      final lang = p.displayLang;
      if (lang.isEmpty) {
        unstated.add(p);
      } else if (lang == srclang.kAllLanguages ||
          languages.any((l) => srclang.normalizeLang(l) == lang)) {
        matched.add(p);
      }
    }

    final built = _TabSources(
      matched: matched,
      unstated: unstated,
      counts: SourceScopeCounts.of([...matched, ...unstated]),
    );
    // Bounded. With the needle out of the key this is one entry per tab per
    // language selection, so the steady state is three — the wipe that used to
    // trip on the fourth keystroke and throw away the unfiltered lists cannot
    // happen while typing any more.
    if (_tabCache.length > 12) _tabCache.clear();
    _tabCache[key] = built;
    return built;
  }

  /// Tabs and search stay available while optional filters contract on scroll.
  /// The header takes only its measured height; the list owns all remaining space.
  Widget _hub() {
    return ValueListenableBuilder<int>(
      valueListenable: sourceHealth().changes,
      builder: (context, _, _) => _hubBody(),
    );
  }

  Widget _hubBody() {
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
        final needle = _query;
        final tab = _tabFor(state, mode, needle);
        final counts = tab.counts;
        final scope = _liveScope(counts);
        final current = state.currentProviderId;
        final downCount = _problemsOnly
            ? 0
            : _down(tab.matched, scope, current).hidable +
                  _down(tab.unstated, scope, current).hidable;

        return LayoutBuilder(
          builder: (context, constraints) {
            return Column(
              children: [
                AppTabBar(
                  controller: _tabs,
                  onChanged: (_) => setState(() => _scope = SourceScope.all),
                  isScrollable: false,
                  labels: [for (final m in ContentMode.values) m.labelKey.tr()],
                ),
                CheckProgressStrip(
                  progress: _checking,
                  onCancel: () => _checker?.cancel(),
                ),
                // Search stays put: it is how anyone finds one name in a
                // few hundred, so it never scrolls out of reach.
                Row(
                  children: [
                    Expanded(child: _searchField(state, mode)),
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: ValueListenableBuilder<double>(
                        valueListenable: _header.hidden,
                        builder: (context, hidden, _) => IconButton(
                          tooltip: 'sources.filter_type'.tr(),
                          isSelected: !_filtersCollapsed && hidden < 1,
                          onPressed: () {
                            // Scrolled away: bring them back. Showing: fold
                            // them, or unfold them.
                            if (hidden >= 1 && !_filtersCollapsed) {
                              _header.show();
                            } else {
                              setState(
                                () => _filtersCollapsed = !_filtersCollapsed,
                              );
                              _header.show();
                            }
                          },
                          icon: const Icon(Icons.tune_rounded),
                        ),
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: QuickReturnLayout(
                    controller: _header,
                    background: AppColors.background,
                    header: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: constraints.maxHeight * .45,
                      ),
                      child: SingleChildScrollView(
                        child: _filterHeader(counts, scope, downCount),
                      ),
                    ),
                    body: TabBarView(
                      controller: _tabs,
                      children: [
                        for (final m in ContentMode.values)
                          _tabList(state, m, needle),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// The filters under the search field: what floats away on scroll, and
  /// what the tune button folds.
  Widget _filterHeader(
    SourceScopeCounts counts,
    SourceScope scope,
    int downCount,
  ) {
    final health = sourceHealth();
    return AnimatedSize(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 240),
      curve: Curves.easeInOutCubic,
      alignment: Alignment.topCenter,
      child: _filtersCollapsed
          ? const SizedBox(width: double.infinity)
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
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
                SourceScopeMenu(
                  counts: counts,
                  scope: scope,
                  onPick: (picked) => setState(() => _scope = picked),
                ),
                // Nothing to offer while problems-only is on: the lists are
                // meant to hold the down sources then, so a switch that
                // promises to take them away has nothing to take.
                if (!_problemsOnly && (downCount > 0 || health.hideDown))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: HideDownChip(
                        count: downCount,
                        hidden: health.hideDown,
                        onChanged: health.setHideDown,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _searchField(ProviderLoaded state, ContentMode mode) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        controller: _search,
        onChanged: (value) {
          _searchDebounce?.cancel();
          _searchDebounce = Timer(const Duration(milliseconds: 200), () {
            if (!mounted) return;
            setState(() => _query = value.trim().toLowerCase());
          });
        },
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          suffixIcon: PopupMenuButton<String>(
            tooltip: 'profile.all_languages'.tr(),
            onSelected: _filterLanguage,
            itemBuilder: (_) => [
              PopupMenuItem(
                value: '*',
                child: Text('profile.all_languages'.tr()),
              ),
              // Offered from displayLang, not the raw field, because that is
              // what the list below filters on: built from `lang` alone the
              // menu could never offer a language that exists only as an
              // inference, so the several hundred untagged extension sources
              // were unreachable — their language was in their name and the
              // one control that could have used it did not know it was there.
              for (final language
                  in srclang
                      .orderedLanguages(
                        state.providers
                            .where((p) => p.id.contentMode == mode)
                            .map((p) => p.displayLang),
                        _languages,
                      )
                      .where((language) => language != srclang.kAllLanguages))
                CheckedPopupMenuItem(
                  value: language,
                  checked: _languages.contains(language),
                  child: Text(srclang.labelFor(language)),
                ),
            ],
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 144, minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.translate,
                      size: 18,
                      color: _languages.isEmpty
                          ? AppColors.textSecondary
                          : AppColors.primary,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        _languages.isEmpty
                            ? 'profile.all_languages'.tr()
                            : _languages.map(srclang.labelFor).join(', '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    const Icon(Icons.expand_more, size: 16),
                  ],
                ),
              ),
            ),
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
    final scope = _liveScope(tab.counts);
    // Down sources sink rather than vanish unless the user asked: a sweep
    // from a datacenter is not the last word on what works from a phone.
    final matched = _down(tab.matched, scope, state.currentProviderId).rows;
    final unstated = _down(tab.unstated, scope, state.currentProviderId).rows;
    _shownIds = [
      for (final p in [...matched, ...unstated])
        if (state.isUsable(p) && !Catalogue.isId(p.id)) p.id,
    ];

    if (matched.isEmpty && unstated.isEmpty) {
      return Column(
        children: [
          QuickReturnSpacer(controller: _header),
          Expanded(child: _emptyTab(mode, needle)),
        ],
      );
    }

    _alignToCurrent(mode, matched, state.currentProviderId);
    return _list(mode, scope, matched, unstated, state);
  }

  Widget _emptyTab(ContentMode mode, String needle) {
    return _Message(
      text: needle.isEmpty && _languages.isEmpty
          ? 'mode.none_installed'.tr(args: [mode.labelKey.tr()])
          : 'profile.no_providers_in_category'.tr(),
      hint: needle.isEmpty ? _modeHint(mode) : null,
      // An empty mode is a dead end without this. Manga and novels are both
      // extension ecosystems, so a fresh install has nothing in either tab
      // and the only way out is a gear icon the message never mentions.
      // Straight to the catalogue on this tab's kind; an empty tab is
      // exactly when somebody wants to add, not to manage.
      actionLabel: needle.isEmpty ? 'ext.add_source'.tr() : null,
      onAction: needle.isEmpty ? _openInstaller : null,
    );
  }

  Widget _list(
    ContentMode mode,
    SourceScope scope,
    List<ProviderEntity> matched,
    List<ProviderEntity> unstated,
    ProviderLoaded state,
  ) {
    return CustomScrollView(
      // No needle in the key. A changed key destroys the element and builds a
      // new one, so every character tore down all three lists: the scroll
      // position reset to zero and every visible row's entrance animation
      // started again — around three dozen AnimationControllers and timers per
      // keystroke. That is the list "flashing" while you type.
      key: PageStorageKey(
        'sources|${mode.id}|${scope.ecosystem}|${scope.repo}|'
        '${_languages.join(",")}',
      ),
      controller: _scrolls[mode],
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        QuickReturnSpacer.sliver(_header),
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
      itemBuilder: (_, i) => ItemAppear(
        index: i,
        child: _SourceTile(
          key: rows[i].id == state.currentProviderId
              ? _currentRows[mode]
              : null,
          source: rows[i],
          health: _badgeFor(rows[i]),
          deviceVerdict: _deviceBadgeFor(rows[i]),
          current: rows[i].id == state.currentProviderId,
          onTap: () => _use(rows[i]),
          onBrowse: () => setState(() => _open = rows[i]),
          onLongPress: _checker == null || Catalogue.isId(rows[i].id)
              ? null
              : () => showSourceCheckSheet(
                  context,
                  id: rows[i].id,
                  name: rows[i].name,
                ),
        ),
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
    this.onLongPress,
    this.current = false,
    this.health,
    this.deviceVerdict,
  });

  final ProviderEntity source;
  final RemoteVerdict? health;

  /// What a check from this phone found, when it is something the server's
  /// badge cannot express. See [deviceBadge].
  final SourceVerdict? deviceVerdict;

  /// Whether this is the currently selected source.
  final bool current;
  final VoidCallback onTap;
  final VoidCallback onBrowse;

  /// What this phone knows about the source, and a check on demand.
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    // The row says the same language the filter menu offers and the split
    // above sorts by. `all` is left out on purpose: "this catalogue is in
    // every language" is not something a two-letter chip can say, and the row
    // appears under every selection anyway.
    final lang = source.displayLang;
    final subtitle = [
      if (lang.isNotEmpty && lang != srclang.kAllLanguages)
        srclang.shortLabelFor(lang),
      if (source.category.isNotEmpty) source.category,
      if (source.browseOnly) 'profile.provider'.tr(),
    ].join(' · ');

    return HoverTap(
      onTap: onTap,
      onLongPress: onLongPress,
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
            Opacity(
              opacity: health?.state == RemoteHealth.dead ? 0.45 : 1,
              child: _SourceMark(url: source.image, size: 40),
            ),
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
                      if (health != null) ...[
                        const SizedBox(width: 6),
                        SourceHealthBadge(
                          verdict: health!,
                          sourceName: source.name,
                          sourceId: source.id,
                        ),
                      ] else if (deviceVerdict != null) ...[
                        const SizedBox(width: 6),
                        DeviceVerdictBadge(
                          verdict: deviceVerdict!,
                          sourceId: source.id,
                          sourceName: source.name,
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
              memCacheWidth: (size * 3).round(),
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

  /// How many sources sit in each ecosystem, and in each repository inside
  /// one — what the scope menu is built from.
  final SourceScopeCounts counts;
}

/// One of the two things this screen is: what you have, or what you could
/// have.
class _LevelPill extends StatelessWidget {
  const _LevelPill({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      child: Material(
        color: active ? AppColors.primary : AppColors.card,
        borderRadius: BorderRadius.circular(999),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: active ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            child: Text(
              label,
              style: TextStyle(
                color: active ? Colors.white : AppColors.textSecondary,
                fontSize: 13,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
