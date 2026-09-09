import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/stats/presentation/watch_stats_page.dart';
import 'package:soplay/features/profile/presentation/widgets/home_rail_customizer_sheet.dart';
import 'package:soplay/features/profile/presentation/widgets/tab_customizer_sheet.dart';
import 'package:soplay/core/bridge/bridge_control.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/theme/app_theme.dart';
import 'package:soplay/features/profile/presentation/pages/appearance_page.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/system/desktop_window.dart';
import 'package:soplay/core/system/nav_prefs.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/features/app_lock/domain/repositories/app_lock_repository.dart';
import 'package:soplay/features/private_list/presentation/private_unlock.dart';
import 'package:soplay/features/auth/domain/entities/user_entity.dart';
import 'package:soplay/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:soplay/features/auth/presentation/bloc/auth_event.dart';
import 'package:soplay/features/auth/presentation/bloc/auth_state.dart';
import 'package:soplay/features/download/domain/usecases/get_downloads_usecase.dart';
import 'package:soplay/features/history/data/history_service.dart';
import 'package:soplay/features/streak/presentation/widgets/streak_card.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_bloc.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_event.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_state.dart';
import 'package:soplay/features/notifications/domain/repositories/notifications_repository.dart';
import 'package:soplay/features/profile/presentation/pages/about_page.dart';
import 'package:soplay/features/profile/presentation/pages/providers_page.dart';
import 'package:soplay/features/profile/presentation/pages/sources_page.dart';
import 'package:soplay/features/profile/presentation/widgets/settings_tiles.dart';
import 'package:soplay/features/stats/data/watch_stats_store.dart';
import 'package:soplay/features/anilist/data/anilist_service.dart';
import 'package:soplay/features/mal/data/mal_service.dart';
import 'package:soplay/features/mal/presentation/widgets/mal_brand.dart';
import 'package:soplay/features/anilist/presentation/widgets/anilist_brand.dart';
import 'package:soplay/features/anilist/presentation/widgets/anilist_logo.dart';
import 'package:soplay/features/watch_party/presentation/party_entry.dart';

// Split into parts the way player_page.dart is: the page was 2721 lines
// across nine sections, which is past the point where anyone can find
// anything in it. Parts keep every `_private` name private, so nothing had
// to be renamed or made public to move it.
part 'profile_page.header.dart';
part 'profile_page.hub.dart';
part 'profile_page.sections.dart';
part 'profile_page.appearance.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) => const _ProfileView();
}

class _ProfileView extends StatefulWidget {
  const _ProfileView();

