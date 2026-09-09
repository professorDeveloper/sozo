import 'dart:async';
import 'dart:ui';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/navigation/app_tab.dart';
import 'package:soplay/core/navigation/nav_controller.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/download/domain/entities/download_status.dart';
import 'package:soplay/features/download/domain/usecases/get_downloads_usecase.dart';
import 'package:soplay/features/home/presentation/bloc/home/home_bloc.dart';
import 'package:soplay/features/home/presentation/bloc/home/home_state.dart';
import 'package:soplay/features/home/presentation/bloc/home/home_event.dart';
import 'package:soplay/features/notifications/domain/repositories/notifications_repository.dart';
import 'package:soplay/core/content/content_mode.dart';
import 'package:soplay/core/widgets/mode_switch_overlay.dart';
import 'package:soplay/features/profile/domain/entities/provider_entity.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_bloc.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_event.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_state.dart';
import 'package:soplay/features/profile/presentation/pages/profile_page.dart';
import 'package:soplay/features/streak/data/streak_service.dart';
import 'package:soplay/features/streak/domain/entities/streak_state.dart';
import 'package:soplay/features/streak/presentation/widgets/streak_badge.dart';

class HomeTopBar extends StatelessWidget {
  const HomeTopBar({super.key, required this.blurProgress});

  final double blurProgress;

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final progress = blurProgress.clamp(0.0, 1.0);

    // The bar reports state. It does not navigate.
    //
    // It had grown to five permanent actions beside the wordmark, source pill
    // and streak, which overflowed a 411dp phone by 18px and had to be scaled
    // down to fit — a row that shrinks to survive is a row with too much in it.
    // Every destination came out: search is already a default bottom tab, and
    // watch party, AniList and Live TV moved to Profile, which is where a place
    // you visit occasionally belongs. What is left is what TELLS you something
    // without being opened — the live source, the streak, a download in flight,
    // an unread count.
    final compact = MediaQuery.sizeOf(context).width < 430;
    final iconPad = compact ? 6.0 : 8.0;

    final actions = <Widget>[
      // First, and deliberately. This is the only place a viewer will notice
      // that history is being suppressed — the player's sheet is not somewhere
      // anyone opens to check. Renders nothing when incognito is off.
      _IncognitoIndicator(pad: iconPad),
      DesktopRefreshButton(
        color: AppColors.textPrimary,
        onRefresh: () => context.read<HomeBloc>().add(HomeLoad(silent: true)),
      ),
      // Streak sits with the other status, not next to the source pill.
      // Grouping the two things that report a count — a streak and an unread
      // badge — puts every "here is where you stand" signal in one place and
      // leaves the left side to say only what it is: the app, and the source.
      const StreakBadge(),
      _DownloadIndicator(pad: iconPad),
      _AnilistShortcut(pad: iconPad),
      // Search rides next to AniList, but yields to a live streak: when the
      // streak badge is showing its count the row is already full, so the
      // search icon steps aside and lives where it always has — the bottom tab.
      _SearchShortcut(pad: iconPad),
      _NotificationsIndicator(pad: iconPad),
    ];

    final bar = Padding(
      padding: EdgeInsetsDirectional.fromSTEB(20, topPad + 10, 12, 10),
      child: Row(
        children: [
          Text(
            'SOZO',
            style: TextStyle(
              color: AppColors.primary,
              fontSize: compact ? 18 : 22,
              fontWeight: FontWeight.w900,
              letterSpacing: compact ? 1.6 : 2.5,
              height: 1,
            ),
          ),
          SizedBox(width: compact ? 8 : 10),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: compact ? 116 : 170),
            child: const _ProviderSwitcher(),
          ),
          // The last line of defence: a transient download badge, a long streak
          // count or a large system font can still outgrow what is left, and a
          // strip that scales a few percent reads better than a yellow bar.
          // Expanded, not Flexible: a loose child shrinks to its own width and
          // then sits wherever the row left it, so the strip floated mid-bar
          // with dead space to its right. Filling the remainder is what lets
          // centerRight actually pin it to the edge.
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerEnd,
              child: Row(mainAxisSize: MainAxisSize.min, children: actions),
            ),
          ),
        ],
      ),
    );

    // The backdrop is a SIBLING painted behind the bar, never a parent of it.
    // It used to wrap `bar`, and the wrapper's TYPE changed as the blur kicked
    // in (Container -> RepaintBoundary/ClipRect/BackdropFilter), so crossing the
    // threshold while scrolling re-inflated the whole bar subtree — re-running
    // _NotificationsIndicatorState.initState (and its unread-count fetch) each
    // time. In a fixed Stack slot the bar's elements are only ever updated.
    return RepaintBoundary(
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(child: _TopBarBackground(progress: progress)),
          ),
          bar,
        ],
      ),
    );
  }
}

