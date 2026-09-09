import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:soplay/core/content/content_mode.dart';
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
  if (state is! ProviderLoaded) return;
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
    ContentMode mode,
  ) async {
    final hive = getIt<HiveService>();
    final candidates = [
      for (final p in state.providers)
        if (state.isUsable(p) && p.id.contentMode == mode) p,
    ];
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('mode.none_installed'.tr(args: [mode.labelKey.tr()]))),
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
        : context.read<HomeBloc>().stream
              .firstWhere((s) => s is HomeLoaded || s is HomeError)
              .then((_) {});

    // Selected BEFORE the animation, so the reload runs underneath the cover
    // rather than starting when it lifts onto an empty screen.
    bloc.add(ProviderSelect(pick.id));
    await ModeSwitchOverlay.play(context, mode, until: loaded);
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
    final result = await showAdaptiveModal<String>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ProviderQuickSwitchSheet(
        favorites: [for (final f in favorites) if (f.id.contentMode == mode) f],
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
    final switched = ContentMode.values
        .where((m) => result == '$_kModePrefix${m.id}')
        .firstOrNull;
    if (switched != null) {
      await _switchMode(context, bloc, state, switched);
      return;
    }
    bloc.add(ProviderSelect(result));
  }

const String _kAllProvidersAction = '__all_providers__';

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
class _ProviderQuickSwitchSheet extends StatefulWidget {
  const _ProviderQuickSwitchSheet({
    required this.favorites,
    required this.all,
    required this.mode,
    required this.currentProviderId,
  });

  final List<ProviderEntity> favorites;
  final List<ProviderEntity> all;

  /// The kind of catalogue these sources belong to. Shown as a row of chips at
  /// the top, because the mode is the thing that decides what the rest of the
  /// sheet contains — putting it anywhere else would make the list look like it
  /// had lost sources.
  final ContentMode mode;

  final String currentProviderId;

  @override
  State<_ProviderQuickSwitchSheet> createState() =>
      _ProviderQuickSwitchSheetState();
}

class _ProviderQuickSwitchSheetState extends State<_ProviderQuickSwitchSheet> {
  final TextEditingController _filter = TextEditingController();
  String _query = '';

  /// Below this the filter is chrome over a list that already fits.
  static const int _filterThreshold = 8;

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
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
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    final favorites = _shownFavorites;
    final rest = _rest;
    // Tall enough to be worth opening, short enough to leave the home screen
    // visible behind it — this is a switch, not a destination.
    final maxHeight = MediaQuery.sizeOf(context).height * 0.72;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            // Mode first. It is the widest cut, and every other row below is
            // filtered by it.
            SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsetsDirectional.only(start: 16, end: 16),
                children: [
                  for (final m in ContentMode.values) ...[
                    _ModeChip(
                      label: m.labelKey.tr(),
                      active: m == widget.mode,
                      onTap: m == widget.mode
                          ? null
                          : () => Navigator.of(context).pop('$_kModePrefix${m.id}'),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (widget.all.length >= _filterThreshold)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: _filter,
                  onChanged: (v) => setState(() => _query = v),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: AppColors.surfaceVariant,
                    hintText: 'profile.search_providers_hint'.tr(),
                    hintStyle: const TextStyle(
                      color: AppColors.textHint,
                      fontSize: 13.5,
                    ),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      size: 19,
                      color: AppColors.textHint,
                    ),
                    prefixIconConstraints: const BoxConstraints(minWidth: 40),
                    contentPadding: const EdgeInsets.symmetric(vertical: 11),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(11),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: [
                  if (favorites.isNotEmpty) ...[
                    _sectionLabel(
                      icon: Icons.star,
                      iconColor: Colors.amber,
                      text: 'profile.favorites'.tr(),
                    ),
                    for (final p in favorites)
                      _favoriteProviderTile(context, p, widget.currentProviderId),
                  ],
                  if (rest.isNotEmpty) ...[
                    _sectionLabel(
                      icon: Icons.apps_rounded,
                      iconColor: AppColors.textSecondary,
                      text: 'profile.all_providers'.tr(),
                    ),
                    for (final p in rest)
                      _favoriteProviderTile(context, p, widget.currentProviderId),
                  ],
                  if (favorites.isEmpty && rest.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                      child: Text(
                        'profile.no_providers_in_category'.tr(),
                        style: const TextStyle(
                          color: AppColors.textHint,
                          fontSize: 13,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Divider(color: AppColors.divider, height: 1),
            // Still here, but now for MANAGING sources — favouriting, testing,
            // installing — rather than for the everyday act of picking one.
            ListTile(
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.tune_rounded,
                  color: AppColors.textSecondary,
                  size: 18,
                ),
              ),
              title: Text(
                'profile.section_providers'.tr(),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              trailing: const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textHint,
                size: 20,
              ),
              onTap: () => Navigator.of(context).pop(_kAllProvidersAction),
            ),
            SizedBox(height: bottomPad + 8),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel({
    required IconData icon,
    required Color iconColor,
    required String text,
  }) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 16),
            const SizedBox(width: 8),
            Text(
              text,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      );
}

/// One of the three catalogue kinds.
///
/// The active one is not tappable: switching to the mode you are already in
/// would replay the animation and reload the screen for no change, which reads
/// as the app stuttering.
class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.label, required this.active, this.onTap});

  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      child: Material(
        color: active ? AppColors.primary : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Center(
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
      ),
    );
  }
}

Widget _favoriteProviderTile(
  BuildContext context,
  ProviderEntity p,
  String currentProviderId,
) {
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
        : null,
    onTap: () => Navigator.of(context).pop(p.id),
  );
}


class ProviderLogo extends StatelessWidget {
  const ProviderLogo({
    required this.image,
    required this.size,
    super.key,
  });

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
