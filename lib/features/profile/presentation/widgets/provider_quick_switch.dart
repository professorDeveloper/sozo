import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/features/home/data/datasources/home_data_source.dart';
import 'package:soplay/features/sources/domain/source_ecosystem.dart';
import 'package:soplay/features/sources/domain/source_scope.dart';
import 'package:soplay/features/search/data/source_health_store.dart';
import 'package:soplay/features/sources/presentation/widgets/source_health_badge.dart';
import 'package:soplay/features/sources/presentation/widgets/source_scope_menu.dart';
import 'package:soplay/core/extensions/source_language.dart';
import 'package:soplay/core/network/image_headers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:soplay/core/content/catalogue.dart';
import 'package:soplay/core/content/catalogue_logo.dart';
import 'package:soplay/core/content/content_mode.dart';
import 'package:soplay/core/content/content_mode_style.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/profile/domain/entities/provider_entity.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_bloc.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_event.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_state.dart';
import 'package:soplay/core/widgets/mode_switch_overlay.dart';
import 'package:flutter/rendering.dart';
import 'package:soplay/core/widgets/edge_fade.dart';
import 'package:soplay/core/widgets/item_appear.dart';
import 'package:soplay/features/home/presentation/bloc/home/home_bloc.dart';
import 'package:soplay/features/home/presentation/bloc/home/home_state.dart';
import 'package:soplay/features/profile/presentation/pages/profile_page.dart';

/// Changing the active source, from wherever somebody happens to be.
///
/// This used to live inside the home screen's top bar, reachable only from the
/// chip up there. Profile had its own path to the same decision — Sources, then
/// Active source, then the full providers page — which is three screens to do
/// the thing this app asks people to do most often, and the last of those
/// screens is really for installing extensions.
///
/// Lifted out so both entry points open the same sheet. The alternative was a
/// second picker in Profile, and two pickers for one decision drift.

/// Opens the quick switcher over whatever screen called it.
///
/// Reads the bloc itself so a caller needs nothing but a context: the home bar
/// has the loaded state to hand, Profile does not, and making them agree on a
/// parameter was the only thing standing between the two entry points.
Future<void> openProviderQuickSwitch(BuildContext context) async {
  final bloc = context.read<ProviderBloc>();
  final state = bloc.state;
  if (state is! ProviderLoaded) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          (state is ProviderError
                  ? 'profile.providers_error'
                  : 'search.loading_sources')
              .tr(),
        ),
      ),
    );
    return;
  }
  await _openSwitcher(context, bloc, state);
}

/// Offline, a favourited server provider is dropped rather than offered —
/// picking it from the quick switcher would break the home screen. If that
/// leaves nothing, the caller falls through to the full picker, which
/// explains the outage.
List<ProviderEntity> _resolveFavorites(ProviderLoaded state) {
  final favIds = getIt<HiveService>().getFavoriteProviders();
  final byId = {
    for (final p in state.providers)
      if (state.isUsable(p)) p.id: p,
  };
  return [
    for (final id in favIds)
      if (byId[id] != null) byId[id]!,
  ];
}

/// Moves to another kind of catalogue.
///
/// The provider has to move with it: the home screen is driven by whichever
/// source is current, and leaving a video provider selected in manga mode
/// would show an empty screen and look like the switch failed. So the first
/// usable source of the new kind is picked — preferring a favourite, because
/// somebody who starred a manga source starred it for this.
///
/// Nothing happens at all when the new mode has no sources: switching into an
/// empty mode is a dead end nobody can get out of except by switching back,
/// and saying so beats stranding them there.
Future<void> _switchMode(
  BuildContext context,
  ProviderBloc bloc,
  ProviderLoaded state,
  ContentMode mode, {
  Rect? origin,
}) async {
  final hive = getIt<HiveService>();
  final candidates = [
    for (final p in state.providers)
      if (state.isUsable(p) && p.id.contentMode == mode) p,
  ];
  final catalogues = Catalogue.forMode(mode);
  if (candidates.isEmpty && catalogues.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('mode.none_installed'.tr(args: [mode.labelKey.tr()])),
      ),
    );
    return;
  }
  // Somebody browsing a catalogue stays on a catalogue across modes: they
  // chose the wide view over one site, and the new mode has the same. With
  // no source installed for the mode the catalogue is the landing anyway —
  // an empty mode used to be a dead end, and now it is AniList's shelf.
  final favIds = hive.getFavoriteProviders().toSet();
  final String pickId;
  if ((Catalogue.isId(state.currentProviderId) || candidates.isEmpty) &&
      catalogues.isNotEmpty) {
    pickId = catalogues.first.id;
  } else {
    pickId = candidates
        .firstWhere(
          (p) => favIds.contains(p.id),
          orElse: () => candidates.first,
        )
        .id;
  }

  await hive.setContentMode(mode.id);
  if (!context.mounted) return;

  // Subscribed BEFORE the pick is dispatched, or the reload it triggers can
  // land before anyone is listening and the cover would wait out its whole
  // timeout over content that is already there.
  //
  // Only when the provider actually changes: MainPage reloads Home off the
  // provider id moving, so an unchanged id means no reload to wait for and
  // this would be a future that never completes.
  final Future<void>? loaded = pickId == state.currentProviderId
      ? null
      : context
            .read<HomeBloc>()
            .stream
            .firstWhere((s) => s is HomeLoaded || s is HomeError)
            .then((_) {});

  // Selected BEFORE the animation, so the reload runs underneath the cover
  // rather than starting when it lifts onto an empty screen.
  bloc.add(ProviderSelect(pickId));
  // The mode's own glyph even when the landing is a catalogue: the viewer
  // changed MODE, and that is what the cover should say.
  await ModeSwitchOverlay.play(context, mode, until: loaded, origin: origin);
}

