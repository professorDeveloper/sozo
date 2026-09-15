import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/features/home/data/datasources/home_data_source.dart';
import 'package:soplay/features/sources/domain/source_ecosystem.dart';
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
      if (state.isUsable(p) && p.id.contentMode == mode) p,
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
  });

  /// Reports where a mode chip was on screen when it was pressed, so the
  /// switch can open from there instead of from nowhere.
  final ValueChanged<Rect>? onModeTap;

  final List<ProviderEntity> favorites;
  final List<ProviderEntity> all;

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

  static const double _pinnedPad = 12;

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

  @override
  void dispose() {
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
    return [
      for (final p in widget.all)
        if (!favIds.contains(p.id) &&
            (q.isEmpty || p.name.toLowerCase().contains(q)))
          p,
    ];
  }

  List<ProviderEntity> get _shownFavorites {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.favorites;
    return [
      for (final p in widget.favorites)
        if (p.name.toLowerCase().contains(q)) p,
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
      // list rather than as the first thing in it. Nothing scrolls above the
      // rows any more, so the offset is the rows alone.
      final target = (index - 2) * _tileExtent;
      controller.jumpTo(target.clamp(0.0, controller.position.maxScrollExtent));
    });
  }

  Widget _body(BuildContext context, ScrollController controller) {
    final favorites = _shownFavorites;
    final items = [...favorites, ..._rest];
    _alignToCurrent(controller, items);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Pinned by construction: the title, the mode chips and the filter are
        // Column children, so scrolling the list underneath cannot carry them
        // away. They were the first rows OF the list, which meant scrolling two
        // hundred sources past the mode switcher and back up again to change
        // mode.
        _grabber(context),
        // Header and list share one flexible box, and the header's cap comes
        // from inside it.
        //
        // Flexible was wrong for the header on its own: a Column shares its
        // spare room between flexible children by flex, so a flexible header
        // and a flexible list took half each — which is why a long list used to
        // stop halfway down the screen. A fixed cap was wrong too: at 200% text
        // with the keyboard up, the footer alone is taller than half the sheet,
        // and the header had no room left to be capped into.
        //
        // The LayoutBuilder reports what is actually left once the grabber,
        // divider and footer have taken their natural heights, so the cap is
        // measured rather than guessed. The header takes what it needs up to
        // most of that, and the list — the one flexible child inside — takes
        // the rest. Short lists leave the Column hugging them; long ones fill.
        Flexible(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: constraints.maxHeight * 0.6,
                    ),
                    child: SingleChildScrollView(
                      child: _header(context, items),
                    ),
                  ),
                  // The note is not a row. Inside a fixed-extent list it had
                  // one row's height and two lines of text, which at large type
                  // overflowed by more than the row was tall.
                  if (items.isEmpty)
                    Flexible(
                      child: SingleChildScrollView(child: _emptyNote(context)),
                    )
                  else
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        controller: controller,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        // Fixed rows are what make the opening jump land on the
                        // right one.
                        itemExtent: _tileExtent,
                        itemCount: items.length,
                        itemBuilder: (context, index) => ItemAppear(
                          index: index,
                          child: _favoriteProviderTile(
                            context,
                            items[index],
                            widget.currentProviderId,
                            favorite: index < favorites.length,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
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

  /// Mode chips and filter — the part that stays put.
  ///
  /// Pinned, because scrolling two hundred sources past a mode switcher that
  /// has left the screen means scrolling back up to change mode, and the search
  /// box goes with it for the same reason.
  Widget _header(BuildContext context, List<ProviderEntity> items) {
    final catalogues = Catalogue.forMode(widget.mode);
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'ux.change_source'.tr(),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: _pinnedPad),
          _ModeSegments(
            keys: _chipKeys,
            active: widget.mode,
            pending: _pendingMode,
            onTap: _pickMode,
          ),
          // Catalogues before the sources. A catalogue is what to browse when
          // no single source is the point — AniList's or TMDB's view of what
          // exists, with the app finding a source for whatever you open.
          // Each mode has its own: AniList's anime shelf and TMDB for Watch,
          // AniList's manga and light-novel shelves for the readers.
          if (catalogues.isNotEmpty) ...[
            const SizedBox(height: _pinnedPad),
            _SectionLabel('catalogue.section'.tr()),
            const SizedBox(height: 8),
            // Two cards side by side where there are two; a lone card takes
            // the width. At 200% text a card's two lines still fit, because
            // the hint is the line that gives way.
            Row(
              children: [
                for (final (i, c) in catalogues.indexed) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: _CatalogueCard(
                      key: _catalogueKeys[c],
                      catalogue: c,
                      active: widget.currentProviderId == c.id,
                      onTap: widget.currentProviderId == c.id
                          ? null
                          : () {
                              HapticFeedback.selectionClick();
                              widget.onModeTap?.call(
                                _rectOf(_catalogueKeys[c]),
                              );
                              Navigator.of(
                                context,
                              ).pop('$_kCataloguePrefix${c.id}');
                            },
                    ),
                  ),
                ],
              ],
            ),
          ],
          const SizedBox(height: _pinnedPad),
          _SectionLabel('${'sources.section'.tr()} · ${widget.all.length}'),
          if (_hasFilter) ...[
            const SizedBox(height: 8),
            SizedBox(
              child: TextField(
                controller: _filter,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  hintText: 'profile.search_providers_hint'.tr(),
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'general.clear'.tr(),
                          onPressed: () {
                            _filter.clear();
                            setState(() => _query = '');
                          },
                          icon: const Icon(Icons.close, size: 18),
                        ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

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
          if (_query.isNotEmpty)
            TextButton(
              onPressed: () {
                _filter.clear();
                setState(() => _query = '');
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

  static const double _height = 68;

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
        height: _height,
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
            onTap: onTap,
            child: Stack(
              fit: StackFit.expand,
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
                  // to them instead of running under them.
                  padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 44, 0),
                  child: Row(
                    children: [
                      CatalogueLogo(catalogue: catalogue, size: 30),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
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
            child: SizedBox(
              width: 22 + w + step * (covers.length - 1),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (final (i, url) in covers.indexed)
                    PositionedDirectional(
                      start: 22 + step * i,
                      top:
                          (_CatalogueCard._height - h) / 2 + (i.isOdd ? 4 : -2),
                      child: Transform.rotate(
                        angle: lean + i * 0.06,
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
}) {
  final selected = p.id == currentProviderId;
  final eco = SourceEcosystem.of(p.id);
  final lang = inferLang(lang: p.lang, name: p.name, id: p.id, url: p.url);
  // Where it comes from and what language it speaks, in one small line:
  // the two things that tell "AnimeKAI" apart from "AnimeKAI" one row down.
  final meta = [
    eco.label,
    if (lang != null && lang.isNotEmpty) lang.toUpperCase(),
  ].join(' · ');
  return Material(
    color: selected
        ? AppColors.primary.withValues(alpha: 0.08)
        : Colors.transparent,
    child: ListTile(
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
        child: ProviderLogo(image: p.image, size: 36),
      ),
      title: Text(
        p.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: selected ? AppColors.textPrimary : AppColors.textSecondary,
          fontSize: 14,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
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
      onTap: () => Navigator.of(context).pop(p.id),
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
