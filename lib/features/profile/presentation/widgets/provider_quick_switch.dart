import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:soplay/core/content/catalogue.dart';
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
  if (candidates.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('mode.none_installed'.tr(args: [mode.labelKey.tr()])),
      ),
    );
    return;
  }
  final favIds = hive.getFavoriteProviders().toSet();
  final pick = candidates.firstWhere(
    (p) => favIds.contains(p.id),
    orElse: () => candidates.first,
  );

  await hive.setContentMode(mode.id);
  if (!context.mounted) return;

  // Subscribed BEFORE the pick is dispatched, or the reload it triggers can
  // land before anyone is listening and the cover would wait out its whole
  // timeout over content that is already there.
  //
  // Only when the provider actually changes: MainPage reloads Home off the
  // provider id moving, so an unchanged id means no reload to wait for and
  // this would be a future that never completes.
  final Future<void>? loaded = pick.id == state.currentProviderId
      ? null
      : context
            .read<HomeBloc>()
            .stream
            .firstWhere((s) => s is HomeLoaded || s is HomeError)
            .then((_) {});

  // Selected BEFORE the animation, so the reload runs underneath the cover
  // rather than starting when it lifts onto an empty screen.
  bloc.add(ProviderSelect(pick.id));
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
      ContentMode.video,
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

  /// Below this the filter is chrome over a list that already fits.
  static const int _filterThreshold = 8;

  /// One source row. Fixed so the sheet can open ON the current source: a
  /// builder with variable rows can only be scrolled to a position it has
  /// already laid out, and the current source is usually far below the fold.
  static const double _tileExtent = 56;

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
                        itemBuilder: (context, index) => _favoriteProviderTile(
                          context,
                          items[index],
                          widget.currentProviderId,
                          favorite: index < favorites.length,
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
          // Wraps rather than scrolls sideways: at 200% text three mode names
          // do not fit one line, and a row that clips is worse than a row that
          // takes two.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in ContentMode.values)
                _ModeChip(
                  key: _chipKeys[m],
                  label: m.labelKey.tr(),
                  accent: m.accent,
                  active: m == widget.mode,
                  onTap: m == widget.mode
                      ? null
                      : () {
                          widget.onModeTap?.call(_rectOf(_chipKeys[m]));
                          Navigator.of(context).pop('$_kModePrefix${m.id}');
                        },
                ),
            ],
          ),
          // Catalogues before the sources. A catalogue is what to browse when
          // no single source is the point — AniList's or TMDB's view of what
          // exists, with the app finding a source for whatever you open.
          // Video only: the two catalogues here are anime and film, and a
          // manga catalogue would be a promise the tap cannot keep yet.
          if (widget.mode == ContentMode.video) ...[
            const SizedBox(height: _pinnedPad),
            // Wraps like the mode chips above it: at 200% text the label and
            // two pills do not fit one line on a narrow phone.
            Wrap(
              spacing: 6,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 4),
                  child: Text(
                    'catalogue.section'.tr().toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                for (final c in Catalogue.values)
                  _ModeChip(
                    key: _catalogueKeys[c],
                    label: c.labelKey.tr(),
                    icon: Icons.auto_awesome_rounded,
                    accent: c.accent,
                    active: widget.currentProviderId == c.id,
                    onTap: widget.currentProviderId == c.id
                        ? null
                        : () {
                            widget.onModeTap?.call(_rectOf(_catalogueKeys[c]));
                            Navigator.of(
                              context,
                            ).pop('$_kCataloguePrefix${c.id}');
                          },
                  ),
              ],
            ),
          ],
          if (_hasFilter) ...[
            const SizedBox(height: _pinnedPad),
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
class _ModeChip extends StatelessWidget {
  const _ModeChip({
    super.key,
    required this.label,
    required this.active,
    required this.accent,
    this.onTap,
    this.icon,
  });

  final String label;
  final bool active;

  /// A catalogue chip carries a sign, so the two rows read as one family
  /// with one difference rather than two components that happen to be near
  /// each other.
  final IconData? icon;

  /// The mode's own colour, and the only place outside the switch animation
  /// where it is used: the chip that starts the switch should be the colour
  /// the switch will be.
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      child: Material(
        color: active ? accent : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Center(
              widthFactor: 1,
              heightFactor: 1,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 15, color: active ? Colors.white : accent),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      color: active ? Colors.white : AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Widget _favoriteProviderTile(
  BuildContext context,
  ProviderEntity p,
  String currentProviderId, {
  bool favorite = false,
}) {
  final selected = p.id == currentProviderId;
  return ListTile(
    leading: ProviderLogo(image: p.image, size: 36),
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
    trailing: selected
        ? Icon(Icons.check_rounded, color: AppColors.primary, size: 20)
        : favorite
        ? const Icon(Icons.star_rounded, color: Colors.amber, size: 20)
        : null,
    onTap: () => Navigator.of(context).pop(p.id),
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
