import 'dart:async';
import 'dart:ui';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:soplay/core/deeplink/deeplink_opt_in.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/system/nav_prefs.dart';
import 'package:soplay/core/system/platform_utils.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/app_updater/presentation/services/update_checker.dart';
import 'package:soplay/features/home/presentation/bloc/home/home_bloc.dart';
import 'package:soplay/features/home/presentation/bloc/home/home_event.dart';
import 'package:soplay/features/home/presentation/bloc/home/home_state.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_bloc.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_state.dart';
import 'package:soplay/features/search/presentation/blocs/search_bloc.dart';
import 'package:showcaseview/showcaseview.dart';

import '../../../../core/navigation/app_tab.dart';
import '../../../../core/navigation/nav_controller.dart';

/// Addressed by name, never through `ShowcaseView.get()`: that returns the most recently
/// registered instance, so opening a detail page — which registers its own private scope —
/// silently rebound this page's showcases to it. When the detail page went away it took the
/// scope with it and the nav capsule threw on its next rebuild.
const String _showcaseScope = 'main-nav';


class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> with WidgetsBindingObserver {
  final GlobalKey _shortsRefreshShowcaseKey = GlobalKey();
  int _index = 0;
  int _shortsRefreshTick = 0;
  List<TabId> _visibleTabs = const [];
  late final NavController _navController;
  late final HiveService _hiveService;
  String? _lastProviderId;
  bool _shortsShowcaseStarted = false;

  // ---- Android TV shell state (unused on phone/desktop) ----
  /// Scope owning the rail's buttons. `requestFocus()` on it restores the rail
  /// item the D-pad last sat on, which is how BACK returns from the content.
  final FocusScopeNode _tvRailScope = FocusScopeNode(debugLabel: 'tvRail');

  /// One scope per tab so switching away and back restores the exact widget the
  /// D-pad was on, instead of dumping focus at the top of the page.
  final Map<TabId, FocusScopeNode> _tvTabScopes = {};

  /// True while focus sits inside the tab body rather than on the rail. Drives
  /// [PopScope.canPop] so BACK means "leave the content" before it means "go
  /// Home", and only then "exit the app".
  bool _tvContentFocused = false;

  FocusScopeNode _tvScopeFor(TabId id) => _tvTabScopes.putIfAbsent(
      id, () => FocusScopeNode(debugLabel: 'tvTab.${id.name}'));

  int get _shortsIndex => _visibleTabs.indexOf(TabId.shorts); // -1 if hidden
  int get _homeIndex {
    final i = _visibleTabs.indexOf(TabId.home);
    return i < 0 ? 0 : i;
  }

