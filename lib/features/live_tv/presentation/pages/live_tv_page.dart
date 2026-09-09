import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/system/platform_utils.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/detail/domain/entities/player_args.dart';
import 'package:soplay/features/home/presentation/widgets/home_shared_widgets.dart';
import 'package:soplay/features/live_tv/data/live_tv_service.dart';
import 'package:soplay/features/live_tv/presentation/widgets/channel_sheet.dart';

const double _kGutter = 14;
const double _kSpacing = 10;

int _columnsFor(double width) => width >= 900 ? 5 : (width >= 620 ? 4 : 3);

/// Width factor for a channel card's progress hairline, or null for no bar.
///
/// The 0.02 floor stops a slot that started a minute ago rendering as a
/// zero-width sliver, which reads as a paint bug rather than as a beginning.
double? _barFactor(LiveProgramme? slot, DateTime at) {
  if (slot == null || !slot.isBarWorthy) return null;
  final value = slot.progressAt(at); // already clamped to 0..1 by the model
  if (value <= 0) return null;
  return value < 0.02 ? 0.02 : value;
}

/// Live TV.
///
/// A line-up rather than a catalogue: channels are picked in a second, so the
/// screen is built for scanning — logo-forward cards, categories across the
/// top, and the ones you actually watch pinned above everything else.
class LiveTvPage extends StatefulWidget {
  /// True when mounted as a tab rather than pushed: a tab is already at the
  /// root of its stack, so it gets no back arrow and keeps its own bottom
  /// padding clear of the nav bar.
  const LiveTvPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<LiveTvPage> createState() => _LiveTvPageState();
}

class _LiveTvPageState extends State<LiveTvPage> {
  final LiveTvService _service = getIt<LiveTvService>();
  final _search = TextEditingController();
  final _scroll = ScrollController();

  List<LiveFolder> _folders = const [];
  List<LiveCountry> _countries = const [];
  List<LiveChannel> _channels = const [];
  Set<String> _favourites = <String>{};
  List<String> _recent = const [];
  Map<String, Map<String, String>> _cards = {};

  /// Pinned channels, rebuilt only when the pins change — never in build().
  List<LiveChannel> _favouriteCards = const [];
  List<LiveChannel> _recentCards = const [];

  /// The folder being read, or empty for the top level.
  String _folder = '';

  /// The country being read, or empty. Mutually exclusive with [_folder] —
  /// they are two ways of asking the same question and combining them produces
  /// a screen nobody navigated to.
  String _country = '';
  String _query = '';
  Timer? _debounce;
  Timer? _ticker;

  int _page = 1;
  bool _hasMore = false;

  /// How many channels the OPEN scope has, as browse reports it.
  int _total = 0;

  /// The whole line-up, summed from the folder counts. A different number with
  /// a different meaning, and the one the Categories header wants.
  int _indexTotal = 0;

  /// The index request has finished, succeeded or not.
  bool _booted = false;
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;

  /// Request generation. Bumped by every scope change, and checked after every
  /// await, so a response for a folder the user already left is dropped.
  int _seq = 0;

  /// One "now" per tick, so every bar and slot line on screen agrees.
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    final hive = getIt<HiveService>();
    _favourites = hive.getLiveTvFavourites().toSet();
    _recent = hive.getLiveTvRecent();
    _cards = hive.getLiveTvCards();
    _rebuildPins();
    _scroll.addListener(_onScroll);
    _ticker = Timer.periodic(const Duration(seconds: 60), _onTick);
    _loadIndex();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ticker?.cancel();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onTick(Timer _) {
    if (!mounted) return;
    // The tab lives inside main_page's IndexedStack for the whole session, so
    // this refuses to rebuild anything that has no bar on it.
    if (!_scoped) return;
    if (!_channels.any((c) => c.now != null)) return;
    setState(() => _now = DateTime.now());
  }

  /// True while a folder, a country or a search is open — i.e. whenever the
  /// screen is showing channels rather than the line-up's index.
  bool get _scoped =>
      _folder.isNotEmpty || _country.isNotEmpty || _query.trim().isNotEmpty;

  bool get _searching => _query.trim().isNotEmpty;

  String get _scopeName {
    if (_folder.isNotEmpty) return _folder;
    if (_country.isNotEmpty) return _countryName(_country);
    return 'live_tv.results'.tr();
  }