  @override
  State<_ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<_ProfileView> {
  final _scrollController = ScrollController();
  final _headerBlur = ValueNotifier<double>(0.0);

  static const double _headerContentHeight = 58.0;

  // Desktop settings use a Sozo-Desktop style sidebar + panel layout.
  int _navIndex = 0;

  @override
  void initState() {
    super.initState();
    context.read<AuthBloc>().add(const AuthStarted());
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _headerBlur.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final next = (_scrollController.offset / 80.0).clamp(0.0, 1.0);
    if ((next - _headerBlur.value).abs() > 0.01) {
      _headerBlur.value = next;
    }
  }

  Future<void> _onRefresh() async {
    context.read<AuthBloc>().add(const AuthProfileRefreshRequested());
    context.read<ProviderBloc>().add(const ProviderLoad());
    await Future.delayed(const Duration(milliseconds: 800));
  }

  @override
  Widget build(BuildContext context) {
    if (isDesktopPlatform) return _buildDesktop(context);

    final topPad = MediaQuery.paddingOf(context).top;
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    final headerH = topPad + _headerContentHeight;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Accent-tinted at the top, falling to the page background. Used to
          // be the literals [#1E1416, #181818, #101010]; those are exactly what
          // these three resolve to at the default red, and they now follow the
          // chosen accent and darkness instead of staying red on a blue app.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.heroTop,
                  AppColors.heroMid,
                  AppColors.heroBottom,
                ],
                stops: const [0, 0.35, 1],
              ),
            ),
            child: const SizedBox.expand(),
          ),
          _ProfileScrollFrame(
            child: RefreshIndicator(
              onRefresh: _onRefresh,
              color: AppColors.primary,
              backgroundColor: AppColors.surface,
              edgeOffset: headerH,
              child: CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: SizedBox(height: headerH + 16)),
                  // One BlocBuilder over the whole list rather than a stack of
                  // fixed slivers with conditionals sprinkled through it.
                  //
                  // A guest cannot use the streak, a tracker connection or a TV
                  // pairing — all three bind to a Sozo account — and the old
                  // list still reserved their gaps, so signed out the page was
                  // a run of empty space with Settings pushed below the fold.
                  // Building the sections into a list means the spacing belongs
                  // to the sections that are actually there, and the reveal
                  // stagger renumbers itself.
                  SliverToBoxAdapter(
                    child: BlocBuilder<AuthBloc, AuthState>(
                      builder: (context, state) {
                        final signedIn = state is AuthLoaded;
                        final user = signedIn ? state.token.user : null;
                        // Mobile is a hub: who you are, what you have done,
                        // then one row per area. Each row owns a screen, so
                        // this list stays short enough to read in one glance
                        // no matter how much the app grows behind it.
                        final sections = <Widget>[
                          _ProfileHeader(user: user),
                          // Watch counters are local, so a guest who has
                          // watched something has real numbers; a guest who
                          // has not would only get three zeroes.
                          if (signedIn || _StatsStripState.hasNumbers)
                            const _StatsStrip(),
                          if (signedIn) const StreakCard(),
                          const _HubOverview(),
                          // signedIn is passed rather than read inside: a
                          // const widget is the same instance every build, so
                          // Flutter would skip rebuilding it and the Watch
                          // Party row would not appear until something else
                          // disturbed the tree.
                          _HubWatch(signedIn: signedIn),
                          const _HubApp(),
                          if (signedIn) const _SignOutSection(),
                        ];
                        return Column(
                          children: [
                            for (var i = 0; i < sections.length; i++) ...[
                              // The header carries its own padding; the gap
                              // after it is the wider one it always had.
                              if (i > 0) SizedBox(height: i == 1 ? 20 : 16),
                              _Reveal(
                                // Keyed by section type, which is unique in
                                // this list: signing out removes three entries
                                // and every section below shifts index, and an
                                // unkeyed Column would hand each one the
                                // previous occupant's Element and State.
                                key: ValueKey<Type>(sections[i].runtimeType),
                                order: i,
                                child: sections[i],
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: bottomPad + (isDesktopPlatform ? 112 : 96),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ValueListenableBuilder<double>(
              valueListenable: _headerBlur,
              builder: (_, blur, _) {
                final progress = blur.clamp(0.0, 1.0);
                final title = Text(
                  'profile.title'.tr(),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                  ),
                );
                final content = Container(
                  padding: EdgeInsetsDirectional.fromSTEB(20, topPad + 14, 16, 14),
                  decoration: BoxDecoration(
                    color: AppColors.navBackground.withValues(
                      alpha: 0.78 * progress,
                    ),
                    border: progress > 0.05
                        ? Border(
                            bottom: BorderSide(
                              color: Colors.white.withValues(
                                alpha: 0.07 * progress,
                              ),
                              width: 0.5,
                            ),
                          )
                        : null,
                  ),
                  child: isDesktopPlatform
                      ? Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 760),
                            child: Padding(
                              padding: const EdgeInsetsDirectional.only(start: 16),
                              child: Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: title,
                              ),
                            ),
                          ),
                        )
                      // Mobile: the inbox lives beside the title. It is the
                      // one thing on this page that changes on its own, and
                      // a row buried in a card cannot say "3 unread".
                      : Row(
                          children: [
                            Expanded(child: title),
                            BlocBuilder<AuthBloc, AuthState>(
                              builder: (context, state) => state is AuthLoaded
                                  ? const _HubBell()
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ),
                );
                if (progress < 0.01) return content;
                return ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: 20 * progress,
                      sigmaY: 20 * progress,
                    ),
                    child: content,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Desktop: Sozo-Desktop style sidebar + panel ───────────────────────────
  static const _desktopNav = <(IconData, String)>[
    (Icons.person_outline_rounded, 'Account'),
    (Icons.dns_outlined, 'Providers'),
    (Icons.history_rounded, 'Activity'),
    (Icons.lock_outline_rounded, 'Security'),
    (Icons.palette_outlined, 'Appearance'),
    (Icons.info_outline_rounded, 'About'),
  ];

  Widget _buildDesktop(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SettingsSidebar(
            items: _desktopNav,
            index: _navIndex,
            onTap: (i) => setState(() => _navIndex = i),
          ),
          const VerticalDivider(
            width: 1,
            thickness: 1,
            color: Color(0x14FFFFFF),
          ),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(36, 34, 36, 120),
              child: Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 240),
                    switchInCurve: Curves.easeOutCubic,
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.03),
                          end: Offset.zero,
                        ).animate(anim),
                        child: child,
                      ),
                    ),
                    child: KeyedSubtree(
                      key: ValueKey<int>(_navIndex),
                      child: _desktopPanel(_navIndex),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _desktopPanel(int index) {
    switch (index) {
      case 0:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BlocBuilder<AuthBloc, AuthState>(
              builder: (context, state) {
                final user = state is AuthLoaded ? state.token.user : null;
                return _ProfileHeader(user: user);
              },
            ),
            const SizedBox(height: 8),
            const StreakCard(),
            const SizedBox(height: 16),
            const _ConnectionsSection(),
          ],
        );
      case 1:
        return const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ProvidersSection(),
            SizedBox(height: 20),
            _ExtensionSourcesSection(),
          ],
        );
      case 2:
        return const _WatchHistorySection();
      case 3:
        return const _SecuritySection();
      case 4:
        // Theme first, then the window / navigation-bar options that were
        // already here — one Appearance panel rather than two half-panels.
        return const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppearanceSettings(showResetRow: true),
            SizedBox(height: 20),
            _AppearanceSection(),
          ],
        );
      default:
        return const AboutSection();
    }
  }
}

