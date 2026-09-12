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

  /// Jumping to a letter, the way the episode list jumps to a range.
  ///
  /// With CloudStream installed this tab is several hundred rows of
  /// alphabetically sorted names, and the only way to reach the middle was to
  /// keep swiping. Search finds a source somebody can already name; the index
  /// is for the far more common case of looking for one you cannot.
  final ItemScrollController _listCtl = ItemScrollController();
  final ItemPositionsListener _listPos = ItemPositionsListener.create();

  /// Where each tab was left, so returning from a source lands where it did.
  /// PageStorage cannot do this for a positioned list — it restores by offset,
  /// and this one is addressed by index.
  final Map<String, int> _restore = {};
  String _activeLetter = '';

  /// Below this the strip is chrome over a list that already fits a swipe.
  static const int _indexThreshold = 25;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) return;
      setState(() => _activeLetter = '');
    });
    _listPos.itemPositions.addListener(_onScrolled);
  }

  /// The first row actually on screen decides the active letter, and is what
  /// gets restored on the way back.
  void _onScrolled() {
    final positions = _listPos.itemPositions.value;
    if (positions.isEmpty) return;
    final first = positions
        .where((p) => p.itemTrailingEdge > 0)
        .fold<int?>(null, (a, p) => a == null || p.index < a ? p.index : a);
    if (first == null) return;
    _restore[ContentMode.values[_tabs.index].id] = first;
    final letter = _letterAt(first);
    if (letter == _activeLetter) return;
    setState(() => _activeLetter = letter);
  }

  /// Set by [_list] each build so the scroll listener can read it without
  /// rebuilding the whole page to find out which names are on screen.
  List<ProviderEntity> _shown = const [];

  String _letterAt(int i) =>
      i >= 0 && i < _shown.length ? _letterOf(_shown[i]) : '';

  static String _letterOf(ProviderEntity p) => indexLetterOf(p.name);

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
        IconButton(
          tooltip: 'profile.section_extensions'.tr(),
          icon: const Icon(Icons.tune_rounded),
          onPressed: _openExtensions,
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
        final sources = [
          for (final p in state.providers)
            if (state.isUsable(p) &&
                p.id.contentMode == mode &&
                (needle.isEmpty || p.name.toLowerCase().contains(needle)))
              p,
        ];

        _shown = sources;
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
            if (sources.length >= _indexThreshold)
              _LetterIndex(
                letters: [
                  for (final p in sources) _letterOf(p),
                ],
                active: _activeLetter,
                onPick: (letter) {
                  final i = sources.indexWhere((p) => _letterOf(p) == letter);
                  if (i < 0 || !_listCtl.isAttached) return;
                  _listCtl.scrollTo(
                    index: i,
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                  );
                },
              ),
            Expanded(
              child: sources.isEmpty
                  ? _Message(
                      text: needle.isEmpty
                          ? 'mode.none_installed'.tr(args: [mode.labelKey.tr()])
                          : 'profile.no_providers_in_category'.tr(),
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

/// The letters present, in order, as a strip you can jump from.
///
/// Modelled on the episode list's range chips: the same idea that a long list
/// needs somewhere to aim at, with the same rule that a chip only exists when
/// there is something behind it.
class _LetterIndex extends StatelessWidget {
  const _LetterIndex({
    required this.letters,
    required this.active,
    required this.onPick,
  });

  /// One entry per row, in row order — the widget takes the distinct set.
  final List<String> letters;
  final String active;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final distinct = indexLetters(letters);
    if (distinct.length < 2) return const SizedBox.shrink();

    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: distinct.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final letter = distinct[i];
          final on = letter == active;
          return HoverTap(
            onTap: () => onPick(letter),
            child: Container(
              alignment: Alignment.center,
              constraints: const BoxConstraints(minWidth: 30),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: on ? AppColors.primary : AppColors.card,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                letter,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                  color: on ? Colors.white : AppColors.textSecondary,
                ),
              ),
            ),
          );
        },
      ),
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
          final text = error is SourceBrowseException && error.message != null
              ? error.message!
              : 'search.source_failed'.tr();
          return _Message(
            text: text,
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
  const _Message({required this.text, this.actionLabel, this.onAction});

  final String text;
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
