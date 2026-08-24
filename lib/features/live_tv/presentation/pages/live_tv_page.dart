import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/detail/domain/entities/player_args.dart';
import 'package:soplay/features/live_tv/data/live_tv_service.dart';

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

  /// The folder being read, or empty for the top level.
  String _folder = '';

  /// The country being read, or empty. Mutually exclusive with [_folder] —
  /// they are two ways of asking the same question and combining them produces
  /// a screen nobody navigated to.
  String _country = '';
  String _query = '';
  Timer? _debounce;

  int _page = 1;
  bool _hasMore = false;
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final hive = getIt<HiveService>();
    _favourites = hive.getLiveTvFavourites().toSet();
    _recent = hive.getLiveTvRecent();
    _cards = hive.getLiveTvCards();
    _scroll.addListener(_onScroll);
    _loadFolders();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  /// True while the screen is showing folders rather than channels.
  bool get _atTopLevel =>
      _folder.isEmpty && _country.isEmpty && _query.trim().isEmpty;

  /// What the crumb says you are inside of.
  String get _openName => _folder.isNotEmpty ? _folder : _countryName(_country);

  Future<void> _loadFolders() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final index = await _service.index();
      if (!mounted) return;
      setState(() {
        _folders = index.folders;
        _countries = index.countries;
        _total = index.folders.fold(0, (n, f) => n + f.count);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'live_tv.load_failed'.tr();
      });
    }
  }

  /// One page of channels for the open folder, or for the current search.
  Future<void> _loadPage({bool append = false}) async {
    if (append && (_loadingMore || !_hasMore)) return;
    setState(() {
      if (append) {
        _loadingMore = true;
      } else {
        _loading = true;
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
      if (!mounted) return;
      setState(() {
        _channels = append ? [..._channels, ...result.channels] : result.channels;
        _page = result.page;
        _hasMore = result.hasMore;
        _total = result.total;
        _loading = false;
        _loadingMore = false;
      });
      _rememberCards(result.channels);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (!append) _error = 'live_tv.load_failed'.tr();
      });
    }
  }

  /// The next page, once the list is close enough to its end to need one.
  void _onScroll() {
    if (!_scroll.hasClients || _atTopLevel) return;
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - 600) _loadPage(append: true);
  }

  /// Searching goes to the server, so it waits for a pause in the typing.
  void _onQueryChanged(String value) {
    _debounce?.cancel();
    setState(() => _query = value);
    if (value.trim().isEmpty) {
      // Back to whatever was on screen before the search started.
      if (_folder.isEmpty) {
        setState(() => _channels = const []);
      } else {
        _loadPage();
      }
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), _loadPage);
  }

  void _openFolder(String name) {
    setState(() {
      _folder = name;
      _country = '';
      _channels = const [];
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _loadPage();
  }

  void _openCountry(String code) {
    setState(() {
      _country = code;
      _folder = '';
      _channels = const [];
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _loadPage();
  }

  void _closeFolder() {
    setState(() {
      _folder = '';
      _country = '';
      _channels = const [];
      _query = '';
    });
    _search.clear();
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  /// Keeps enough of the pinned channels to draw them without their page.
  void _rememberCards(List<LiveChannel> seen) {
    final wanted = {..._favourites, ..._recent};
    if (wanted.isEmpty) return;
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
    _cards.removeWhere((id, _) => !wanted.contains(id));
    if (changed) getIt<HiveService>().setLiveTvCards(_cards);
  }

  /// A country code as something readable.
  ///
  /// Only the ones this line-up actually carries are named; anything else keeps
  /// its code, which is still better than an empty chip. Home comes first
  /// wherever these are sorted, because it is what most people came for.
  static const Map<String, String> _countryNames = {
    'UZ': 'O\'zbekiston',
    'RU': 'Rossiya',
    'TR': 'Turkiya',
    'KZ': 'Qozog\'iston',
    'KG': 'Qirg\'iziston',
    'TJ': 'Tojikiston',
    'TM': 'Turkmaniston',
    'AZ': 'Ozarbayjon',
    'US': 'AQSH',
    'UK': 'Buyuk Britaniya',
    'GB': 'Buyuk Britaniya',
    'CA': 'Kanada',
    'DE': 'Germaniya',
    'FR': 'Fransiya',
    'QA': 'Qatar',
    'AE': 'BAA',
    'CN': 'Xitoy',
    'JP': 'Yaponiya',
    'KR': 'Koreya',
    'SG': 'Singapur',
    'IL': 'Isroil',
    'AT': 'Avstriya',
    'SK': 'Slovakiya',
  };

  String _countryName(String code) =>
      _countryNames[code.toUpperCase()] ?? code.toUpperCase();

  /// The flag for an ISO country code, built from regional-indicator letters.
  ///
  /// A picture rather than two letters, and no asset to ship or fail to load —
  /// every platform this runs on renders these.
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
        showDownloadAction: false,
      ),
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
        titleSpacing: widget.embedded ? 18 : null,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'live_tv.title'.tr(),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 8),
            const _LivePill(),
          ],
        ),
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_loading && _folders.isEmpty && _channels.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
    }
    if (_error != null && _folders.isEmpty && _channels.isEmpty) {
      return _Empty(
        icon: Icons.cloud_off_rounded,
        text: _error!,
        actionLabel: 'live_tv.retry'.tr(),
        onAction: _loadFolders,
      );
    }

    final searching = _query.trim().isNotEmpty;
    final favourites = [
      for (final id in _favourites)
        if (_fromCard(id) != null) _fromCard(id)!,
    ];
    final recent = [
      for (final id in _recent)
        if (!_favourites.contains(id) && _fromCard(id) != null) _fromCard(id)!,
    ];

    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: AppColors.surface,
      onRefresh: _atTopLevel ? _loadFolders : () => _loadPage(),
      child: CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: TextField(
                controller: _search,
                onChanged: _onQueryChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: _atTopLevel
                      ? 'live_tv.search_hint'.tr()
                      : 'live_tv.search_in'.tr(namedArgs: {'folder': _openName}),
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () {
                            _search.clear();
                            _onQueryChanged('');
                          },
                        ),
                ),
              ),
            ),
          ),

          // Which folder is open, and the way back out of it.
          if (_folder.isNotEmpty || _country.isNotEmpty)
            SliverToBoxAdapter(
              child: _FolderCrumb(
                folder: _openName,
                total: _total,
                onBack: _closeFolder,
              ),
            ),

          if (_atTopLevel) ...[
            if (recent.isNotEmpty) ...[
              _Header(label: 'live_tv.recent'.tr()),
              _RecentRow(channels: recent, onPlay: _play),
            ],
            if (favourites.isNotEmpty) ...[
              _Header(label: 'live_tv.favourites'.tr()),
              _Grid(
                channels: favourites,
                favourites: _favourites,
                onPlay: _play,
                onFavourite: _toggleFavourite,
              ),
            ],
            _Header(label: 'live_tv.folders'.tr()),
            // Folders, not channels. A hundred thousand channels is a few dozen
            // folders, and the one somebody wants is two taps away rather than
            // twenty megabytes and a scroll.
            _FolderGrid(folders: _folders, onOpen: _openFolder),
            if (_countries.isNotEmpty) ...[
              _Header(label: 'live_tv.countries'.tr()),
              _CountryRow(
                countries: _countries,
                nameOf: _countryName,
                flagOf: _flagOf,
                onOpen: _openCountry,
              ),
            ],
          ] else if (_loading) ...[
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(top: 60),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
              ),
            ),
          ] else if (_channels.isEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 60),
                child: _Empty(
                  icon: searching ? Icons.search_off_rounded : Icons.live_tv_rounded,
                  text: searching ? 'live_tv.no_match'.tr() : 'live_tv.empty'.tr(),
                ),
              ),
            ),
          ] else ...[
            _Grid(
              channels: _channels,
              favourites: _favourites,
              onPlay: _play,
              onFavourite: _toggleFavourite,
            ),
            if (_loadingMore)
              const SliverToBoxAdapter(
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
              ),
          ],

          SliverToBoxAdapter(child: SizedBox(height: widget.embedded ? 96 : 28)),
        ],
      ),
    );
  }
}