Future<void> _openSwitcher(
  BuildContext context,
  ProviderBloc bloc,
  ProviderLoaded state,
) async {
  final favorites = _resolveFavorites(state);
  // Everything usable, not only the favourites.
  //
  // The sheet used to hold favourites and nothing else, and fell through to
  // the full providers PAGE when there were none — which is most people, and
  // is why the report was "I have to go to settings every time I want to
  // change source". Switching source is the single most repeated action in
  // this app and it must never leave the home screen.
  final hive = getIt<HiveService>();
  final mode = ContentMode.fromId(hive.getContentMode());
  // Narrowed to the mode. Somebody who came to read should be choosing
  // between the four readers they have, not finding them among thirty video
  // providers — which is the version of this that sent people to Settings.
  final all = [
    for (final p in state.providers)
      if (p.id.contentMode == mode) p,
  ];
  // Where the chip was when it was pressed, so the cover can open from it.
  // Read here rather than carried in the pop result: the result is a string
  // channel shared by three kinds of answer, and widening it to a record for
  // one of them would touch every caller.
  Rect? tapped;
  final result = await showAdaptiveModal<String>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => ProviderQuickSwitchSheet(
      onModeTap: (rect) => tapped = rect,
      favorites: [
        for (final f in favorites)
          if (f.id.contentMode == mode) f,
      ],
      all: all,
      unavailableIds: {
        for (final p in all)
          if (!state.isUsable(p)) p.id,
      },
      mode: mode,
      currentProviderId: state.currentProviderId,
    ),
  );
  if (result == null || !context.mounted) return;
  if (result == _kAllProvidersAction) {
    openProviderPicker(context, bloc);
    return;
  }
  if (result.startsWith(_kCataloguePrefix)) {
    final id = result.substring(_kCataloguePrefix.length);
    final catalogue = Catalogue.fromId(id);
    if (catalogue == null) return;
    // The same beat as a mode switch, and for the same reason: the whole
    // home is replaced underneath, and doing that with no transition reads
    // as the app hanging while the catalogue loads.
    final Future<void>? loaded = id == state.currentProviderId
        ? null
        : context
              .read<HomeBloc>()
              .stream
              .firstWhere((s) => s is HomeLoaded || s is HomeError)
              .then((_) {});
    bloc.add(ProviderSelect(id));
    await ModeSwitchOverlay.play(
      context,
      catalogue.mode,
      catalogue: catalogue,
      until: loaded,
      origin: tapped,
    );
    return;
  }
  final switched = ContentMode.values
      .where((m) => result == '$_kModePrefix${m.id}')
      .firstOrNull;
  if (switched != null) {
    await _switchMode(context, bloc, state, switched, origin: tapped);
    return;
  }
  bloc.add(ProviderSelect(result));
}

const String _kAllProvidersAction = '__all_providers__';

/// Marks a sheet result as "make this catalogue the home", the same way
/// [_kModePrefix] marks a mode. Three kinds of answer share one string channel.
const String _kCataloguePrefix = '__cat__:';

/// Prefix that marks a sheet result as "switch to this mode" rather than
/// "select this provider". They share one return channel because the sheet is
/// one list, and a sentinel is cheaper than a second result type.
const String _kModePrefix = '__mode__:';

/// The one place a source gets changed.
///
/// Favourites first because they are what somebody switches BETWEEN, then every
/// other usable source underneath, with a filter once the list is long enough
/// to need one. The full providers page is still reachable from the bottom, but
/// it is now for managing sources rather than for the everyday act of picking
/// one — which is what it had quietly become.
class ProviderQuickSwitchSheet extends StatefulWidget {
  const ProviderQuickSwitchSheet({
    super.key,
    required this.favorites,
    required this.all,
    required this.mode,
    required this.currentProviderId,
    this.onModeTap,
    this.unavailableIds = const {},
  });

  /// Reports where a mode chip was on screen when it was pressed, so the
  /// switch can open from there instead of from nowhere.
  final ValueChanged<Rect>? onModeTap;

  final List<ProviderEntity> favorites;
  final List<ProviderEntity> all;
  final Set<String> unavailableIds;

  /// The kind of catalogue these sources belong to. Shown as a row of chips at
  /// the top, because the mode is the thing that decides what the rest of the
  /// sheet contains — putting it anywhere else would make the list look like it
  /// had lost sources.
  final ContentMode mode;

  final String currentProviderId;

  @override
  State<ProviderQuickSwitchSheet> createState() =>
      ProviderQuickSwitchSheetState();
}

class ProviderQuickSwitchSheetState extends State<ProviderQuickSwitchSheet> {
  final TextEditingController _filter = TextEditingController();
  String _query = '';

  /// Which slice of the sources is showing. The same control as the sources
  /// page, for the same reason: with several repositories installed this sheet
  /// is a few hundred rows behind one text field, and typing only helps if you
  /// already know the name you are looking for.
  SourceScope _scope = SourceScope.all;

  /// The language narrowed to, or null for every language. Several hundred
  /// sources is a list nobody scrolls; the language a viewer watches in is
  /// the question most of them answer first. A source that declares every
  /// language stays under every choice.
  String? _lang;

  bool _speaks(ProviderEntity p) {
    final want = _lang;
    if (want == null) return true;
    final lang = p.displayLang;
    return lang == want || lang == kAllLanguages;
  }

  /// Languages among these sources, most common first, with how many.
  List<MapEntry<String, int>> get _languageCounts {
    final counts = <String, int>{};
    for (final p in widget.all) {
      final l = p.displayLang;
      if (l.isEmpty || l == kAllLanguages) continue;
      counts[l] = (counts[l] ?? 0) + 1;
    }
    return counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  }