  Future<void> _loadIndex({bool silent = false}) async {
    if (!silent) setState(() => _error = null);
    try {
      final index = await _service.index();
      if (!mounted) return;
      // Ordered here, once, and by the same rule for both strips: the line-up
      // leads with what it actually carries.
      final folders = [...index.folders]
        ..sort((a, b) => b.count.compareTo(a.count));
      final countries = [...index.countries]
        ..sort((a, b) => b.count.compareTo(a.count));
      setState(() {
        _folders = folders;
        _countries = countries;
        _indexTotal = folders.fold(0, (n, f) => n + f.count);
        _booted = true;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _booted = true;
        _error = 'live_tv.load_failed'.tr();
      });
    }
  }

  /// One page of channels for the open scope.
  Future<void> _loadPage({bool append = false, bool silent = false}) async {
    if (append && (_loadingMore || !_hasMore)) return;
    final seq = ++_seq;
    setState(() {
      if (append) {
        _loadingMore = true;
      } else {
        if (!silent) _loading = true;
        _error = null;
      }
    });
    final page = append ? _page + 1 : 1;
    try {
      final result = await _service.browse(
        category: _folder.isEmpty ? null : _folder,
        country: _country.isEmpty ? null : _country,
        search: _query,
        page: page,
      );
      if (!mounted || seq != _seq) return;
      setState(() {
        // Appended by id, not blindly concatenated. A page boundary is where a
        // channel added or removed between two requests shifts everything after
        // it, and the same row arriving twice would render two cards for one
        // channel — and, since the grid keys on the id, throw on the duplicate
        // key rather than merely look wrong.
        _channels = append
            ? _mergeChannels(_channels, result.channels)
            : result.channels;
        _page = result.page;
        _hasMore = result.hasMore;
        _total = result.total;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
      _rememberCards(result.channels);
    } catch (_) {
      if (!mounted || seq != _seq) return;
      final hasContent = _channels.isNotEmpty;
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (!hasContent) _error = 'live_tv.load_failed'.tr();
      });
      // With a grid already on screen there is nowhere to put an error state,
      // and stopping without a word looks like the list simply ended.
      if (hasContent) _toast('live_tv.load_failed'.tr());
    }
  }

