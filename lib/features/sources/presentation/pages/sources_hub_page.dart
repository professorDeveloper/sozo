import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:soplay/core/content/content_mode.dart';
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
import 'package:soplay/features/extensions/presentation/pages/mangayomi_sources_page.dart';
import 'package:soplay/features/profile/presentation/pages/sources_page.dart';
import 'package:soplay/features/sources/data/source_browse_repository.dart';
import 'package:soplay/features/sources/domain/source_ecosystem.dart';
import 'package:soplay/features/sources/domain/source_failure.dart';
import 'package:soplay/features/sources/domain/source_index.dart';

/// Every source in one place, grouped by what it carries, browsable in place.
///
/// The screen this replaces was a settings list: an "Active source" row that
/// opened a picker, and below it a row per extension ecosystem that pushed you
/// somewhere else. Choosing a source there meant becoming that source and
/// landing back on Home, so there was no way to look at what a source has
/// without committing to it — the reported shape of that was having to go to
/// settings every time.
///
/// Here the three kinds are tabs, because [ContentMode] already knows which
/// source is which, and tapping one opens its catalogue inside this page. The
/// app's active source does not move: cards carry their own provider to
/// `/detail`, the way cross-search already does.
class SourcesHubPage extends StatefulWidget {
  const SourcesHubPage({super.key});

  @override
  State<SourcesHubPage> createState() => _SourcesHubPageState();
}