/// Sozo-Desktop style settings sidebar: fixed-width nav rail with a title and
/// hoverable, active-tinted category items.
class _SettingsSidebar extends StatelessWidget {
  const _SettingsSidebar({
    required this.items,
    required this.index,
    required this.onTap,
  });

  final List<(IconData, String)> items;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 236,
      color: AppColors.navBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 18),
            child: Text(
              'profile.title'.tr(),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          for (int i = 0; i < items.length; i++)
            _SettingsNavItem(
              icon: items[i].$1,
              label: items[i].$2,
              active: index == i,
              onTap: () => onTap(i),
            ),
        ],
      ),
    );
  }
}

class _SettingsNavItem extends StatefulWidget {
  const _SettingsNavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_SettingsNavItem> createState() => _SettingsNavItemState();
}

class _SettingsNavItemState extends State<_SettingsNavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    final color = active
        ? AppColors.primary
        : (_hover ? AppColors.textPrimary : AppColors.textSecondary);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: active
                ? AppColors.primary.withValues(alpha: 0.12)
                : (_hover
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.transparent),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(widget.icon, color: color, size: 18),
              const SizedBox(width: 12),
              Text(
                widget.label,
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Staggered fade + slide-up entrance for each settings section (desktop only,
/// akuse-style). Mobile returns the child unchanged.
class _Reveal extends StatefulWidget {
  const _Reveal({super.key, required this.order, required this.child});
  final int order;
  final Widget child;

  @override
  State<_Reveal> createState() => _RevealState();
}

class _RevealState extends State<_Reveal> with SingleTickerProviderStateMixin {
  AnimationController? _c;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    if (!isDesktopPlatform) return;
    final c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 440),
    );
    _c = c;
    _fade = CurvedAnimation(parent: c, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: c, curve: Curves.easeOutCubic));
    Future.delayed(Duration(milliseconds: 45 * widget.order), () {
      if (mounted) c.forward();
    });
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) return widget.child;
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

/// Centers the settings list to a readable column on desktop; full-width on
/// mobile (unchanged).
class _ProfileScrollFrame extends StatelessWidget {
  const _ProfileScrollFrame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!isDesktopPlatform) return child;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: child,
      ),
    );
  }
}

class NavbarPage extends StatelessWidget {
  const NavbarPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'profile.nav_style'.tr(),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ),
      body: const SingleChildScrollView(
        padding: EdgeInsets.only(top: 12, bottom: 40),
        child: _AppearanceSection(showLabel: false),
      ),
    );
  }
}