  /// Existing channels plus whatever is new, in arrival order.
  ///
  /// Deliberately keeps the copy already on screen for anything seen twice: a
  /// card the user is looking at must not be replaced under them by an
  /// identical one, and there is nothing in a later copy worth having.
  static List<LiveChannel> _mergeChannels(
    List<LiveChannel> current,
    List<LiveChannel> incoming,
  ) {
    final seen = {for (final c in current) c.id};
    return [
      ...current,
      for (final c in incoming)
        if (seen.add(c.id)) c,
    ];
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Pull to refresh. Silent because RefreshIndicator draws its own spinner and
  /// raising [_loading] would swap the grid for skeletons underneath it.
  Future<void> _refresh() =>
      _scoped ? _loadPage(silent: true) : _loadIndex(silent: true);

  /// Everything a scope change must forget. Always called inside a setState.
  void _resetPaging() {
    _page = 1;
    _hasMore = false;
    _total = 0;
    _error = null;
    _channels = const [];
  }

  void _openFolder(String name) {
    setState(() {
      _folder = name;
      _country = '';
      _resetPaging();
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _loadPage();
  }

  void _openCountry(String code) {
    setState(() {
      _country = code;
      _folder = '';
      _resetPaging();
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _loadPage();
  }

  void _closeScope() {
    _debounce?.cancel();
    _search.clear();
    _seq++; // drop anything already in flight for the scope being left
    setState(() {
      _folder = '';
      _country = '';
      _query = '';
      _resetPaging();
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  /// Searching goes to the server, so it waits for a pause in the typing.
  void _onQueryChanged(String value) {
    _debounce?.cancel();
    setState(() {
      _query = value;
      _resetPaging();
    });
    if (value.trim().isEmpty) {
      if (_folder.isEmpty && _country.isEmpty) {
        _seq++; // back to the top level; nothing to fetch, nothing in flight
        return;
      }
      // Still inside a folder or a country: the scope itself is what to show.
      _loadPage();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), _loadPage);
  }

  /// The next page, once the list is close enough to its end to need one.
  void _onScroll() {
    if (!_scroll.hasClients || !_scoped) return;
    if (_loading || _loadingMore || !_hasMore) return;
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - 600) {
      _loadPage(append: true);
    }
  }

  /// Rebuilds the two pinned rails from the saved cards.
  void _rebuildPins() {
    final favourites = <LiveChannel>[];
    for (final id in _favourites) {
      final channel = _fromCard(id);
      if (channel != null) favourites.add(channel);
    }
    final recents = <LiveChannel>[];
    for (final id in _recent) {
      if (_favourites.contains(id)) continue;
      final channel = _fromCard(id);
      if (channel != null) recents.add(channel);
    }
    _favouriteCards = favourites.take(12).toList(growable: false);
    _recentCards = recents.take(12).toList(growable: false);
  }

  /// Keeps enough of the pinned channels to draw them without their page.
  void _rememberCards(List<LiveChannel> seen) {
    final wanted = {..._favourites, ..._recent};
    var changed = false;
    for (final channel in seen) {
      if (!wanted.contains(channel.id)) continue;
      final card = _cardOf(channel);
      if (_cards[channel.id]?.toString() == card.toString()) continue;
      _cards[channel.id] = card;
      changed = true;
    }
    // Only what is still pinned; a cache that only grows is a leak with a nicer
    // name.
    final before = _cards.length;
    _cards.removeWhere((id, _) => !wanted.contains(id));
    if (_cards.length != before) changed = true;
    if (!changed) return;
    getIt<HiveService>().setLiveTvCards(_cards);
    if (!mounted) return;
    setState(_rebuildPins);
  }

  /// A country code as something readable, in English.
  ///
  /// English because the channel names beside it are: a strip reading
  /// "O'zbekiston · Rossiya" above a grid of "Pluto TV Comedy" and "Al Jazeera"
  /// is two languages doing one job. Only the countries this line-up actually
  /// carries are named; anything else keeps its code, which still beats a blank.
  static const Map<String, String> _countryNames = {
    'UZ': 'Uzbekistan',
    'RU': 'Russia',
    'TR': 'Turkey',
    'KZ': 'Kazakhstan',
    'KG': 'Kyrgyzstan',
    'TJ': 'Tajikistan',
    'TM': 'Turkmenistan',
    'AZ': 'Azerbaijan',
    'US': 'United States',
    'UK': 'United Kingdom',
    'GB': 'United Kingdom',
    'CA': 'Canada',
    'AU': 'Australia',
    'DE': 'Germany',
    'FR': 'France',
    'ES': 'Spain',
    'IT': 'Italy',
    'QA': 'Qatar',
    'AE': 'UAE',
    'SA': 'Saudi Arabia',
    'CN': 'China',
    'JP': 'Japan',
    'KR': 'South Korea',
    'IN': 'India',
    'SG': 'Singapore',
    'IL': 'Israel',
    'AT': 'Austria',
    'SK': 'Slovakia',
    'SE': 'Sweden',
    'NL': 'Netherlands',
    'PL': 'Poland',
    'UA': 'Ukraine',
    'GE': 'Georgia',
    'BR': 'Brazil',
    'MX': 'Mexico',
  };

  String _countryName(String code) =>
      _countryNames[code.toUpperCase()] ?? code.toUpperCase();

  /// The flag for an ISO country code, built from regional-indicator letters.
  ///
  /// A picture rather than two letters, and no asset to ship or fail to load.
  String _flagOf(String code) {
    final c = code.toUpperCase();
    if (c.length != 2 || !RegExp(r'^[A-Z]{2}$').hasMatch(c)) return '';
    return String.fromCharCodes([
      0x1F1E6 + c.codeUnitAt(0) - 0x41,
      0x1F1E6 + c.codeUnitAt(1) - 0x41,
    ]);
  }

  /// Everything needed to draw and PLAY a pinned channel without its page.
  ///
  /// `headers` rides along encoded, because a favourite is opened straight from
  /// this cache: dropping them here meant a header-gated channel worked the
  /// first time and 403'd every time after it was pinned.
  Map<String, String> _cardOf(LiveChannel channel) => {
    'name': channel.name,
    'streamUrl': channel.streamUrl,
    'logoUrl': channel.logoUrl ?? '',
    'category': channel.category,
    if (channel.headers.isNotEmpty) 'headers': jsonEncode(channel.headers),
  };

  LiveChannel? _fromCard(String id) {
    final card = _cards[id];
    if (card == null) return null;
    final url = card['streamUrl'] ?? '';
    final name = card['name'] ?? '';
    if (url.isEmpty || name.isEmpty) return null;
    Map<String, String> headers = const {};
    final raw = card['headers'];
    if (raw != null && raw.isNotEmpty) {
      try {
        headers = (jsonDecode(raw) as Map).map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        );
      } catch (_) {
        // A card written by an older build, or corrupted. Playing without the
        // headers is worth trying; refusing to draw the channel is not.
      }
    }
    return LiveChannel(
      id: id,
      name: name,
      streamUrl: url,
      logoUrl: (card['logoUrl'] ?? '').isEmpty ? null : card['logoUrl'],
      category: card['category'] ?? '',
      headers: headers,
    );
  }

  void _toggleFavourite(LiveChannel channel) {
    setState(() {
      if (!_favourites.remove(channel.id)) {
        _favourites.add(channel.id);
        _cards[channel.id] = _cardOf(channel);
      }
      _rebuildPins();
    });
    final hive = getIt<HiveService>();
    hive.setLiveTvFavourites(_favourites.toList());
    hive.setLiveTvCards(_cards);
  }

  void _play(LiveChannel channel) {
    final hive = getIt<HiveService>();
    hive.pushLiveTvRecent(channel.id);
    _cards[channel.id] = _cardOf(channel);
    hive.setLiveTvCards(_cards);
    setState(() {
      _recent = [channel.id, ..._recent.where((e) => e != channel.id)]
          .take(12)
          .toList();
      _rebuildPins();
    });
    context.push(
      '/player',
      extra: PlayerArgs(
        title: channel.name,
        provider: 'live',
        // Some broadcast CDNs 403 anything that does not present the
        // User-Agent or Referer they expect. The server records which channels
        // those are; sending an empty map made them look dead.
        headers: channel.headers,
        movieUrl: channel.streamUrl,
        thumbnail: channel.logoUrl,
        // Live has no episodes and nothing to resume to, and offering a
        // download for a stream with no end would be a lie.
        type: 'live',
        // Lets the player open this channel's guide without going back out to
        // the channel list to find it.
        liveChannelId: channel.id,
        showDownloadAction: false,
      ),
    );
  }

  Future<void> _openSheet(LiveChannel channel) {
    return showChannelSheet(
      context: context,
      channel: channel,
      favourite: _favourites.contains(channel.id),
      onPlay: () => _play(channel),
      onToggleFavourite: () => _toggleFavourite(channel),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        automaticallyImplyLeading: !widget.embedded,
        titleSpacing: widget.embedded ? _kGutter : null,
        // Inside a folder, a country or a search, back closes the scope rather
        // than the screen; outside one this is null and the usual leading
        // behaviour applies.
        leading: _scoped
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded, size: 22),
                color: AppColors.textPrimary,
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: _closeScope,
              )
            : null,
        title: Text(
          'live_tv.title'.tr(),
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
        ),
      ),
      body: SafeArea(
        // Inside the SafeArea and outside the RefreshIndicator, so the width
        // every grid divides up is the real content width — a notch in
        // landscape makes it several points narrower than the screen.
        child: LayoutBuilder(
          builder: (context, constraints) => RefreshIndicator(
            color: AppColors.primary,
            backgroundColor: AppColors.surface,
            onRefresh: _refresh,
            child: CustomScrollView(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: _slivers(constraints.maxWidth),
            ),
          ),
        ),
      ),
    );
  }

  /// Every state of this screen is a sliver under the search field, so the
  /// field is never unmounted underneath somebody's typing.
  List<Widget> _slivers(double width) {
    return [
      _searchSliver(),
      if (_scoped) ..._scopedSlivers(width) else ..._topSlivers(width),
      SliverToBoxAdapter(child: SizedBox(height: widget.embedded ? 96 : 28)),
    ];
  }

  Widget _searchSliver() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(_kGutter, 8, _kGutter, 10),
        child: TextField(
          controller: _search,
          onChanged: _onQueryChanged,
          textInputAction: TextInputAction.search,
          style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
          // Fill, padding and radius all come from inputDecorationTheme, so
          // this field is the same field as every other one in the app.
          decoration: InputDecoration(
            hintText: (_folder.isEmpty && _country.isEmpty)
                ? 'live_tv.search_hint'.tr()
                : 'live_tv.search_in'.tr(namedArgs: {'folder': _scopeName}),
            prefixIcon: const Icon(
              Icons.search_rounded,
              size: 20,
              color: AppColors.textSecondary,
            ),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                    onPressed: () {
                      _search.clear();
                      _onQueryChanged('');
                    },
                  ),
          ),
        ),
      ),
    );
  }

  List<Widget> _topSlivers(double width) {
    final indexEmpty = _booted && _folders.isEmpty;

    return [
      if (_recentCards.isNotEmpty) ...[
        _SectionHeader(
          icon: Icons.history_rounded,
          label: 'live_tv.recent'.tr(),
        ),
        _PinRail(
          channels: _recentCards,
          favourites: _favourites,
          onPlay: _play,
          onMore: _openSheet,
        ),
      ],
      if (_favouriteCards.isNotEmpty) ...[
        _SectionHeader(
          icon: Icons.star_rounded,
          label: 'live_tv.favourites'.tr(),
        ),
        _PinRail(
          channels: _favouriteCards,
          favourites: _favourites,
          onPlay: _play,
          onMore: _openSheet,
        ),
      ],
      if (_booted &&
          _recentCards.isEmpty &&
          _favouriteCards.isEmpty &&
          _folders.isNotEmpty)
        const _HintLine(),
      if (indexEmpty)
        SliverFillRemaining(
          hasScrollBody: false,
          child: _Empty(
            icon: _error != null
                ? Icons.cloud_off_rounded
                : Icons.live_tv_rounded,
            text: _error ?? 'live_tv.empty'.tr(),
            actionLabel: 'live_tv.retry'.tr(),
            onAction: () => _loadIndex(),
          ),
        )
      else ...[
        _SectionHeader(
          icon: Icons.grid_view_rounded,
          label: 'live_tv.categories'.tr(),
          trailing: _indexTotal > 0
              ? 'live_tv.channel_count'.plural(_indexTotal)
              : null,
        ),
        if (!_booted)
          _CategorySkeleton(width: width)
        else
          _CategoryGrid(folders: _folders, width: width, onOpen: _openFolder),
        if (!_booted || _countries.isNotEmpty) ...[
          _SectionHeader(
            icon: Icons.public_rounded,
            label: 'live_tv.countries'.tr(),
          ),
          if (!_booted)
            const _CountryRailSkeleton()
          else
            _CountryRail(
              countries: _countries,
              nameOf: _countryName,
              flagOf: _flagOf,
              onOpen: _openCountry,
            ),
        ],
      ],
    ];
  }

  List<Widget> _scopedSlivers(double width) {
    return [
      _ScopeLine(
        name: _scopeName,
        total: _total,
        showTotal: _channels.isNotEmpty,
      ),
      if (_loading && _channels.isEmpty)
        _GridSkeleton(width: width, count: 9)
      else if (_error != null && _channels.isEmpty)
        SliverFillRemaining(
          hasScrollBody: false,
          child: _Empty(
            icon: Icons.cloud_off_rounded,
            text: _error!,
            actionLabel: 'live_tv.retry'.tr(),
            onAction: () => _loadPage(),
          ),
        )
      else if (_channels.isEmpty)
        SliverFillRemaining(
          hasScrollBody: false,
          child: _Empty(
            icon: _searching ? Icons.search_off_rounded : Icons.live_tv_rounded,
            text: _searching ? 'live_tv.no_match'.tr() : 'live_tv.empty'.tr(),
          ),
        )
      else
        _ChannelGrid(
          channels: _channels,
          favourites: _favourites,
          width: width,
          now: _now,
          onPlay: _play,
          onMore: _openSheet,
        ),
      if (_loadingMore) const _LoadMoreFooter(),
    ];
  }
}