/// The folder you are inside, and the way back out.
class _FolderCrumb extends StatelessWidget {
  const _FolderCrumb({
    required this.folder,
    required this.total,
    required this.onBack,
  });

  final String folder;
  final int total;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
      child: Row(
        children: [
          Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onBack,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                child: Icon(Icons.arrow_back_rounded, size: 17),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              folder,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            '$total',
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textHint,
            ),
          ),
        ],
      ),
    );
  }
}

/// The folders themselves.
///
/// Two per row and captioned with a count, because the decision being made here
/// is "which of these do I want", and a count is the only thing that
/// distinguishes a folder with four channels in it from one with four thousand.
class _FolderGrid extends StatelessWidget {
  const _FolderGrid({required this.folders, required this.onOpen});

  final List<LiveFolder> folders;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 900 ? 4 : (width >= 620 ? 3 : 2);

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          mainAxisExtent: 64,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, i) {
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
                    border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 32,
                        height: 32,
                        child: folder.logoUrl == null
                            ? Icon(
                                Icons.folder_rounded,
                                size: 19,
                                color: AppColors.textHint,
                              )
                            : CachedNetworkImage(
                                imageUrl: folder.logoUrl!,
                                fit: BoxFit.contain,
                                errorWidget: (_, _, _) => Icon(
                                  Icons.folder_rounded,
                                  size: 19,
                                  color: AppColors.textHint,
                                ),
                              ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              folder.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'live_tv.channel_count'.plural(folder.count),
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: AppColors.textHint,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: AppColors.textHint,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
          childCount: folders.length,
        ),
      ),
    );
  }
}