  /// Counted over every source the sheet was handed, not over what the search
  /// has left — so the menu still says how many CloudStream sources exist while
  /// a query is narrowing the list, which is the number worth knowing.
  SourceScopeCounts get _counts => SourceScopeCounts.of(widget.all);

  /// As much of [_scope] as still exists. See the sources page for the rule;
  /// here the list can also change under it when the mode does.
  SourceScope get _liveScope {
    final e = _scope.ecosystem;
    if (e == null) return SourceScope.all;
    final counts = _counts;
    if ((counts.byEcosystem[e] ?? 0) == 0) return SourceScope.all;
    final r = _scope.repo;
    if (r == null) return _scope;
    return (counts.byRepo[e]?[r] ?? 0) > 0 ? _scope : SourceScope(ecosystem: e);
  }

  /// One per chip, so the chip that was pressed can say where it was.
  final Map<ContentMode, GlobalKey> _chipKeys = {
    for (final m in ContentMode.values) m: GlobalKey(),
  };
  final Map<Catalogue, GlobalKey> _catalogueKeys = {
    for (final c in Catalogue.values) c: GlobalKey(),
  };

  /// The mode whose segment was just tapped. The thumb slides onto it for
  /// one beat before the sheet closes and the switch plays from there, so
  /// the tap is answered on the sheet itself rather than by the sheet
  /// vanishing.
  ContentMode? _pendingMode;

  Future<void> _pickMode(ContentMode m) async {
    if (m == widget.mode || _pendingMode != null) return;
    HapticFeedback.selectionClick();
    setState(() => _pendingMode = m);
    await Future<void>.delayed(_ModeSegments.slide);
    if (!mounted) return;
    widget.onModeTap?.call(_rectOf(_chipKeys[m]));
    Navigator.of(context).pop('$_kModePrefix${m.id}');
  }

  /// Below this the filter is chrome over a list that already fits.
  static const int _filterThreshold = 8;

  /// One source row. Fixed so the sheet can open ON the current source: a
  /// builder with variable rows can only be scrolled to a position it has
  /// already laid out, and the current source is usually far below the fold.
  static const double _tileExtent = 64;

  /// Used on TV and desktop, where there is no sheet to supply one.
  final ScrollController _flat = ScrollController();

  bool get _hasFilter => widget.all.length >= _filterThreshold;