class _SourcesHubPageState extends State<SourcesHubPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: ContentMode.values.length,
    vsync: this,
  );
  final TextEditingController _search = TextEditingController();

  /// The source being browsed, or null while the list is showing. Held here
  /// rather than pushed as a route so "back" returns to the list this page is,
  /// which is what "from that one page" means.
  ProviderEntity? _open;

  /// The list is addressed by index so returning from a source lands where it
  /// did. It used to carry an A–Z strip as well; the strip is gone — eleven
  /// chips in a row above a search box that already finds anything by name
  /// bought one gesture and cost a band of the screen.
  final ItemScrollController _listCtl = ItemScrollController();
  final ItemPositionsListener _listPos = ItemPositionsListener.create();

  /// Where each tab was left, so returning from a source lands where it did.
  /// PageStorage cannot do this for a positioned list — it restores by offset,
  /// and this one is addressed by index.
  final Map<String, int> _restore = {};

  /// See [_tabFor].
  final Map<String, _TabSources> _tabCache = {};

  /// null is "all". Which runtime a source comes from is the axis people
  /// actually filter on here — "the one I added from CloudStream" — and it was
  /// visible only as a word in grey under each of several hundred names.
  SourceEcosystem? _eco;

  @override
  void initState() {
    super.initState();
    _listPos.itemPositions.addListener(_onScrolled);
  }

  /// The first row actually on screen is what gets restored on the way back.
  void _onScrolled() {
    final positions = _listPos.itemPositions.value;
    if (positions.isEmpty) return;
    final first = positions
        .where((p) => p.itemTrailingEdge > 0)
        .fold<int?>(null, (a, p) => a == null || p.index < a ? p.index : a);
    if (first == null) return;
    _restore[ContentMode.values[_tabs.index].id] = first;
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
    _listPos.itemPositions.removeListener(_onScrolled);
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  void _close() => setState(() => _open = null);

  /// Installing and removing extensions is a different job from browsing them,
  /// and it keeps its own screen.
  void _openExtensions() => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const SourcesPage()),
      );

  /// Where an empty tab sends somebody who wants to fill it.
  ///
  /// Manga and novels come from one ecosystem — the JavaScript extensions —
  /// and its screen is the one carrying the recommended repos that actually
  /// publish a novel index. Sending them to the generic list instead would be
  /// one more hop to the same place.
  void _openInstaller(ContentMode mode) {
    if (mode == ContentMode.video) {
      _openExtensions();
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const MangayomiSourcesPage()),
    );
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
        appBar: open == null ? _listBar() : _browseBar(open),
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: open == null
              ? _list()
              : _SourceBrowseView(key: ValueKey(open.id), source: open),
        ),
      ),
    );
  }

  PreferredSizeWidget _listBar() {
    return AppBar(
      backgroundColor: AppColors.background,
      title: Text('profile.sources_title'.tr()),
      actions: [
        // Labelled, not a sliders icon with a tooltip nobody long-presses.
        // Installing a source is the reason most people open this screen, and
        // it was the one thing on it with no words — indistinguishable from a
        // settings button, which is what a tune icon means everywhere else.
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: TextButton.icon(
            onPressed: _openExtensions,
            icon: const Icon(Icons.add_rounded, size: 20),
            label: Text('manga.add_source'.tr()),
          ),
        ),
      ],
      bottom: AppTabBar(
        controller: _tabs,
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
          Expanded(
            child: Text(source.name, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      actions: [
        // Here, and not on the list row: this is the moment the decision gets
        // made, with what the source actually carries on the screen behind it.
        BlocBuilder<ProviderBloc, ProviderState>(
          builder: (context, state) {
            final current = state is ProviderLoaded &&
                state.currentProviderId == source.id;
            return Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: TextButton(
                onPressed: current ? null : () => _use(source),
                child: Text(
                  current ? 'ux.in_use'.tr() : 'ux.use_source'.tr(),
                ),
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
    final key = '${identityHashCode(state.providers)}'
        '|${state.providers.length}|${mode.id}|$needle';
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

    final built = _TabSources(
      all: all,
      present: {for (final p in all) SourceEcosystem.of(p.id)},
    );
    // Bounded: three tabs times a few search terms, and a new provider list
    // changes the key anyway. Cleared wholesale rather than aged out, because
    // the cost of a miss is one sort.
    if (_tabCache.length > 12) _tabCache.clear();
    _tabCache[key] = built;
    return built;
  }

  Widget _list() {
    return BlocBuilder<ProviderBloc, ProviderState>(
      builder: (context, state) {
        if (state is ProviderError) {
          return _Message(text: 'profile.providers_error'.tr());
        }
        if (state is! ProviderLoaded) {
          return const Center(child: CircularProgressIndicator());
        }
        final mode = ContentMode.values[_tabs.index];
        final needle = _search.text.trim().toLowerCase();
        final tab = _tabFor(state, mode, needle);
        final present = tab.present;
        final eco = present.contains(_eco) ? _eco : null;
        final sources = eco == null
            ? tab.all
            : [
                for (final p in tab.all)
                  if (SourceEcosystem.of(p.id) == eco) p,
              ];

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  hintText: 'profile.search_providers_hint'.tr(),
                  filled: true,
                  fillColor: AppColors.card,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            if (present.length > 1)
              _EcosystemFilter(
                present: present,
                active: eco,
                onPick: (picked) => setState(() => _eco = picked),
              ),
            Expanded(
              child: sources.isEmpty
                  ? _Message(
                      text: needle.isEmpty
                          ? 'mode.none_installed'.tr(args: [mode.labelKey.tr()])
                          : 'profile.no_providers_in_category'.tr(),
                      hint: needle.isEmpty ? _modeHint(mode) : null,
                      // An empty mode is a dead end without this. Manga and
                      // novels are both extension ecosystems, so a fresh
                      // install has nothing in either tab and the only way out
                      // is a gear icon the message never mentions.
                      actionLabel: needle.isEmpty ? 'manga.add_source'.tr() : null,
                      onAction: needle.isEmpty ? () => _openInstaller(mode) : null,
                    )
                  : ScrollablePositionedList.separated(
                      itemScrollController: _listCtl,
                      itemPositionsListener: _listPos,
                      // Going into a source and back rebuilt this list from
                      // nothing, so a tap forty rows down returned to the top.
                      initialScrollIndex: _restore[mode.id] ?? 0,
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                      itemCount: sources.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _SourceTile(
                        source: sources[i],
                        current: sources[i].id == state.currentProviderId,
                        onTap: () => setState(() => _open = sources[i]),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.source,
    required this.onTap,
    this.current = false,
  });

  final ProviderEntity source;

  /// The app's source right now. Marked, not made un-tappable: tapping still
  /// browses, which is what every other row here does.
  final bool current;
  final VoidCallback onTap;

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
                        Icon(Icons.check_rounded,
                            size: 16, color: AppColors.primary),
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
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textSecondary,
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
          for (final s in data?.sections ?? const []) if (s.items.isNotEmpty) s,
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


/// Which runtime a source comes from, as a row of chips.
///
/// Only the ecosystems this tab actually contains: a fresh install has no
/// CloudStream plugins, and a chip that filters to nothing is a chip that
/// teaches people the filter is broken.
class _EcosystemFilter extends StatelessWidget {
  const _EcosystemFilter({
    required this.present,
    required this.active,
    required this.onPick,
  });

  final Set<SourceEcosystem> present;
  final SourceEcosystem? active;
  final ValueChanged<SourceEcosystem?> onPick;

  @override
  Widget build(BuildContext context) {
    final chips = <SourceEcosystem?>[
      null,
      for (final e in SourceEcosystem.values)
        if (present.contains(e)) e,
    ];
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final e = chips[i];
          final selected = e == active;
          return Center(
            child: Material(
              color: selected ? AppColors.primary : AppColors.card,
              borderRadius: BorderRadius.circular(10),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onPick(e),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Text(
                    e?.label ?? 'sources.eco_all'.tr(),
                    style: TextStyle(
                      color: selected ? Colors.white : AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
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


/// One tab's sources, and which ecosystems are in them.
class _TabSources {
  const _TabSources({required this.all, required this.present});

  final List<ProviderEntity> all;
  final Set<SourceEcosystem> present;
}