/// A section title, in Home's one header shape.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.label,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final tail = trailing;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(_kGutter, 18, _kGutter, 12),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Semantics(
              header: true,
              child: Text(
                label,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
            ),
            const Spacer(),
            if (tail != null)
              Text(
                tail,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// What is open, and how much is in it. The way back out is the AppBar's, which
/// is on screen at every scroll position.
class _ScopeLine extends StatelessWidget {
  const _ScopeLine({
    required this.name,
    required this.total,
    required this.showTotal,
  });

  final String name;
  final int total;
  final bool showTotal;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(_kGutter, 2, _kGutter, 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (showTotal) ...[
              const SizedBox(width: 10),
              Text(
                'live_tv.channel_count'.plural(total),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The one line that teaches the long press, shown only while nothing is
/// pinned — the moment there is a pin, it has been learnt.
class _HintLine extends StatelessWidget {
  const _HintLine();

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(_kGutter, 0, _kGutter, 4),
        child: Text(
          'live_tv.hint_long_press'.tr(),
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11.5,
            height: 1.35,
          ),
        ),
      ),
    );
  }
}

/// Recents and favourites, in one shape.
///
/// A rail because these are shortcuts, not a section to browse: they should
/// never push the line-up itself off the first screen.
class _PinRail extends StatelessWidget {
  const _PinRail({
    required this.channels,
    required this.favourites,
    required this.onPlay,
    required this.onMore,
  });

  final List<LiveChannel> channels;
  final Set<String> favourites;
  final ValueChanged<LiveChannel> onPlay;
  final ValueChanged<LiveChannel> onMore;

  @override
  Widget build(BuildContext context) {
    // 76 tile + 6 gap + one caption line, so text scaling cannot overflow it.
    final height = 82 + MediaQuery.textScalerOf(context).scale(10.5) * 1.2;
    return SliverToBoxAdapter(
      child: SizedBox(
        height: height,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: _kGutter),
          itemCount: channels.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (context, i) => _PinTile(
            channel: channels[i],
            favourite: favourites.contains(channels[i].id),
            onPlay: onPlay,
            onMore: onMore,
          ),
        ),
      ),
    );
  }
}