  /// Where a chip is on screen. Zero when it has not been laid out, which the
  /// cover reads as "no visible cause" and opens from the middle instead.
  Rect _rectOf(GlobalKey? key) {
    final box = key?.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return Rect.zero;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// Opening on the current source is a one-time move. Re-running it after a
  /// keystroke in the filter would yank the list out from under the typing.
  bool _aligned = false;

  /// The sliver that holds the source rows, so the extent of everything above
  /// it can be read back after layout rather than assumed.
  final GlobalKey _listKey = GlobalKey();

  /// That extent. Zero until the first layout, and re-read whenever it moves —
  /// the catalogue section is one card or two, side by side or stacked,
  /// depending on the mode and the text size.
  double _leading = 0;

  void _measureLeading() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final sliver = _listKey.currentContext?.findRenderObject();
      if (sliver is! RenderSliver || sliver.geometry == null) return;
      final leading = sliver.constraints.precedingScrollExtent;
      if (leading == _leading || !leading.isFinite) return;
      setState(() => _leading = leading);
    });
  }

  @override
  void initState() {
    super.initState();
    _health.changes.addListener(_onHealth);
    unawaited(_health.refreshRemote());
  }

  final SourceHealthStore _health = sourceHealth();

  void _onHealth() {
    if (mounted) setState(() {});
  }

  /// Down sources go last, or away when the user hid them; the one in use
  /// always stays.
  List<ProviderEntity> _arrange(List<ProviderEntity> rows) => _health.sinkDown(
    rows,
    (p) => p.id,
    keyOf: (p) => p.healthKey,
    hide: _health.hideDown,
    keep: (p) => p.id == widget.currentProviderId,
  );

  int get _downCount =>
      widget.all.where((p) => _health.isDown(p.id, key: p.healthKey)).length;

  @override
  void dispose() {
    _health.changes.removeListener(_onHealth);
    _filter.dispose();
    _flat.dispose();
    super.dispose();
  }

  /// The bar at the top.
  ///
  /// Decoration: the sheet is as tall as its content and there is nowhere to
  /// drag it to. Kept because a sheet without one reads as a panel that
  /// appeared from nowhere, and every other sheet in the app has one.
  Widget _grabber(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 10, bottom: 2),
      alignment: Alignment.center,
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.textSecondary.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  /// The sources that are not already in the favourites block above.
  ///
  /// Listing a favourite twice makes the sheet look like it has duplicates and
  /// makes the favourites section pointless.
  List<ProviderEntity> get _rest {
    final favIds = {for (final p in widget.favorites) p.id};
    final q = _query.trim().toLowerCase();
    final scope = _liveScope;
    return [
      for (final p in widget.all)
        if (!favIds.contains(p.id) &&
            scope.matches(p) &&
            _speaks(p) &&
            (q.isEmpty || p.name.toLowerCase().contains(q)))
          p,
    ];
  }

  /// Favourites are filtered by the scope too.
  ///
  /// They are a shortcut into the same list, not a separate one — leaving them
  /// alone would show CloudStream favourites above a list filtered to Aniyomi,
  /// which reads as the filter having missed them.
  List<ProviderEntity> get _shownFavorites {
    final q = _query.trim().toLowerCase();
    final scope = _liveScope;
    return [
      for (final p in widget.favorites)
        if (scope.matches(p) &&
            _speaks(p) &&
            (q.isEmpty || p.name.toLowerCase().contains(q)))
          p,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    // TV and desktop never get a sheet: showAdaptiveModal hands those a sized
    // Dialog wrapped in a SingleChildScrollView, so there is nothing to drag
    // and no bounded height to drag it against.
    if (isTvPlatform || isDesktopPlatform) {
      final available =
          (MediaQuery.sizeOf(context).height -
                  keyboard -
                  MediaQuery.paddingOf(context).top -
                  24)
              .clamp(0.0, double.infinity);
      final box = available * (keyboard > 0 ? 1 : 0.78);
      return Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: SizedBox(height: box, child: _body(context, _flat)),
      );
    }

    // A plain bounded Column, not a DraggableScrollableSheet.
    //
    // That widget assumes its child IS the scrollable it was given a controller
    // for. This sheet is a Column — pinned header, list, pinned footer — so the
    // assumption does not hold, and the sheet reserved a height the Column then
    // did not fill: a band of dead space under the footer at every size it was
    // asked to open at.
    //
    // The ceiling is the screen less the status bar and a margin: a sheet that
    // reaches the very top loses its rounded corners against the edge and puts
    // its title level with the clock. viewPadding, not padding — a modal route
    // consumes the padding it has already honoured, so inside the sheet padding
    // reads as zero and the reserve would quietly do nothing.
    final ceiling =
        (MediaQuery.sizeOf(context).height -
                MediaQuery.viewPaddingOf(context).top -
                24 -
                keyboard)
            .clamp(0.0, double.infinity);

    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: ceiling),
        child: SafeArea(top: false, child: _body(context, _flat)),
      ),
    );
  }

  /// Puts the list where the current source is, not at the top.
  ///
  /// Somebody opening this sheet is looking at the source they are on before
  /// they look for another one, and with a couple of hundred installed sources
  /// that row was never on screen — the sheet opened on whatever happened to be
  /// alphabetically first and gave no sign that anything was selected.
  void _alignToCurrent(
    ScrollController controller,
    List<ProviderEntity> items,
  ) {
    if (_aligned || _query.isNotEmpty) return;
    _aligned = true;
    final index = items.indexWhere((p) => p.id == widget.currentProviderId);
    if (index <= 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !controller.hasClients) return;
      // Two rows of lead-in, so the current source reads as one entry in a
      // list rather than as the first thing in it — plus everything that
      // scrolls above the list, which is read off the sliver rather than
      // guessed.
      final sliver = _listKey.currentContext?.findRenderObject();
      final leading = sliver is RenderSliver && sliver.geometry != null
          ? sliver.constraints.precedingScrollExtent
          : 0.0;
      final target = leading + (index - 2) * _tileExtent;
      controller.jumpTo(target.clamp(0.0, controller.position.maxScrollExtent));
    });
  }

  Widget _body(BuildContext context, ScrollController controller) {
    final favorites = _arrange(_shownFavorites);
    final items = [...favorites, ..._arrange(_rest)];
    final downCount = _downCount;
    final catalogues = Catalogue.forMode(widget.mode);
    final searchExtent = _SearchBarHeader.extentFor(context);
    _alignToCurrent(controller, items);
    _measureLeading();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Above the scroll view, and nothing else: the title says what the
        // sheet is, and the mode decides what the whole list even contains.
        // Everything that merely describes the list — the catalogues, the
        // count, the scope — went back INTO it.
        //
        // That is the fix for a sheet that showed three hundred and
        // seventy-two sources through a gap one row tall. The header was a
        // Column child capped at six tenths of the box, and on a phone it took
        // every point of that: title, mode chips, two catalogue cards, a
        // section label, a scope menu and a search field, stacked above a list
        // that got whatever was left. None of it scrolled, because the list
        // was a separate scrollable underneath it.
        _grabber(context),
        // One flexible box holding both the title block and the list, not one
        // each.
        //
        // A Column shares its spare room between flexible children by flex, so
        // a flexible header beside a flexible list takes a share whether it
        // needs one or not — and what a loose fit leaves unused becomes dead
        // space rather than going to the list. Nested, the outer box takes
        // what the inner Column needs and the list inside it is the only thing
        // that stretches.
        //
        // The cap is for the case that was overflowing: a 320-point screen at
        // 200% text with the keyboard up, where the title and the mode chips
        // together are taller than what is left of the sheet. They scroll.
        Flexible(
          child: LayoutBuilder(
            builder: (context, box) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: box.maxHeight * 0.4),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _title(context),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: _ModeSegments(
                            keys: _chipKeys,
                            active: widget.mode,
                            pending: _pendingMode,
                            onTap: _pickMode,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Flexible(
                  child: Scrollbar(
                    controller: controller,
                    // Outside the fade: a position indicator that dissolves at the
                    // edge it exists to mark is no indicator.
                    child: EdgeFade(
                      extent: _tileExtent * 0.55,
                      // The search bar is pinned and opaque, so it is already the top
                      // boundary — rows pass under it rather than being cut by it.
                      before: false,
                      child: CustomScrollView(
                        controller: controller,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        slivers: [
                          // The filter first, and pinned.
                          //
                          // Not because it belongs above the catalogue by
                          // rights, but because a sliver outside the viewport
                          // is not built at all: placed after a section taller
                          // than the box, the field does not exist — and on a
                          // short screen with the keyboard up, which is to say
                          // while somebody is typing in it, there was no field
                          // and no way to get one back. It is also the only
                          // practical way into a list of several hundred, so
                          // it is the one thing here that must never leave.
                          if (_hasFilter)
                            SliverPersistentHeader(
                              pinned: true,
                              delegate: _SearchBarHeader(
                                controller: _filter,
                                query: _query,
                                onChanged: (v) => setState(() => _query = v),
                                onClear: () {
                                  _filter.clear();
                                  setState(() => _query = '');
                                },
                                extent: searchExtent,
                              ),
                            ),
                          SliverToBoxAdapter(
                            child: SourceScopeMenu(
                              counts: _counts,
                              scope: _liveScope,
                              dense: true,
                              onPick: (picked) =>
                                  setState(() => _scope = picked),
                            ),
                          ),
                          if (_languageCounts.length > 1)
                            SliverToBoxAdapter(
                              child: _LanguageRow(
                                languages: _languageCounts,
                                selected: _lang,
                                onPick: (l) => setState(() => _lang = l),
                              ),
                            ),
                          if (downCount > 0 || _health.hideDown)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  0,
                                  12,
                                  8,
                                ),
                                child: Align(
                                  alignment: AlignmentDirectional.centerStart,
                                  child: HideDownChip(
                                    count: downCount,
                                    hidden: _health.hideDown,
                                    onChanged: _health.setHideDown,
                                  ),
                                ),
                              ),
                            ),
                          if (catalogues.isNotEmpty &&
                              _liveScope.isAll &&
                              _query.trim().isEmpty)
                            SliverToBoxAdapter(
                              child: _FadeOnScroll(
                                controller: controller,
                                over: 120,
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    12,
                                    16,
                                    12,
                                  ),
                                  child: _catalogueSection(context, catalogues),
                                ),
                              ),
                            ),
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _SectionLabel(
                                    '${'sources.section'.tr()} · '
                                    '${widget.all.length}',
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (items.isEmpty)
                            SliverToBoxAdapter(child: _emptyNote(context))
                          else
                            SliverFixedExtentList(
                              key: _listKey,
                              // Fixed rows are what make the opening jump land
                              // on the right one, and what lets the settle know
                              // where a row is without measuring it.
                              itemExtent: _tileExtent,
                              delegate: SliverChildBuilderDelegate((
                                context,
                                index,
                              ) {
                                return ScrollSettle(
                                  controller: controller,
                                  index: index,
                                  extent: _tileExtent,
                                  // The catalogue and the count scroll past
                                  // above these, so a row's position is not its
                                  // index alone; and the filter bar covers the
                                  // top of the viewport, so the top edge is not
                                  // the top edge.
                                  leading: _leading,
                                  topInset: _hasFilter ? searchExtent : 0,
                                  child: ItemAppear(
                                    index: index,
                                    child: _favoriteProviderTile(
                                      context,
                                      items[index],
                                      widget.currentProviderId,
                                      favorite: index < favorites.length,
                                      available: !widget.unavailableIds
                                          .contains(items[index].id),
                                      health: _health.badgeOf(
                                        items[index].id,
                                        key: items[index].healthKey,
                                      ),
                                    ),
                                  ),
                                );
                              }, childCount: items.length),
                            ),
                          const SliverToBoxAdapter(child: SizedBox(height: 8)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        ListTile(
          // "Add" first, because that is what somebody who cannot find their
          // source is looking for, and the word was nowhere on this sheet.
          leading: const Icon(Icons.add_rounded),
          title: Text('ux.add_or_manage_sources'.tr()),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.of(context).pop(_kAllProvidersAction),
        ),
      ],
    );
  }

  Widget _title(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
    child: Text(
      'ux.change_source'.tr(),
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
    ),
  );

  /// Catalogues before the sources. A catalogue is what to browse when no
  /// single source is the point — AniList's or TMDB's view of what exists,
  /// with the app finding a source for whatever you open. Each mode has its
  /// own: AniList's anime shelf and TMDB for Watch, AniList's manga and
  /// light-novel shelves for the readers.
  Widget _catalogueSection(BuildContext context, List<Catalogue> catalogues) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _SectionLabel('catalogue.section'.tr()),
        const SizedBox(height: 8),
        // Two cards side by side where there are two; a lone card takes the
        // width. Past the text size at which the navigation bar goes readable,
        // half a phone width is about two letters of a name once the mark and
        // the covers have taken theirs, so the cards take a line each instead
        // of sharing one.
        if (_stacksCatalogues(context))
          for (final (i, c) in catalogues.indexed) ...[
            if (i > 0) const SizedBox(height: 8),
            _catalogueCard(c),
          ]
        else
          Row(
            children: [
              for (final (i, c) in catalogues.indexed) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: _catalogueCard(c)),
              ],
            ],
          ),
      ],
    );
  }

  /// The same threshold the bottom bar switches its own layout at, read off
  /// the card's title rather than a label size: one number for "type is big
  /// enough that side by side stops being readable".
  static bool _stacksCatalogues(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(14) > 18.2;

  Widget _catalogueCard(Catalogue c) {
    final current = widget.currentProviderId == c.id;
    return _CatalogueCard(
      key: _catalogueKeys[c],
      catalogue: c,
      active: current,
      // The catalogue already being browsed has nowhere to go, the same way
      // the active mode segment has nowhere to go.
      onTap: current
          ? null
          : () {
              HapticFeedback.selectionClick();
              widget.onModeTap?.call(_rectOf(_catalogueKeys[c]));
              Navigator.of(context).pop('$_kCataloguePrefix${c.id}');
            },
    );
  }

  /// Mode chips and filter — the part that stays put.
  ///
  /// Pinned, because scrolling two hundred sources past a mode switcher that
  /// has left the screen means scrolling back up to change mode, and the search
  /// box goes with it for the same reason.
  /// Said under the list, not inside the pinned block: that block has a fixed
  /// height, and a message that appears and disappears cannot live in one.
  Widget _emptyNote(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            (_query.isEmpty
                    ? 'profile.no_providers_in_category'
                    : 'ux.no_source_match')
                .tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          if (_query.isNotEmpty || !_liveScope.isAll || _lang != null)
            TextButton(
              onPressed: () {
                _filter.clear();
                setState(() {
                  _query = '';
                  _scope = SourceScope.all;
                  _lang = null;
                });
              },
              child: Text('general.clear'.tr()),
            ),
        ],
      ),
    );
  }
}