  @override
  void initState() {
    super.initState();
    _navController = getIt<NavController>();
    _hiveService = getIt<HiveService>();
    // Reflect the persisted nav-style preference into the shared notifier the
    // nav listens to (so it renders correctly on first frame).
    NavPrefs.navStyle.value = _hiveService.navStyle;
    // TV runs a fixed tab set — the customizer is drag-driven and hidden there,
    // and the persisted mobile order is left completely untouched (never read,
    // never written) so a user's phone bar survives round-tripping.
    _visibleTabs =
        isTvPlatform ? List.of(kTvTabs) : sanitizeTabOrder(_hiveService.tabOrder);
    NavPrefs.tabOrder.value = _hiveService.tabOrder;
    NavPrefs.tabOrder.addListener(_onTabSetChange);
    _navController.tabIndexResolver = (id) => _visibleTabs.indexOf(id);
    _navController.index.addListener(_onNavChange);
    WidgetsBinding.instance.addObserver(this);
    ShowcaseView.register(
      scope: _showcaseScope,
      blurValue: 1.5,
      overlayColor: Colors.black,
      overlayOpacity: 0.76,
      onFinish: _markShortsShowcaseSeen,
      onDismiss: (_) => _markShortsShowcaseSeen(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!isDesktopPlatform) {
        getIt<UpdateChecker>().run(context);
        // The deeplink opt-in walks the user into the Android "open by default"
        // settings screen, which does not exist on leanback — skip on TV.
        if (!isTvPlatform) DeeplinkOptIn.maybePrompt(context);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && mounted && !isDesktopPlatform) {
      getIt<UpdateChecker>().run(context);
    }
  }

  void _onNavChange() {
    setState(() => _index = _navController.index.value);
    _maybeShowShortsRefreshTip();
  }

  // The user changed the tab set in Settings → Appearance. Keep the SAME tab
  // selected if it survived; otherwise fall back to Home.
  void _onTabSetChange() {
    // TV's tab set is fixed; ignore customizer writes that reach us anyway.
    if (isTvPlatform) return;
    final currentId = (_index >= 0 && _index < _visibleTabs.length)
        ? _visibleTabs[_index]
        : TabId.home;
    final next = sanitizeTabOrder(NavPrefs.tabOrder.value);
    setState(() {
      _visibleTabs = next;
      final keep = next.indexOf(currentId);
      _index = keep >= 0 ? keep : _homeIndex;
    });
    _navController.goTo(_index);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _navController.index.removeListener(_onNavChange);
    NavPrefs.tabOrder.removeListener(_onTabSetChange);
    ShowcaseView.getNamed(_showcaseScope).unregister();
    _tvRailScope.dispose();
    for (final n in _tvTabScopes.values) {
      n.dispose();
    }
    super.dispose();
  }

  void _onProviderStateChange(BuildContext context, ProviderState state) {
    if (state is! ProviderLoaded) return;
    final newId = state.currentProviderId;
    if (_lastProviderId == null) {
      _lastProviderId = newId;
      // HomePage.initState already fires a (non-silent) HomeLoad the moment the
      // shell mounts. Kicking a second one here while that is still in flight
      // runs BOTH handlers concurrently (bloc's default transformer), and the
      // late completion re-emits HomeLoaded/HomeError — churning HomeContent
      // through extra mounts. Only load if nothing is in flight or landed.
      final homeState = context.read<HomeBloc>().state;
      if (homeState is! HomeLoaded && homeState is! HomeLoading) {
        context.read<HomeBloc>().add(HomeLoad(silent: true));
      }
      return;
    }
    if (_lastProviderId == newId) return;
    _lastProviderId = newId;
    context.read<HomeBloc>().add(HomeLoad(silent: true));
    context.read<SearchBloc>().add(const SearchLoad());
  }

  void _onTabTap(int index) {
    setState(() => _index = index);
    _navController.goTo(index);
    _maybeShowShortsRefreshTip();
  }

  // The glass capsule has no per-tab double-tap, so re-tapping the already-active
  // Shorts tab refreshes the reel (the packaged bar fires onTabSelected on active
  // re-taps). Capture the "was already selected" state before _onTabTap mutates
  // _index.
  void _handleTabTap(int index) {
    final reselected = index == _index;
    _onTabTap(index);
    if (reselected && _shortsIndex >= 0 && index == _shortsIndex) {
      _refreshShorts();
    }
  }

  void _refreshShorts() {
    if (_shortsIndex < 0 || _index != _shortsIndex) return;
    setState(() => _shortsRefreshTick++);
  }

  void _maybeShowShortsRefreshTip() {
    if (_shortsIndex < 0 ||
        _index != _shortsIndex ||
        _shortsShowcaseStarted ||
        _hiveService.hasSeenShortsRefreshShowcase) {
      return;
    }
    _shortsShowcaseStarted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Future<void>.delayed(const Duration(milliseconds: 420), () {
        if (!mounted) return;
        if (_shortsIndex < 0 || _index != _shortsIndex) {
          _shortsShowcaseStarted = false;
          return;
        }
        ShowcaseView.getNamed(_showcaseScope).startShowCase([_shortsRefreshShowcaseKey]);
      });
    });
  }

  void _markShortsShowcaseSeen() {
    if (_hiveService.hasSeenShortsRefreshShowcase) return;
    unawaited(_hiveService.markShortsRefreshShowcaseSeen());
  }

  // ---------------------------------------------------------------- TV shell

  /// TV only. Gives every tab its own [FocusScope] and makes the inactive ones
  /// unfocusable.
  ///
  /// The `ExcludeFocus` is not optional: [IndexedStack] lays its hidden children
  /// out at full size and only skips PAINTING them, so their focus nodes stay
  /// registered at real screen coordinates. Without this the D-pad walks
  /// straight into an invisible tab and OK fires an unseen action.
  Widget _tvWrapTab(Widget page, TabId id, bool active) {
    if (!isTvPlatform) return page;
    return FocusScope(
      node: _tvScopeFor(id),
      child: ExcludeFocus(excluding: !active, child: page),
    );
  }

  /// Rail → content. Prefers the widget this tab was last on; falls back to the
  /// first focusable one.
  void _tvEnterContent() {
    if (_index < 0 || _index >= _visibleTabs.length) return;
    final scope = _tvScopeFor(_visibleTabs[_index]);
    final last = scope.focusedChild;
    if (last != null && last.canRequestFocus) {
      last.requestFocus();
      return;
    }
    scope.requestFocus();
    scope.nextFocus();
  }

  /// Focus-follows-selection on the rail: arrowing up/down switches the tab
  /// live. Cheap because [IndexedStack] keeps every tab mounted — this only
  /// changes which one is painted.
  void _tvFocusTab(int index) {
    if (index == _index) return;
    _onTabTap(index);
  }

  Widget _buildTvShell(List<Widget> tabs, List<AppTabDef> defs) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Content is inset by the rail's COLLAPSED width. The rail expands
          // over the top of it (see below), so gaining focus never reflows the
          // page underneath.
          Positioned.fill(
            left: _TvNavRail.collapsedWidth,
            child: Focus(
              // Not focusable itself — it exists purely to observe whether
              // focus is anywhere inside the tab body, which BACK keys off.
              canRequestFocus: false,
              skipTraversal: true,
              onFocusChange: (inside) {
                if (_tvContentFocused == inside) return;
                setState(() => _tvContentFocused = inside);
              },
              child: IndexedStack(index: _index, children: tabs),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: _TvNavRail(
              index: _index,
              items: defs,
              scope: _tvRailScope,
              onFocusItem: _tvFocusTab,
              onEnterContent: _tvEnterContent,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final defs = [for (final id in _visibleTabs) kTabRegistry[id]!];
    final tabs = <Widget>[
      for (var i = 0; i < defs.length; i++)
        KeyedSubtree(
          // Stable per-tab key so reordering the bar MOVES a page (keeping its
          // State) instead of rebuilding it at a new index — which was
          // re-mounting Home and re-firing its "Join Telegram" sheet.
          key: ValueKey(defs[i].id),
          // No-op off TV: returns the page widget unchanged.
          child: _tvWrapTab(
            defs[i].builder(TabBuildContext(
              isActive: _index == i,
              shortsRefreshTick: _shortsRefreshTick,
            )),
            defs[i].id,
            _index == i,
          ),
        ),
    ];

    // Hide the floating bottom nav while a keyboard is open (e.g. searching),
    // otherwise it rides up and floats over the keyboard.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: BlocListener<ProviderBloc, ProviderState>(
        listener: _onProviderStateChange,
        child: PopScope(
          // TV adds one step in front of the existing rule: BACK first leaves
          // the content for the rail, THEN goes Home, THEN exits. Phone and
          // desktop keep `_index == _homeIndex` exactly as before.
          canPop: isTvPlatform
              ? (!_tvContentFocused && _index == _homeIndex)
              : _index == _homeIndex,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (isTvPlatform && _tvContentFocused) {
              // Restores the rail's last-focused button (the active tab).
              _tvRailScope.requestFocus();
              return;
            }
            setState(() => _index = _homeIndex);
            _navController.goTo(_homeIndex);
          },
          child: isTvPlatform
              ? _buildTvShell(tabs, defs)
              : isDesktopPlatform
              ? Scaffold(
                  backgroundColor: AppColors.background,
                  body: Stack(
                    children: [
                      Positioned.fill(
                        child: IndexedStack(index: _index, children: tabs),
                      ),
                      // Sozo-Desktop: floating bottom-center rounded pill nav
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 18),
                          child: _SoplayFloatingNav(
                            index: _index,
                            onTap: _onTabTap,
                            items: defs,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : Scaffold(
                  backgroundColor: AppColors.background,
                  extendBody: true,
                  body: Stack(
                    children: [
                      // The tab body is OUTSIDE the nav-style listener so switching
                      // the nav style never re-mounts the tabs (that remount was
                      // re-triggering the Home "Join Telegram" sheet).
                      Positioned.fill(
                        child: IndexedStack(index: _index, children: tabs),
                      ),
                      if (!keyboardOpen)
                        Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: ValueListenableBuilder<String>(
                          valueListenable: NavPrefs.navStyle,
                          builder: (context, style, _) {
                            // Classic: the original full-width frosted bar (keeps
                            // the per-tab Showcase + real double-tap-to-refresh).
                            if (style == NavPrefs.classic) {
                              return _SoplayClassicBar(
                                index: _index,
                                items: defs,
                                shortsShowcaseKey: _shortsRefreshShowcaseKey,
                                onTap: _onTabTap,
                                onShortsDoubleTap: _refreshShorts,
                              );
                            }
                            // Glass / Solid: a floating capsule inset 16 each side.
                            return Padding(
                              padding: EdgeInsets.fromLTRB(
                                16,
                                0,
                                16,
                                MediaQuery.paddingOf(context).bottom + 12,
                              ),
                              child: _SoplayGlassCapsule(
                                index: _index,
                                items: defs,
                                glass: style == NavPrefs.glass,
                                shortsShowcaseKey: _shortsRefreshShowcaseKey,
                                onTabSelected: _handleTabTap,
                              ),
                            );
                          },
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

/// iOS-26 "Liquid Glass" FLOATING capsule — the MOBILE bottom nav.
///
/// Built on liquid_glass_widgets' [GlassTabBar.bottom]. Mounted only from the
/// mobile Scaffold branch as a bottom-center overlay with `extendBody: true`, so
/// the content scrolling behind it is refracted/blurred (native iOS-26 look).
/// Desktop keeps [_SoplayFloatingNav]; this is never mounted on desktop, and the
/// glass shaders are pre-warmed / wrapped mobile-only in main.dart.
///
/// The packaged bar exposes no per-tab GlobalKey or double-tap, so: the Shorts
/// refresh Showcase highlights the whole capsule (Shorts is the central tab),
/// and double-tap-to-refresh becomes re-tapping the already-active Shorts tab
/// (see [_MainPageState._handleTabTap]).
class _SoplayGlassCapsule extends StatelessWidget {
  const _SoplayGlassCapsule({
    required this.index,
    required this.items,
    required this.glass,
    required this.shortsShowcaseKey,
    required this.onTabSelected,
  });

  final int index;
  final List<AppTabDef> items;

  /// When false, render a shader-free solid dark capsule (lighter for weak
  /// devices / users who turned liquid glass off in Profile → Appearance).
  final bool glass;

  final GlobalKey shortsShowcaseKey;
  final ValueChanged<int> onTabSelected;

  static const double _barHeight = 62;

  // Refractive dark glass — matches the app's dark surfaces (dark backer pad).
  // The rim is deliberately quiet: a bright specular edge on a dark capsule
  // reads as a drawn outline rather than as glass, so the highlight, the
  // fresnel glow and the refraction band are all kept thin.
  // Not const: `backerColor` is the page background, and that is a runtime
  // value now — on AMOLED the pad has to go to true black with the rest of the
  // app instead of staying a #1A1A1A slab floating on nothing.
  static LiquidGlassSettings get _glassSettings => LiquidGlassSettings(
    thickness: 14, // narrower edge band → a finer rim, not a fat outline
    blur: 5, // less haze behind the bar → cleaner, not muddy
    chromaticAberration: 0.08, // barely-there edge tint
    refractiveIndex: 1.5,
    saturation: 1.08,
    lightIntensity: 0.6, // soft top-edge sheen instead of a hard stroke
    ambientStrength: 1,
    glowIntensity: 0.25, // faint luminous rim
    glassColor: const Color(0x12FFFFFF), // faint white sheen
    // Near-solid pad → premium, not hazy. #181818 at 90% on the default theme,
    // which is where the old #1A1A1A literal sat.
    backerColor: AppColors.background.withValues(alpha: 0.902),
    whitenStrength: 0.0,
  );

  // Solid (glass off): a near-opaque dark pad, no blur/refraction — the cheap,
  // always-smooth path.
  static LiquidGlassSettings get _solidSettings => LiquidGlassSettings(
    thickness: 0,
    blur: 0,
    chromaticAberration: 0,
    refractiveIndex: 1,
    saturation: 1,
    lightIntensity: 0,
    ambientStrength: 0,
    glassColor: const Color(0x00000000),
    backerColor: AppColors.background.withValues(alpha: 0.941), // ~94% solid
    whitenStrength: 0.0,
  );

  @override
  Widget build(BuildContext context) {
    final bar = GlassTabBar.bottom(
      tabs: [
        for (final it in items)
          GlassTab(
            label: it.labelKey.tr(),
            icon: Icon(it.icon),
            activeIcon: Icon(it.activeIcon),
          ),
      ],
      selectedIndex: index,
      onTabSelected: onTabSelected,
      // Outer Positioned(left:16,right:16) owns the float inset; the bar expands
      // to fill it (tabWidth null) and its own padding is zeroed.
      tabWidth: null,
      horizontalPadding: 0,
      verticalPadding: 0,
      barHeight: _barHeight,
      barBorderRadius: _barHeight / 2, // full capsule
      magnification: glass ? 1.12 : 1.0, // subtle iOS-26 lens on the selected tab
      indicatorPinchStrength: glass ? 0.3 : 0.0,
      // Selected-tab pill: a soft, restrained light pill on the dark body —
      // unless Appearance → "Colour the tab bar" is on, in which case the whole
      // selected state moves onto the accent. Off by default: the white pill is
      // a deliberate part of the shipped design, so it changes only when asked.
      indicatorColor: AppColors.isNavTinted
          ? AppColors.primary.withValues(alpha: glass ? 0.26 : 0.20)
          : Color(glass ? 0x22FFFFFF : 0x18FFFFFF),
      quality: glass ? null : GlassQuality.minimal,
      settings: glass ? _glassSettings : _solidSettings,
      // primaryLight, not primary: a selected icon is a small glyph on a dark
      // bar, and the lighter variant is the one that reads at that size.
      selectedIconColor:
          AppColors.isNavTinted ? AppColors.primaryLight : Colors.white,
      unselectedIconColor: const Color(0xFF7A7A7A),
      selectedLabelColor:
          AppColors.isNavTinted ? AppColors.primaryLight : Colors.white,
      unselectedLabelColor: const Color(0xFF7A7A7A),
      labelFontSize: 10.5,
    );

    // The package drop shadow is light-mode only, so paint our own soft capsule
    // shadow behind the glass for the "floating" look on the dark UI.
    //
    // A black shadow only separates the bar from a background that is lighter
    // than black. Under AMOLED both are #000000 and the capsule dissolves into
    // the page, so there it swaps to a faint light halo — the only direction a
    // true-black page leaves to work in.
    final shadowed = Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_barHeight / 2),
                boxShadow: [
                  AppColors.isBlack
                      ? BoxShadow(
                          color: Colors.white.withValues(alpha: 0.10),
                          blurRadius: 18,
                          spreadRadius: -6,
                        )
                      : const BoxShadow(
                          color: Color(0x66000000),
                          blurRadius: 24,
                          spreadRadius: -4,
                          offset: Offset(0, 10),
                        ),
                ],
              ),
            ),
          ),
        ),
        bar,
      ],
    );

    // No per-tab key on the packaged bar → the Showcase spotlights the whole
    // capsule (Shorts is the visually central tab). Register/start/seen flow is
    // unchanged.
    return Showcase.withWidget(
      key: shortsShowcaseKey,
      tooltipPosition: TooltipPosition.top,
      targetBorderRadius: BorderRadius.circular(_barHeight / 2),
      targetPadding: const EdgeInsets.all(6),
      targetTooltipGap: 14,
      overlayColor: Colors.black,
      overlayOpacity: 0.76,
      blurValue: 1.5,
      container: const _ShortsRefreshShowcaseCard(),
      child: shadowed,
    );
  }
}

/// Classic full-width frosted bottom bar — the ORIGINAL mobile nav, offered as a
/// style option (Profile → Appearance). Unlike the glass capsule it keeps the
/// per-tab Showcase anchor and double-tap-to-refresh, since each tab is its own
/// [_ClassicNavButton].
class _SoplayClassicBar extends StatelessWidget {
  const _SoplayClassicBar({
    required this.index,
    required this.items,
    required this.shortsShowcaseKey,
    required this.onTap,
    required this.onShortsDoubleTap,
  });

  final int index;
  final List<AppTabDef> items;
  final GlobalKey shortsShowcaseKey;
  final ValueChanged<int> onTap;
  final VoidCallback onShortsDoubleTap;

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          height: 68 + bottomPad,
          decoration: BoxDecoration(
            // A translucent frosted surface (not near-black) so content shows
            // through the blur and the bar reads as frosted glass. Follows the
            // palette, so AMOLED gets a genuinely black frosted bar.
            color: AppColors.surface.withValues(alpha: 0.72),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            border: Border(
              top: BorderSide(
                color: Colors.white.withValues(alpha: 0.10),
                width: 0.5,
              ),
            ),
          ),
          child: Padding(
            padding: EdgeInsets.only(
              top: 8,
              bottom: bottomPad == 0 ? 8 : bottomPad,
            ),
            child: Row(
              children: List.generate(
                items.length,
                (i) => Expanded(
                  child: _ClassicNavButton(
                    item: items[i],
                    selected: index == i,
                    showcaseKey: items[i].id == TabId.shorts
                        ? shortsShowcaseKey
                        : null,
                    onTap: () => onTap(i),
                    onDoubleTap: items[i].id == TabId.shorts
                        ? onShortsDoubleTap
                        : null,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ClassicNavButton extends StatefulWidget {
  const _ClassicNavButton({
    required this.item,
    required this.selected,
    required this.showcaseKey,
    required this.onTap,
    required this.onDoubleTap,
  });

  final AppTabDef item;
  final bool selected;
  final GlobalKey? showcaseKey;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;

  @override
  State<_ClassicNavButton> createState() => _ClassicNavButtonState();
}

class _ClassicNavButtonState extends State<_ClassicNavButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final selectedColor =
        AppColors.isNavTinted ? AppColors.primaryLight : Colors.white;
    final color = widget.selected ? selectedColor : const Color(0xFF7A7A7A);

    final button = Semantics(
      button: true,
      selected: widget.selected,
      label: widget.item.labelKey.tr(),
      onTap: widget.onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setPressed(true),
        onTapCancel: () => _setPressed(false),
        onTapUp: (_) => _setPressed(false),
        onTap: widget.onTap,
        onDoubleTap: widget.selected ? widget.onDoubleTap : null,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          scale: _pressed ? 0.92 : 1,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 120),
            opacity: _pressed ? 0.68 : 1,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedScale(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutBack,
                  scale: widget.selected ? 1.1 : 1,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    child: Icon(
                      widget.selected
                          ? widget.item.activeIcon
                          : widget.item.icon,
                      key: ValueKey('${widget.item.labelKey}-${widget.selected}'),
                      size: 24,
                      color: color,
                      shadows: widget.selected
                          ? [
                              Shadow(
                                color: selectedColor.withValues(alpha: 0.28),
                                blurRadius: 10,
                              ),
                            ]
                          : null,
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 160),
                  style: TextStyle(
                    color: color,
                    fontSize: 10.5,
                    fontWeight:
                        widget.selected ? FontWeight.w700 : FontWeight.w500,
                    height: 1,
                  ),
                  child: Text(
                    widget.item.labelKey.tr(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final key = widget.showcaseKey;
    if (key == null) return button;

    return Showcase.withWidget(
      key: key,
      tooltipPosition: TooltipPosition.top,
      targetBorderRadius: BorderRadius.circular(18),
      targetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      targetTooltipGap: 14,
      overlayColor: Colors.black,
      overlayOpacity: 0.76,
      blurValue: 1.5,
      container: const _ShortsRefreshShowcaseCard(),
      child: button,
    );
  }
}

/// Sozo-Desktop style floating bottom-center rounded pill navigation.
/// Desktop only — mobile uses [_SoplayGlassCapsule]. Reuses the same 5 tabs.
class _SoplayFloatingNav extends StatelessWidget {
  const _SoplayFloatingNav(
      {required this.index, required this.onTap, required this.items});

  final int index;
  final ValueChanged<int> onTap;
  final List<AppTabDef> items;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(9999));

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          // `outer` keeps the lift without darkening the content that now
          // shows through the translucent fill.
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.32),
            blurRadius: 28,
            offset: const Offset(0, 10),
            blurStyle: BlurStyle.outer,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.72),
              borderRadius: radius,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.10),
                width: 0.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < items.length; i++)
                  _NavCircle(
                    item: items[i],
                    selected: index == i,
                    onTap: () => onTap(i),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavCircle extends StatefulWidget {
  const _NavCircle({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final AppTabDef item;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NavCircle> createState() => _NavCircleState();
}

class _NavCircleState extends State<_NavCircle> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected;
    final color = active
        ? AppColors.primary
        : (_hover ? AppColors.textPrimary : AppColors.textSecondary);

    return Tooltip(
      message: widget.item.labelKey.tr(),
      preferBelow: false,
      verticalOffset: 34,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _hover ? 1.2 : 1.0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            child: Container(
              width: 50,
              height: 50,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active
                    ? AppColors.primary.withValues(alpha: 0.14)
                    : Colors.transparent,
              ),
              child: Icon(
                active ? widget.item.activeIcon : widget.item.icon,
                color: color,
                size: 22,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Android-TV navigation rail — the THIRD shell, mounted only when
/// [isTvPlatform]. The bottom pill (mobile glass capsule, desktop floating pill)
/// is a touch idiom; a 10-foot D-pad UI wants a vertical rail on the leading
/// edge, so this is a genuine third arm rather than a reuse of either.
///
/// It lives in a Stack ABOVE the content and animates 92 → 232 wide while it
/// holds focus, so showing the labels never reflows the page underneath.
///
/// Interaction model: focus-follows-selection (arrowing the rail switches the
/// tab live), OK or arrow-right hands focus to the tab body, BACK brings it back
/// (see [_MainPageState._buildTvShell] and the PopScope above it).
class _TvNavRail extends StatefulWidget {
  const _TvNavRail({
    required this.index,
    required this.items,
    required this.scope,
    required this.onFocusItem,
    required this.onEnterContent,
  });

  final int index;
  final List<AppTabDef> items;
  final FocusScopeNode scope;
  final ValueChanged<int> onFocusItem;
  final VoidCallback onEnterContent;

  static const double collapsedWidth = 92;
  static const double expandedWidth = 232;

  @override
  State<_TvNavRail> createState() => _TvNavRailState();
}

class _TvNavRailState extends State<_TvNavRail> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return FocusScope(
      node: widget.scope,
      onFocusChange: (hasFocus) {
        if (_expanded == hasFocus) return;
        setState(() => _expanded = hasFocus);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        width: _expanded
            ? _TvNavRail.expandedWidth
            : _TvNavRail.collapsedWidth,
        decoration: BoxDecoration(
          color: AppColors.navBackground,
          border: Border(
            right: BorderSide(color: AppColors.border, width: 0.6),
          ),
          boxShadow: _expanded
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 36,
                    offset: const Offset(10, 0),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < widget.items.length; i++)
              _TvRailButton(
                item: widget.items[i],
                selected: widget.index == i,
                expanded: _expanded,
                // Initial focus for the whole app lands on the active tab.
                autofocus: widget.index == i,
                onFocused: () => widget.onFocusItem(i),
                onActivate: widget.onEnterContent,
              ),
          ],
        ),
      ),
    );
  }
}

class _TvRailButton extends StatefulWidget {
  const _TvRailButton({
    required this.item,
    required this.selected,
    required this.expanded,
    required this.autofocus,
    required this.onFocused,
    required this.onActivate,
  });

  final AppTabDef item;
  final bool selected;
  final bool expanded;
  final bool autofocus;
  final VoidCallback onFocused;
  final VoidCallback onActivate;

  @override
  State<_TvRailButton> createState() => _TvRailButtonState();
}

class _TvRailButtonState extends State<_TvRailButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected || _focused;
    final color = active ? AppColors.textPrimary : AppColors.textSecondary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: InkWell(
        // InkWell is already focusable and already answers ActivateIntent, so
        // the remote's OK button works through it once app.dart binds
        // select/gameButtonA to that intent.
        autofocus: widget.autofocus,
        onTap: widget.onActivate,
        onFocusChange: (v) {
          setState(() => _focused = v);
          if (v) widget.onFocused();
        },
        borderRadius: BorderRadius.circular(12),
        // The focus ring below is the affordance; suppress the default wash.
        focusColor: Colors.transparent,
        hoverColor: Colors.transparent,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            color: _focused ? AppColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _focused ? AppColors.border : Colors.transparent,
              width: 0.6,
            ),
          ),
          child: Row(
            children: [
              // Brand accent as a 3px bar on the active tab — never a fill.
              AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOut,
                width: 3,
                height: widget.selected ? 20 : 0,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 11),
              Icon(
                widget.selected ? widget.item.activeIcon : widget.item.icon,
                size: 24,
                color: color,
              ),
              if (widget.expanded)
                // Expanded (not a fixed width) so the label can never overflow
                // mid-animation while the rail is still growing.
                Expanded(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 180),
                    opacity: widget.expanded ? 1 : 0,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Text(
                        widget.item.labelKey.tr(),
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: color,
                          fontSize: 14,
                          fontWeight:
                              widget.selected ? FontWeight.w800 : FontWeight.w600,
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

class _ShortsRefreshShowcaseCard extends StatelessWidget {
  const _ShortsRefreshShowcaseCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 276,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.navBackground.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.06),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [AppColors.primary, AppColors.primaryDark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.35),
                      blurRadius: 14,
                    ),
                  ],
                ),
                child: const Icon(
                  CupertinoIcons.arrow_2_circlepath,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'main.shorts_refresh_title'.tr(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'main.shorts_refresh_body'.tr(),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'main.tap_again'.tr(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => ShowcaseView.getNamed(_showcaseScope).dismiss(),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'general.ok'.tr(),
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