/// One pinned channel: its logo, and its name underneath.
///
/// No guide line here on purpose — a pinned channel is rebuilt from a saved
/// card, which never carries a slot, so the line would be permanently blank.
class _PinTile extends StatelessWidget {
  const _PinTile({
    required this.channel,
    required this.favourite,
    required this.onPlay,
    required this.onMore,
  });

  final LiveChannel channel;
  final bool favourite;
  final ValueChanged<LiveChannel> onPlay;
  final ValueChanged<LiveChannel> onMore;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return SizedBox(
      width: 76,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => onPlay(channel),
              onLongPress: () => onMore(channel),
              onSecondaryTap: () => onMore(channel),
              child: Container(
                width: 76,
                height: 76,
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: favourite
                        ? AppColors.primary.withValues(alpha: 0.45)
                        : Colors.white.withValues(alpha: 0.06),
                  ),
                ),
                child: channel.logoUrl == null
                    ? const Icon(
                        Icons.live_tv_rounded,
                        size: 26,
                        color: AppColors.textHint,
                      )
                    : CachedNetworkImage(
                        imageUrl: channel.logoUrl!,
                        fit: BoxFit.contain,
                        // The 54pt content box, not the 76pt tile.
                        memCacheWidth: (54 * dpr).round(),
                        errorWidget: (_, _, _) => const Icon(
                          Icons.live_tv_rounded,
                          size: 26,
                          color: AppColors.textHint,
                        ),
                        placeholder: (_, _) => const SizedBox.shrink(),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          FixedTextLines(
            fontSize: 10.5,
            lineHeight: 1.2,
            lines: 1,
            child: Text(
              channel.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The categories, two per row.
///
/// Captioned with a count, because the decision being made here is "which of
/// these do I want", and a count is the only thing that distinguishes a
/// category with four channels in it from one with four hundred.
class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({
    required this.folders,
    required this.width,
    required this.onOpen,
  });

  final List<LiveFolder> folders;
  final double width;
  final ValueChanged<String> onOpen;

  /// The eleven names the line-up actually uses, each with the glyph somebody
  /// would draw for it. Anything else the backend grows later falls back.
  static const Map<String, IconData> _glyphs = {
    'movies': Icons.movie_rounded,
    'general': Icons.tv_rounded,
    'entertainment': Icons.celebration_rounded,
    'kids': Icons.child_care_rounded,
    'documentary': Icons.public_rounded,
    'news': Icons.article_rounded,
    'music': Icons.music_note_rounded,
    'sports': Icons.sports_soccer_rounded,
    'lifestyle': Icons.spa_rounded,
    'religious': Icons.auto_stories_rounded,
    'family': Icons.family_restroom_rounded,
  };

  static IconData _glyphFor(String name) =>
      _glyphs[name.toLowerCase()] ?? Icons.folder_rounded;

  static int columnsFor(double width) =>
      width >= 900 ? 4 : (width >= 620 ? 3 : 2);

  /// Two lines of text plus the tile's own padding, floored at the height the
  /// tile has always had — so it is unchanged at normal text size and grows
  /// rather than overflows at 1.8×.
  static double extentFor(BuildContext context) {
    final ts = MediaQuery.textScalerOf(context);
    final raw = ts.scale(12.5) * 1.2 + 3 + ts.scale(10.5) * 1.2 + 28;
    return raw < 64 ? 64.0 : raw;
  }

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: _kGutter),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columnsFor(width),
          mainAxisSpacing: _kSpacing,
          crossAxisSpacing: _kSpacing,
          mainAxisExtent: extentFor(context),
        ),
        delegate: SliverChildBuilderDelegate((context, i) {
          final folder = folders[i];
          return Material(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => onOpen(folder.name),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        _glyphFor(folder.name),
                        size: 18,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            folder.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'live_tv.channel_count'.plural(folder.count),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 10.5,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }, childCount: folders.length),
      ),
    );
  }
}