/// One of the three catalogue kinds.
///
/// The active one is not tappable: switching to the mode you are already in
/// would replay the animation and reload the screen for no change, which reads
/// as the app stuttering.
/// The three modes as one control: a track with a thumb that sits on the
/// current mode and slides to the one tapped.
///
/// Three loose chips said "here are three buttons"; one track says "you are
/// in one of three places". The glyph on each segment is the same one the
/// switch animation draws, so the thing tapped and the thing that then
/// fills the screen are recognisably the same.
class _ModeSegments extends StatelessWidget {
  const _ModeSegments({
    required this.keys,
    required this.active,
    required this.pending,
    required this.onTap,
  });

  final Map<ContentMode, GlobalKey> keys;
  final ContentMode active;
  final ContentMode? pending;
  final ValueChanged<ContentMode> onTap;

  static const Duration slide = Duration(milliseconds: 220);
  static const double _height = 54;

  @override
  Widget build(BuildContext context) {
    final modes = ContentMode.values;
    final shown = pending ?? active;
    final accent = shown.accent;
    return LayoutBuilder(
      builder: (context, constraints) {
        final segment = constraints.maxWidth / modes.length;
        return Container(
          height: _height,
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(14),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              AnimatedPositionedDirectional(
                duration: slide,
                curve: const Cubic(0.05, 0.7, 0.1, 1.0),
                start: segment * modes.indexOf(shown),
                top: 0,
                bottom: 0,
                width: segment,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: AnimatedContainer(
                    duration: slide,
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(11),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.45),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  for (final m in modes)
                    Expanded(
                      child: Semantics(
                        button: true,
                        selected: m == shown,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(11),
                          key: keys[m],
                          onTap: () => onTap(m),
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // The glyph on the segment the thumb has
                                // just reached draws itself, the way it
                                // will on the cover a moment later.
                                m == shown
                                    ? TweenAnimationBuilder<double>(
                                        key: ValueKey(m),
                                        tween: Tween(begin: 0, end: 1),
                                        duration: const Duration(
                                          milliseconds: 520,
                                        ),
                                        curve: Curves.easeOutCubic,
                                        builder: (_, t, _) => ModeGlyph(
                                          mode: m,
                                          color: Colors.white,
                                          size: 20,
                                          progress: t,
                                        ),
                                      )
                                    : ModeGlyph(
                                        mode: m,
                                        color: m.accent.withValues(alpha: 0.85),
                                        size: 20,
                                      ),
                                const SizedBox(width: 7),
                                Flexible(
                                  child: AnimatedDefaultTextStyle(
                                    duration: slide,
                                    style: TextStyle(
                                      color: m == shown
                                          ? Colors.white
                                          : AppColors.textSecondary,
                                      fontSize: 13.5,
                                      fontWeight: m == shown
                                          ? FontWeight.w800
                                          : FontWeight.w600,
                                    ),
                                    child: Text(
                                      m.labelKey.tr(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A catalogue as a card: its mark, its name, one line on what it holds.
///
/// A chip with a name assumes the name means something; "TMDB" to somebody
/// who has never used it is three letters. The hint is what makes it a
/// choice — "Movies & series" against "Anime" — and the mark is what makes
/// it the same thing as the row above Play on a title's page.
class _CatalogueCard extends StatelessWidget {
  const _CatalogueCard({
    super.key,
    required this.catalogue,
    required this.active,
    required this.onTap,
  });

  final Catalogue catalogue;
  final bool active;
  final VoidCallback? onTap;

  /// A floor, not a height. The card used to be exactly this tall, which is
  /// the size the mark and two lines of text want at normal type — and at
  /// 200% those two lines are taller than the card, so they spilled out of
  /// the bottom of it. It sizes to its text now and only stops shrinking
  /// here, so a card next to a one-word catalogue still looks like a card.
  static const double _minHeight = 68;

  @override
  Widget build(BuildContext context) {
    final accent = catalogue.accent;
    final base = active
        ? Color.alphaBlend(accent.withValues(alpha: 0.16), AppColors.surface)
        : AppColors.surfaceVariant;
    return Semantics(
      button: true,
      selected: active,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        constraints: const BoxConstraints(minHeight: _minHeight),
        decoration: BoxDecoration(
          color: base,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active ? accent : Colors.white.withValues(alpha: 0.05),
            width: active ? 1.5 : 1,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.25),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ]
              : const [],
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            // Loose, and centred: the text stack is what says how tall the
            // card is, and an expanded Stack would hand it the card's height
            // instead — which is the fixed height this just stopped being.
            child: Stack(
              alignment: AlignmentDirectional.center,
              children: [
                // What is inside, along the far edge and fading into the
                // card, so the name never has to fight it for room.
                PositionedDirectional(
                  end: 0,
                  top: 0,
                  bottom: 0,
                  child: _CataloguePeek(catalogue: catalogue),
                ),
                Padding(
                  // Room on the end for the covers, so the hint gives way
                  // to them instead of running under them, and enough above
                  // and below that big type is inset rather than flush with
                  // the border.
                  padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 44, 10),
                  child: Row(
                    children: [
                      CatalogueLogo(catalogue: catalogue, size: 30),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    catalogue.labelKey.tr(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                if (active) ...[
                                  const SizedBox(width: 5),
                                  Icon(
                                    Icons.check_circle_rounded,
                                    size: 15,
                                    color: accent,
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              catalogue.hintKey.tr(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: active
                                    ? accent
                                    : AppColors.textSecondary,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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

/// Three covers from the catalogue's front page, fanned at the end of its
/// card — what is inside, before it is chosen. The front page is cached on
/// the server and here, so the sheet costs one small request per catalogue
/// per half hour and nothing at all the rest of the time.
class _CataloguePeek extends StatefulWidget {
  const _CataloguePeek({required this.catalogue});

  final Catalogue catalogue;

  static final Map<Catalogue, (DateTime, List<String>)> _cache = {};
  static const Duration _fresh = Duration(minutes: 30);

  static Future<List<String>> covers(Catalogue c) async {
    final hit = _cache[c];
    if (hit != null && DateTime.now().difference(hit.$1) < _fresh) {
      return hit.$2;
    }
    try {
      final home = await getIt<HomeDataSource>().loadCatalogueHome(c.kind);
      final items = home.sections
          .expand((s) => s.items)
          .map((m) => m.thumbnail ?? '')
          .where((t) => t.isNotEmpty)
          .take(3)
          .toList();
      _cache[c] = (DateTime.now(), items);
      return items;
    } catch (_) {
      return hit?.$2 ?? const [];
    }
  }

  @override
  State<_CataloguePeek> createState() => _CataloguePeekState();
}

class _CataloguePeekState extends State<_CataloguePeek> {
  late final Future<List<String>> _covers = _CataloguePeek.covers(
    widget.catalogue,
  );

  @override
  Widget build(BuildContext context) {
    // Three leaning covers, each a little behind the last, on a strip a
    // third of the card wide.
    const w = 26.0, h = 38.0, step = 13.0, lean = -0.18;
    final rtl = Directionality.of(context) == ui.TextDirection.rtl;
    return FutureBuilder<List<String>>(
      future: _covers,
      builder: (context, snap) {
        final covers = snap.data ?? const [];
        if (covers.isEmpty) return const SizedBox.shrink();
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          builder: (context, t, child) => Opacity(opacity: t, child: child),
          child: ShaderMask(
            // A directional alignment needs a text direction to resolve,
            // and a shader callback has no context to read one from.
            shaderCallback: (rect) => LinearGradient(
              begin: rtl ? Alignment.centerRight : Alignment.centerLeft,
              end: rtl ? Alignment.centerLeft : Alignment.centerRight,
              colors: const [Color(0x00000000), Color(0xFF000000)],
              stops: const [0, 0.55],
            ).createShader(rect),
            blendMode: BlendMode.dstIn,
            // Centred against whatever the card ended up being, rather than
            // against a number copied from it: the card grows with the text
            // size now, and a copied number would leave the fan riding high
            // in a tall card.
            child: Center(
              child: SizedBox(
                width: 22 + w + step * (covers.length - 1),
                height: h + 6,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (final (i, url) in covers.indexed)
                      PositionedDirectional(
                        start: 22 + step * i,
                        top: i.isOdd ? 6 : 0,
                        child: Transform.rotate(
                          // The fan leans away from the card's edge, so it
                          // leans the other way when that edge is the left.
                          angle: (lean + i * 0.06) * (rtl ? -1 : 1),
                          child: Container(
                            width: w,
                            height: h,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              boxShadow: const [
                                BoxShadow(color: Colors.black54, blurRadius: 6),
                              ],
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: CachedNetworkImage(
                              imageUrl: url,
                              httpHeaders: posterImageHeaders(url),
                              fit: BoxFit.cover,
                              fadeInDuration: const Duration(milliseconds: 200),
                              errorWidget: (_, _, _) => const SizedBox.shrink(),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: const TextStyle(
      color: AppColors.textSecondary,
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.1,
    ),
  );
}

Widget _favoriteProviderTile(
  BuildContext context,
  ProviderEntity p,
  String currentProviderId, {
  bool favorite = false,
  bool available = true,
  RemoteVerdict? health,
}) {
  final selected = p.id == currentProviderId;
  final eco = SourceEcosystem.of(p.id);
  // Where it comes from and what language it speaks, in one small line:
  // the two things that tell "AnimeKAI" apart from "AnimeKAI" one row down.
  //
  // [ProviderLanguage.displayLang] is the one answer, the same one the
  // providers page badges and the sources hub subtitles. Calling [inferLang]
  // here instead was a second opinion that disagreed: a source declaring
  // `all` — which Tachiyomi and Aniyomi repos hand out freely — falls past
  // that function's declaration check into the domain guess, so an `all`
  // catalogue hosted on a `.ru` domain read `RU` in this sheet and `ALL`
  // everywhere else. displayLang keeps `all` as itself.
  //
  // `all` is then left out of the line for the reason the other two lists
  // leave it out: "this catalogue is in every language" is not something a
  // two-letter chip can say, and the row shows under every selection anyway.
  final lang = p.displayLang;
  final meta = [
    eco.label,
    if (!available) 'profile.offline_badge'.tr(),
    if (lang.isNotEmpty && lang != kAllLanguages) shortLabelFor(lang),
  ].join(' · ');
  // Announced the way the mode segments and the catalogue cards are: a thing
  // to press, and one of them is the one you are on. Without it the current
  // source reads to a screen reader as an ordinary row with a tick drawn on
  // it, which is exactly the row somebody using one cannot see.
  return Semantics(
    button: true,
    selected: selected,
    child: Material(
      color: selected
          ? AppColors.primary.withValues(alpha: 0.08)
          : Colors.transparent,
      child: ListTile(
        enabled: available,
        leading: Container(
          decoration: selected
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.35),
                      blurRadius: 10,
                    ),
                  ],
                )
              : null,
          child: Opacity(
            opacity: health?.state == RemoteHealth.dead ? 0.45 : 1,
            child: ProviderLogo(image: p.image, size: 36),
          ),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                p.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            if (health != null) ...[
              const SizedBox(width: 6),
              SourceHealthBadge(verdict: health, sourceName: p.name),
            ],
          ],
        ),
        subtitle: Text(
          meta,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.textHint,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
        dense: true,
        trailing: selected
            ? Icon(Icons.check_rounded, color: AppColors.primary, size: 20)
            : favorite
            ? const Icon(Icons.star_rounded, color: Colors.amber, size: 20)
            : null,
        onTap: !available
            ? null
            : () {
                // The same tick the mode segments answer a tap with, so a source
                // and a mode feel like one control between them.
                HapticFeedback.selectionClick();
                Navigator.of(context).pop(p.id);
              },
      ),
    ),
  );
}

class ProviderLogo extends StatelessWidget {
  const ProviderLogo({required this.image, required this.size, super.key});

  final String image;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      color: AppColors.surfaceVariant,
      alignment: Alignment.center,
      child: Icon(
        Icons.movie_filter_outlined,
        color: AppColors.textHint,
        size: size * 0.55,
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: image.isEmpty
          ? fallback
          : Image.network(
              image,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback,
              loadingBuilder: (_, child, chunk) =>
                  chunk == null ? child : fallback,
            ),
    );
  }
}

/// The section above the list, going quietly as it leaves.
///
/// It is not enough for the catalogue cards to scroll away — they have to
/// leave like something being put down, or a sheet whose top third suddenly
/// slides under a row of chips reads as a layout glitch. They fade, shrink a
/// little and travel up slower than the finger, so the list arrives over them
/// rather than shoving them off.
class _FadeOnScroll extends StatelessWidget {
  const _FadeOnScroll({
    required this.controller,
    required this.child,
    required this.over,
  });

  final ScrollController controller;
  final Widget child;

  /// How far the list has to travel for this to be fully gone.
  final double over;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      child: child,
      builder: (context, built) {
        if (controller.positions.length != 1) return built!;
        final position = controller.position;
        if (!position.haveDimensions) return built!;
        final t = (position.pixels / over).clamp(0.0, 1.0);
        if (t == 0) return built!;
        final k = Curves.easeOut.transform(t);
        return Opacity(
          // Never quite nothing until it is quite gone: a section that has
          // faded out while still occupying its space reads as a hole.
          opacity: 1 - k,
          child: Transform(
            alignment: Alignment.topCenter,
            transform: Matrix4.identity()
              // Slower than the scroll, so it recedes rather than races off.
              ..translateByDouble(0, position.pixels * 0.22, 0, 1)
              ..scaleByDouble(1 - k * 0.05, 1 - k * 0.05, 1, 1),
            child: built,
          ),
        );
      },
    );
  }
}

/// The filter field, pinned above the rows.
///
/// Pinned because of what the list is: three hundred and seventy-two entries,
/// opened scrolled to the one in use. Typing a name is the only practical way
/// to reach any other one, and in a header that scrolls the way to reach the
/// field was to scroll three hundred rows back to the top.
///
/// Its height is fixed by construction rather than measured. A persistent
/// header has to declare an extent before its child is laid out, so the field
/// is given that exact height through [InputDecoration.constraints] — which
/// means the declared extent and the real one cannot drift apart, at any text
/// size.
class _SearchBarHeader extends SliverPersistentHeaderDelegate {
  const _SearchBarHeader({
    required this.controller,
    required this.query,
    required this.onChanged,
    required this.onClear,
    required this.extent,
  });

  final TextEditingController controller;
  final String query;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final double extent;

  static const double _padding = 10;

  /// The field's own height, and with it the header's. Derived from the text
  /// size, because at 200% a 44-point box is a field with the descenders cut
  /// off it.
  static double fieldHeightFor(BuildContext context) {
    final line = MediaQuery.textScalerOf(context).scale(16) * 1.25;
    return math.max(44, line + 22);
  }

  static double extentFor(BuildContext context) =>
      fieldHeightFor(context) + _padding * 2;

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    return Container(
      height: extent,
      // Opaque, because rows pass under it. A translucent pinned bar over a
      // moving list is the one place a blur costs more than it says.
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, _padding, 16, _padding),
      child: Column(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              decoration: InputDecoration(
                isDense: true,
                constraints: BoxConstraints.tightFor(
                  height: fieldHeightFor(context),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                hintText: 'profile.search_providers_hint'.tr(),
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'general.clear'.tr(),
                        onPressed: onClear,
                        icon: const Icon(Icons.close, size: 18),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_SearchBarHeader old) =>
      old.query != query || old.extent != extent;
}

/// One row of language chips under the source-type filter.
class _LanguageRow extends StatelessWidget {
  const _LanguageRow({
    required this.languages,
    required this.selected,
    required this.onPick,
  });

  final List<MapEntry<String, int>> languages;
  final String? selected;
  final ValueChanged<String?> onPick;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    Widget chip(String? code, String label) {
      final on = selected == code;
      return ChoiceChip(
        label: Text(label),
        selected: on,
        showCheckmark: false,
        selectedColor: colors.primaryContainer,
        labelStyle: TextStyle(
          color: on ? colors.onPrimaryContainer : colors.onSurface,
          fontSize: 13,
        ),
        onSelected: (_) {
          HapticFeedback.selectionClick();
          onPick(on ? null : code);
        },
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.translate_rounded, size: 18),
              const SizedBox(width: 8),
              Text(
                'sources.filter_language'.tr(),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                chip(null, 'sources.eco_all'.tr()),
                for (final e in languages) ...[
                  const SizedBox(width: 8),
                  chip(e.key, '${labelFor(e.key)} · ${e.value}'),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