class _TopBarBackground extends StatelessWidget {
  const _TopBarBackground({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    if (progress < 0.01) {
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black.withValues(alpha: 0.80), Colors.transparent],
          ),
        ),
      );
    }

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14 * progress, sigmaY: 14 * progress),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.navBackground.withValues(alpha: 0.72 * progress),
            border: progress > 0.05
                ? Border(
                    bottom: BorderSide(
                      color: Colors.white.withValues(alpha: 0.07 * progress),
                      width: 0.5,
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

class _ProviderSwitcher extends StatelessWidget {
  const _ProviderSwitcher();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProviderBloc, ProviderState>(
      builder: (context, state) {
        if (state is! ProviderLoaded) return const SizedBox.shrink();
        final current = state.currentProvider;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _openSwitcher(context, state),
            child: Container(
              padding: const EdgeInsetsDirectional.fromSTEB(5, 4, 7, 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ProviderLogo(image: current?.image ?? '', size: 22),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      current?.name ?? '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: AppColors.textHint,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
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

  Future<void> _openSwitcher(BuildContext context, ProviderLoaded state) async {
    final bloc = context.read<ProviderBloc>();
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
    leading: _ProviderLogo(image: p.image, size: 36),
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

class _ProviderLogo extends StatelessWidget {
  const _ProviderLogo({required this.image, required this.size});

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

/// A tap target that matches the notification bell: same 24px icon, same
/// padding, so the row reads as one set of controls.
class _TopBarIconButton extends StatelessWidget {
  const _TopBarIconButton({
    required this.child,
    required this.onTap,
    this.pad = 8,
  });

  final Widget child;
  final VoidCallback onTap;
  final double pad;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: pad, vertical: 10),
          child: SizedBox(width: 24, height: 24, child: Center(child: child)),
        ),
      ),
    );
  }
}

class _AnilistShortcut extends StatelessWidget {
  const _AnilistShortcut({this.pad = 8});

  final double pad;

  @override
  Widget build(BuildContext context) {
    return _TopBarIconButton(
      pad: pad,
      onTap: () => context.push('/anilist'),
      child: SvgPicture.asset(
        'assets/icons/anilist.svg',
        width: 22,
        height: 22,
      ),
    );
  }
}

/// Search — but only while no streak is showing its count. A live streak fills
/// the row, so search yields and stays a bottom tab; without one it rides here.
class _SearchShortcut extends StatelessWidget {
  const _SearchShortcut({this.pad = 8});

  final double pad;

  @override
  Widget build(BuildContext context) {
    final streak = getIt<StreakService>();
    final loggedIn = getIt<HiveService>().isLoggedIn;
    return ValueListenableBuilder<StreakState>(
      valueListenable: streak.state,
      builder: (context, state, _) {
        final streakShowing = loggedIn && state.current > 0;
        if (streakShowing) return const SizedBox.shrink();
        return _TopBarIconButton(
          pad: pad,
          onTap: () {
            if (!getIt<NavController>().goToId(TabId.search)) {
              context.push('/cross-search');
            }
          },
          child: const Icon(
            Icons.search_rounded,
            color: Colors.white,
            size: 24,
          ),
        );
      },
    );
  }
}

class _NotificationsIndicator extends StatefulWidget {
  const _NotificationsIndicator({this.pad = 8});

  final double pad;

  @override
  State<_NotificationsIndicator> createState() =>
      _NotificationsIndicatorState();
}

class _NotificationsIndicatorState extends State<_NotificationsIndicator>
    with WidgetsBindingObserver {
  /// Floor on the spacing between two unread-count calls, whatever fires them.
  /// Shorter than the [_timer] period, so the intended 60s cadence always gets
  /// through while every *extra* trigger (a remount, a lifecycle resume moments
  /// after the last fetch, a second indicator that somehow outlived its widget)
  /// is dropped. Field evidence: eight identical
  /// GET /notifications/unread-count inside 7ms.
  static const Duration _minInterval = Duration(seconds: 45);

  /// Deliberately STATIC, not per-State: the throttle has to hold across
  /// instances, because the bursts came from triggers this widget cannot see
  /// from inside a single [State]. Overlapping callers await the same future,
  /// so N triggers in one tick can only ever produce one HTTP request — and
  /// every live instance still gets the result.
  static Future<Result<int>>? _inFlight;
  static DateTime? _lastFetch;

  /// Last known count, so a remount paints the badge immediately instead of
  /// flashing to 0 while (or instead of) fetching.
  static int _cachedCount = 0;

  final NotificationsRepository _repo = getIt<NotificationsRepository>();
  final HiveService _hive = getIt<HiveService>();
  Timer? _timer;
  int _count = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _count = _cachedCount;
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  /// [force] skips the cool-down (but never the in-flight coalescing) — used
  /// when the user just came back from /notifications or /login, where the
  /// count is expected to have changed right now.
  Future<void> _refresh({bool force = false}) async {
    if (!_hive.isLoggedIn) {
      _cachedCount = 0;
      if (_count != 0 && mounted) setState(() => _count = 0);
      return;
    }
    final last = _lastFetch;
    if (!force &&
        _inFlight == null &&
        last != null &&
        DateTime.now().difference(last) < _minInterval) {
      return;
    }
    // Every overlapping caller awaits the SAME request; the field is cleared
    // before the awaiters resume, so the next trigger starts a fresh one.
    final result = await (_inFlight ??= _repo.unreadCount().whenComplete(() {
      _lastFetch = DateTime.now();
      _inFlight = null;
    }));
    switch (result) {
      case Success(:final value):
        _cachedCount = value;
        if (mounted && value != _count) setState(() => _count = value);
      case Failure():
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () async {
          if (!_hive.isLoggedIn) {
            await context.push('/login');
            _refresh(force: true);
            return;
          }
          await context.push('/notifications');
          _refresh(force: true);
        },
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: widget.pad, vertical: 10),
          child: SizedBox(
            width: 24,
            height: 24,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(
                  Icons.notifications_none_rounded,
                  color: Colors.white,
                  size: 24,
                ),
                if (_count > 0)
                  Positioned(
                    right: -3,
                    top: -3,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      constraints: const BoxConstraints(
                        minWidth: 14,
                        minHeight: 14,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                          color: AppColors.navBackground,
                          width: 1.2,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          _count > 99 ? '99+' : '$_count',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                            height: 1,
                          ),
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
  }
}

class _DownloadIndicator extends StatefulWidget {
  const _DownloadIndicator({this.pad = 8});

  final double pad;

  @override
  State<_DownloadIndicator> createState() => _DownloadIndicatorState();
}

class _DownloadIndicatorState extends State<_DownloadIndicator>
    with SingleTickerProviderStateMixin {
  final GetDownloadsUseCase _downloads = getIt<GetDownloadsUseCase>();
  late final AnimationController _pulse;
  bool _hasActive = false;
  int _activeCount = 0;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _downloads.revision.addListener(_check);
    _check();
  }

  @override
  void dispose() {
    _downloads.revision.removeListener(_check);
    _pulse.dispose();
    super.dispose();
  }

  void _check() {
    if (!mounted) return;
    final items = _downloads();
    final active = items
        .where((i) => i.status == DownloadStatus.downloading)
        .length;
    final hasActive = active > 0;
    if (hasActive != _hasActive || active != _activeCount) {
      setState(() {
        _hasActive = hasActive;
        _activeCount = active;
      });
      if (hasActive) {
        _pulse.repeat();
      } else {
        _pulse.stop();
        _pulse.value = 0;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasActive) return const SizedBox.shrink();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => context.push('/downloads'),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: widget.pad, vertical: 10),
          child: SizedBox(
            width: 24,
            height: 24,
            child: Stack(
              children: [
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, _) => Icon(
                    Icons.download_rounded,
                    color: Color.lerp(
                      AppColors.primary,
                      Colors.white,
                      (_pulse.value * 2 - 1).abs(),
                    ),
                    size: 24,
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    constraints: const BoxConstraints(
                      minWidth: 12,
                      minHeight: 12,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Center(
                      child: Text(
                        _activeCount > 9 ? '9+' : '$_activeCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 7,
                          fontWeight: FontWeight.w900,
                          height: 1,
                        ),
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
  }
}


/// Shown on the home bar whenever incognito is on.
///
/// The mode persists across restarts, which is the right default for a privacy
/// setting but makes it easy to leave on for weeks — and the symptom is silent:
/// Continue Watching simply stays empty. A badge on the screen the viewer opens
/// first is what turns that into something they can see and undo.
///
/// Tapping asks before turning it off. A single tap silently disabling a
/// privacy mode is the wrong direction to fail in, and the dialog doubles as
/// the explanation for anyone who does not remember switching it on.
class _IncognitoIndicator extends StatefulWidget {
  const _IncognitoIndicator({this.pad = 8});

  final double pad;

  @override
  State<_IncognitoIndicator> createState() => _IncognitoIndicatorState();
}

class _IncognitoIndicatorState extends State<_IncognitoIndicator> {
  final HiveService _hive = getIt<HiveService>();

  @override
  void initState() {
    super.initState();
    _hive.incognitoChanged.addListener(_onChanged);
  }

  @override
  void dispose() {
    _hive.incognitoChanged.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _confirmOff() async {
    final off = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('profile.incognito'.tr()),
        content: Text('profile.incognito_active'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('general.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('profile.incognito_turn_off'.tr()),
          ),
        ],
      ),
    );
    if (off != true) return;
    await _hive.setIncognito(false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('profile.incognito_off'.tr()),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_hive.isIncognito) return const SizedBox.shrink();
    return _TopBarIconButton(
      pad: widget.pad,
      onTap: _confirmOff,
      child: Tooltip(
        message: 'profile.incognito'.tr(),
        child: Icon(
          Icons.visibility_off_rounded,
          // The one item in this bar that is a warning rather than a
          // shortcut, so it does not wear the same colour as the rest.
          color: AppColors.errorLight,
          size: 22,
        ),
      ),
    );
  }
}