/// The countries the line-up covers, as a strip you scroll sideways.
///
/// A shortcut for somebody who already knows what they are after, not the main
/// navigation. Ordered by how much each country contributes, and cut at
/// sixteen — past that the codes stop resolving to names and the strip goes
/// ragged.
class _CountryRail extends StatelessWidget {
  const _CountryRail({
    required this.countries,
    required this.nameOf,
    required this.flagOf,
    required this.onOpen,
  });

  static const int _cap = 16;

  final List<LiveCountry> countries;
  final String Function(String) nameOf;
  final String Function(String) flagOf;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    // Regional-indicator pairs do not render on Windows, where a flag becomes
    // two letterboxed letters. Phones, where this strip is actually used, get
    // the picture.
    final showFlags = !isDesktopPlatform;

    return SliverToBoxAdapter(
      child: SizedBox(
        height: 40,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: _kGutter),
          itemCount: countries.length < _cap ? countries.length : _cap,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final country = countries[i];
            final flag = showFlags ? flagOf(country.code) : '';
            return Material(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(20),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onOpen(country.code),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 13),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (flag.isNotEmpty) ...[
                        Text(flag, style: const TextStyle(fontSize: 15)),
                        const SizedBox(width: 7),
                      ],
                      Text(
                        nameOf(country.code),
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${country.count}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The channels themselves.
class _ChannelGrid extends StatelessWidget {
  const _ChannelGrid({
    required this.channels,
    required this.favourites,
    required this.width,
    required this.now,
    required this.onPlay,
    required this.onMore,
  });

  final List<LiveChannel> channels;
  final Set<String> favourites;
  final double width;
  final DateTime now;
  final ValueChanged<LiveChannel> onPlay;
  final ValueChanged<LiveChannel> onMore;

  @override
  Widget build(BuildContext context) {
    // Channel logos are wide, not poster-shaped, so the cell is landscape and
    // the count follows the width rather than a fixed number.
    final columns = _columnsFor(width);
    final cell = (width - _kGutter * 2 - _kSpacing * (columns - 1)) / columns;
    final caption = _ChannelCard.reserveCaption(context);

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: _kGutter),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisSpacing: _kSpacing,
          crossAxisSpacing: _kSpacing,
          // The logo box is what the cell is for, so the caption's two lines
          // are added to it rather than taken out of it — a fixed ratio let a
          // long name eat the logo, and a one-line name grow it.
          childAspectRatio: cell / (cell * 0.73 + caption + 9),
        ),
        delegate: SliverChildBuilderDelegate(
          (context, i) => _ChannelCard(
            channel: channels[i],
            favourite: favourites.contains(channels[i].id),
            captionHeight: caption,
            cell: cell,
            now: now,
            onPlay: () => onPlay(channels[i]),
            onMore: () => onMore(channels[i]),
          ),
          childCount: channels.length,
        ),
      ),
    );
  }
}