class _LivePill extends StatelessWidget {
  const _LivePill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            'LIVE',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.9,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

/// The last few channels, as a rail rather than a grid.
///
/// A rail because this is a shortcut, not a section to browse: four or five
/// entries wide is the whole of it, and it should never push the line-up itself
/// off the first screen.
class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.channels, required this.onPlay});

  final List<LiveChannel> channels;
  final ValueChanged<LiveChannel> onPlay;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 62,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          itemCount: channels.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final channel = channels[i];
            return Material(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onPlay(channel),
                child: Container(
                  width: 148,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 34,
                        height: 34,
                        child: channel.logoUrl == null
                            ? Icon(
                                Icons.live_tv_rounded,
                                size: 18,
                                color: AppColors.textHint,
                              )
                            : CachedNetworkImage(
                                imageUrl: channel.logoUrl!,
                                fit: BoxFit.contain,
                                errorWidget: (_, _, _) => Icon(
                                  Icons.live_tv_rounded,
                                  size: 18,
                                  color: AppColors.textHint,
                                ),
                              ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          channel.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            height: 1.15,
                            fontWeight: FontWeight.w600,
                          ),
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

class _Header extends StatelessWidget {
  const _Header({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: AppColors.textHint,
          ),
        ),
      ),
    );
  }
}


class _Grid extends StatelessWidget {
  const _Grid({
    required this.channels,
    required this.favourites,
    required this.onPlay,
    required this.onFavourite,
  });

  final List<LiveChannel> channels;
  final Set<String> favourites;
  final ValueChanged<LiveChannel> onPlay;
  final ValueChanged<LiveChannel> onFavourite;

  @override
  Widget build(BuildContext context) {
    // Channel logos are wide, not poster-shaped, so the cell is landscape and
    // the count follows the width rather than a fixed number.
    const gutter = 14.0;
    const spacing = 10.0;
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 900 ? 5 : (width >= 620 ? 4 : 3);
    final cell = (width - gutter * 2 - spacing * (columns - 1)) / columns;
    final caption = _ChannelCard.reserveCaption(context);

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: gutter),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisSpacing: spacing,
          crossAxisSpacing: spacing,
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
            onPlay: () => onPlay(channels[i]),
            onFavourite: () => onFavourite(channels[i]),
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
    required this.onPlay,
    required this.onFavourite,
  });

  static const double _fontSize = 11.5;
  static const double _lineHeight = 1.2;

  /// Two lines, always. Channel names run from "TV1" to "Discovery Science HD",
  /// and letting the caption size itself left every logo in a row at a
  /// different scale.
  static double reserveCaption(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(_fontSize) * _lineHeight * 2;

  final LiveChannel channel;
  final bool favourite;
  final double captionHeight;
  final VoidCallback onPlay;
  final VoidCallback onFavourite;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPlay,
        onLongPress: onFavourite,
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
                                // Logos come from wherever the playlist points,
                                // and a dead one is common — the initial reads
                                // better than a broken-image glyph.
                                errorWidget: (_, _, _) =>
                                    _Fallback(name: channel.name),
                                placeholder: (_, _) =>
                                    _Fallback(name: channel.name),
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
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 9),
                child: SizedBox(
                  height: captionHeight,
                  child: Center(
                    child: Text(
                      channel.name,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: _fontSize,
                        height: _lineHeight,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
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
            Icon(icon, size: 46, color: AppColors.textHint.withValues(alpha: 0.6)),
            const SizedBox(height: 14),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textHint,
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

/// The countries the line-up covers, as a strip you scroll sideways.
///
/// A row rather than a grid, and below the folders: it is a shortcut for
/// somebody who already knows what they are after, not the main navigation.
/// Ordered by how much each country actually contributes — the line-up leads
/// with channels people recognise, and pinning a home country in front of that
/// puts a provincial station where a famous one should be.
class _CountryRow extends StatelessWidget {
  const _CountryRow({
    required this.countries,
    required this.nameOf,
    required this.flagOf,
    required this.onOpen,
  });

  final List<LiveCountry> countries;
  final String Function(String) nameOf;
  final String Function(String) flagOf;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final ordered = [...countries]..sort((a, b) => b.count.compareTo(a.count));

    return SliverToBoxAdapter(
      child: SizedBox(
        height: 40,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          itemCount: ordered.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final country = ordered[i];
            final flag = flagOf(country.code);
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
                    border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
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
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${country.count}',
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textHint,
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