class _ChannelCard extends StatelessWidget {
  const _ChannelCard({
    required this.channel,
    required this.favourite,
    required this.captionHeight,
    required this.cell,
    required this.now,
    required this.onPlay,
    required this.onMore,
  });

  static const double _fontSize = 11.5;
  static const double _lineHeight = 1.2;
  static const double _slotFontSize = 10.5;

  /// Two lines, always. Channel names run from "TV1" to "Discovery Science HD",
  /// and letting the caption size itself left every logo in a row at a
  /// different scale.
  ///
  /// Rounded up, and that is the whole point of the call. 11.5 x 1.2 x 2 is
  /// 27.6, but the text is laid out in whole logical pixels and takes 28 — so
  /// every card whose name wrapped to a second line overflowed by exactly the
  /// 0.4 difference. Reserving the ceiling costs at most a pixel of card and
  /// removes a sub-pixel deficit that no amount of padding elsewhere could fix,
  /// because it was arithmetic and not spacing.
  static double reserveCaption(BuildContext context) =>
      (MediaQuery.textScalerOf(context).scale(_fontSize) * _lineHeight * 2)
          .ceilToDouble();

  final LiveChannel channel;
  final bool favourite;
  final double captionHeight;
  final double cell;
  final DateTime now;
  final VoidCallback onPlay;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final slot = channel.slotAt(now);
    final bar = _barFactor(slot, now);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final logoWidth = cell - 24;

    return Semantics(
      container: true,
      button: true,
      label: slot == null ? channel.name : '${channel.name}. ${slot.title}',
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPlay,
          onLongPress: onMore,
          onSecondaryTap: onMore,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: favourite
                    ? AppColors.primary.withValues(alpha: 0.45)
                    : Colors.white.withValues(alpha: 0.06),
              ),
            ),
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: channel.logoUrl == null
                              ? _Fallback(name: channel.name)
                              : CachedNetworkImage(
                                  imageUrl: channel.logoUrl!,
                                  fit: BoxFit.contain,
                                  memCacheWidth: logoWidth > 0
                                      ? (logoWidth * dpr).round()
                                      : null,
                                  // Logos come from wherever the playlist
                                  // points, and a dead one is common — the
                                  // initial reads better than a broken-image
                                  // glyph.
                                  errorWidget: (_, _, _) =>
                                      _Fallback(name: channel.name),
                                  placeholder: (_, _) =>
                                      const SizedBox.shrink(),
                                ),
                        ),
                      ),
                      if (favourite)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Icon(
                            Icons.star_rounded,
                            size: 15,
                            color: AppColors.primary,
                          ),
                        ),
                      // Rides the bottom edge of the logo box, so it costs the
                      // cell no height at all.
                      if (bar != null)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: SizedBox(
                            height: 2,
                            child: Container(
                              color: Colors.white.withValues(alpha: 0.08),
                              child: FractionallySizedBox(
                                alignment: AlignmentDirectional.centerStart,
                                widthFactor: bar,
                                heightFactor: 1,
                                child: Container(color: AppColors.primary),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 9),
                  child: SizedBox(
                    height: captionHeight,
                    // One name line plus a slot line at 10.5 is strictly
                    // shorter than the two name lines the box reserves, so a
                    // guide costs the grid nothing and a channel without one
                    // simply keeps both lines for its name.
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          channel.name,
                          maxLines: slot == null ? 2 : 1,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: _fontSize,
                            height: _lineHeight,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (slot != null)
                          Text(
                            slot.title,
                            maxLines: 1,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: _slotFontSize,
                              height: _lineHeight,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase(),
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: AppColors.textHint,
        ),
      ),
    );
  }
}

class _LoadMoreFooter extends StatelessWidget {
  const _LoadMoreFooter();

  @override
  Widget build(BuildContext context) {
    return const SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          ),
        ),
      ),
    );
  }
}

/// The channel grid's shape, before it has anything in it.
///
/// The same delegate and the same aspect ratio as the real grid, so the
/// channels land exactly where the skeleton sat.
class _GridSkeleton extends StatelessWidget {
  const _GridSkeleton({required this.width, required this.count});

  final double width;
  final int count;

  @override
  Widget build(BuildContext context) {
    final columns = _columnsFor(width);
    final cell = (width - _kGutter * 2 - _kSpacing * (columns - 1)) / columns;
    final caption = _ChannelCard.reserveCaption(context);

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: _kGutter),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisSpacing: _kSpacing,
          crossAxisSpacing: _kSpacing,
          childAspectRatio: cell / (cell * 0.73 + caption + 9),
        ),
        delegate: SliverChildBuilderDelegate(
          (_, _) => const ShimmerWrapper(
            child: HomeSkeletonBox(
              width: double.infinity,
              height: double.infinity,
              radius: 14,
            ),
          ),
          childCount: count,
        ),
      ),
    );
  }
}

class _CategorySkeleton extends StatelessWidget {
  const _CategorySkeleton({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: _kGutter),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _CategoryGrid.columnsFor(width),
          mainAxisSpacing: _kSpacing,
          crossAxisSpacing: _kSpacing,
          mainAxisExtent: _CategoryGrid.extentFor(context),
        ),
        delegate: SliverChildBuilderDelegate(
          (_, _) => const ShimmerWrapper(
            child: HomeSkeletonBox(
              width: double.infinity,
              height: double.infinity,
              radius: 14,
            ),
          ),
          childCount: 6,
        ),
      ),
    );
  }
}

class _CountryRailSkeleton extends StatelessWidget {
  const _CountryRailSkeleton();

  /// Uneven on purpose: four identical pills read as a rendering artefact
  /// rather than as country names on their way.
  static const List<double> _widths = [96, 78, 110, 86];

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 40,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: _kGutter),
          itemCount: _widths.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, i) => ShimmerWrapper(
            child: HomeSkeletonBox(width: _widths[i], height: 40, radius: 20),
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
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
            Icon(
              icon,
              size: 46,
              color: AppColors.textHint.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 14),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13.5,
                height: 1.5,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 14),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
