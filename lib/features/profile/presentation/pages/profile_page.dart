import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/features/profile/presentation/widgets/tab_customizer_sheet.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:soplay/core/aniyomi/aniyomi_channel.dart';
import 'package:soplay/core/cloudstream/cloudstream_channel.dart';
import 'package:soplay/core/bridge/bridge_control.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/theme/app_theme.dart';
import 'package:soplay/core/theme/theme_controller.dart';
import 'package:soplay/features/profile/presentation/pages/appearance_page.dart';
import 'package:soplay/features/extensions/data/mangayomi_runtime.dart';
import 'package:soplay/features/extensions/presentation/pages/mangayomi_sources_page.dart';
import 'package:soplay/features/aniyomi/presentation/pages/aniyomi_sources_page.dart';
import 'package:soplay/core/manga/manga_channel.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/system/desktop_window.dart';
import 'package:soplay/core/system/nav_prefs.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/features/manga/presentation/pages/manga_sources_page.dart';
import 'package:soplay/features/cloudstream/presentation/pages/cloudstream_sources_page.dart';
import 'package:soplay/features/app_lock/domain/repositories/app_lock_repository.dart';
import 'package:soplay/features/private_list/presentation/private_unlock.dart';
import 'package:soplay/features/auth/domain/entities/user_entity.dart';
import 'package:soplay/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:soplay/features/auth/presentation/bloc/auth_event.dart';
import 'package:soplay/features/auth/presentation/bloc/auth_state.dart';
import 'package:soplay/features/download/data/download_service.dart';
import 'package:soplay/features/history/data/history_service.dart';
import 'package:soplay/features/streak/presentation/widgets/streak_card.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_bloc.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_event.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_state.dart';
import 'package:soplay/features/profile/presentation/pages/providers_page.dart';
import 'package:soplay/features/anilist/data/anilist_service.dart';
import 'package:soplay/features/mal/data/mal_service.dart';
import 'package:soplay/features/mal/presentation/widgets/mal_brand.dart';
import 'package:soplay/features/anilist/presentation/widgets/anilist_brand.dart';
import 'package:soplay/features/anilist/presentation/widgets/anilist_logo.dart';
import 'package:soplay/features/watch_party/presentation/party_entry.dart';

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
                        final sections = <Widget>[
                          _ProfileHeader(user: user),
                          if (signedIn) const StreakCard(),
                          if (signedIn) const _ConnectionsSection(),
                          const _ContentSection(),
                          // signedIn is passed rather than read inside: a
                          // `const _WatchHistorySection()` is the same widget
                          // instance every build, so Flutter would skip
                          // rebuilding it and the Watch Party row would not
                          // appear until something else disturbed the tree.
                          _WatchHistorySection(signedIn: signedIn),
                          const _SettingsEntriesSection(),
                          const _AboutSection(),
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
                  padding: EdgeInsets.fromLTRB(20, topPad + 14, 16, 14),
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
                              padding: const EdgeInsets.only(left: 16),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: title,
                              ),
                            ),
                          ),
                        )
                      : title,
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
        return const _AboutSection();
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

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.user});
  final UserEntity? user;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.06),
            width: 0.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: user == null
            ? _GuestContent(onLogin: () => context.push('/login'))
            : _UserContent(user: user!),
      ),
    );
  }
}

class _GuestContent extends StatelessWidget {
  const _GuestContent({required this.onLogin});
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.primary.withValues(alpha: 0.25),
                      AppColors.primaryDark.withValues(alpha: 0.15),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.2),
                  ),
                ),
                child: Icon(
                  Icons.person_outline_rounded,
                  color: AppColors.primaryLight,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'profile.signin_account_title'.tr(),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'profile.signin_account_subtitle'.tr(),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: onLogin,
              icon: const Icon(Icons.login_rounded, size: 18),
              label: Text('profile.sign_in'.tr()),
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(kButtonRadius),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UserContent extends StatelessWidget {
  const _UserContent({required this.user});
  final UserEntity user;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          _Avatar(user: user),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.displayIdentifier,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  user.email,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _EditProfileButton(user: user),
        ],
      ),
    );
  }
}

/// Editing is what someone reaches for on their own profile; signing out is
/// something they do once and go looking for. The header carries the first, and
/// the last section of the page carries the second.
class _EditProfileButton extends StatelessWidget {
  const _EditProfileButton({required this.user});

  final UserEntity user;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () => context.push('/profile/edit', extra: user),
      icon: const Icon(Icons.edit_outlined, size: 19),
      color: AppColors.textPrimary,
      tooltip: 'profile.edit_profile'.tr(),
      style: IconButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.07),
        fixedSize: const Size(40, 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

class _SignOutSection extends StatelessWidget {
  const _SignOutSection();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: _SectionCard(
        children: [
          _Tile(
            icon: Icons.logout_rounded,
            title: 'profile.sign_out'.tr(),
            destructive: true,
            trailing: const SizedBox.shrink(),
            onTap: () => _confirmLogout(context),
          ),
        ],
      ),
    );
  }

  void _confirmLogout(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'profile.sign_out'.tr(),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'profile.sign_out_confirm'.tr(),
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'general.cancel'.tr(),
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              context.read<AuthBloc>().add(const AuthLogoutRequested());
            },
            child: Text(
              'profile.sign_out'.tr(),
              style: const TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact summary of the active provider; the picker itself is [ProvidersPage].
class _ProvidersSection extends StatelessWidget {
  const _ProvidersSection();

  /// The provider row on its own, so the mobile CONTENT card can put it above
  /// the extension sources rather than give it a labelled card of its own.
  static Widget row() => const _ProviderRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel('profile.section_providers'.tr()),
          _SectionCard(children: [row()]),
        ],
      ),
    );
  }
}

class _ProviderRow extends StatelessWidget {
  const _ProviderRow();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProviderBloc, ProviderState>(
            builder: (context, state) {
              final loaded = state is ProviderLoaded ? state : null;
              final currentProvider = loaded?.currentProvider;
              final currentName =
                  currentProvider?.name ?? loaded?.currentProviderId ?? '—';
              final total = loaded?.providers.length ?? 0;

              return _Tile(
                    icon: Icons.movie_filter_outlined,
                    title: 'profile.provider'.tr(),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (currentProvider != null &&
                            currentProvider.image.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: CachedNetworkImage(
                                imageUrl: currentProvider.image,
                                width: 22,
                                height: 22,
                                fit: BoxFit.cover,
                                // Holds the slot while loading so the name next
                                // to it does not slide sideways when it lands.
                                placeholder: (_, _) =>
                                    const SizedBox(width: 22, height: 22),
                                errorWidget: (_, _, _) =>
                                    const SizedBox.shrink(),
                              ),
                            ),
                          ),
                        Flexible(
                          child: Text(
                            currentName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        if (total > 0)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Text(
                              '· $total',
                              style: const TextStyle(
                                color: AppColors.textHint,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        const SizedBox(width: 4),
                        const _TileChevron(),
                      ],
                    ),
                    onTap: () => context.push('/providers'),
                  );
            },
          );
  }
}

void openProviderPicker(BuildContext context, ProviderBloc bloc) {
  ProvidersPage.open(context, bloc);
}

class _WatchHistorySection extends StatefulWidget {
  const _WatchHistorySection({this.signedIn = true});

  /// Hides the rows that only work with a Sozo account.
  final bool signedIn;

  @override
  State<_WatchHistorySection> createState() => _WatchHistorySectionState();
}

class _WatchHistorySectionState extends State<_WatchHistorySection> {
  final HistoryService _historyService = getIt<HistoryService>();
  final DownloadService _downloadService = getIt<DownloadService>();
  int _historyCount = 0;
  int _downloadCount = 0;

  @override
  void initState() {
    super.initState();
    _historyService.revision.addListener(_reload);
    _downloadService.revision.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    _historyService.revision.removeListener(_reload);
    _downloadService.revision.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _historyCount = _historyService.getAll().length;
      _downloadCount = _downloadService.getAll().length;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel('profile.section_activity'.tr()),
          _SectionCard(
            children: [
              _Tile(
                icon: Icons.history_rounded,
                title: 'profile.watch_history'.tr(),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_historyCount > 0)
                      Text(
                        '$_historyCount',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    const SizedBox(width: 4),
                    const _TileChevron(),
                  ],
                ),
                onTap: () => context.push('/history'),
              ),
              const _TileDivider(),
              _Tile(
                icon: Icons.download_rounded,
                title: 'profile.downloads'.tr(),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_downloadCount > 0)
                      Text(
                        '$_downloadCount',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    const SizedBox(width: 4),
                    const _TileChevron(),
                  ],
                ),
                onTap: () => context.push('/downloads'),
              ),
              const _TileDivider(),
              _Tile(
                icon: Icons.notifications_active_outlined,
                title: 'tracker.title'.tr(),
                trailing: const _TileChevron(),
                onTap: () => context.push('/following'),
              ),
              // Moved out of the home top bar, which had five permanent icons
              // and no room. Each of these is somewhere you go on purpose, and
              // this list is where the app already keeps those; leaving them
              // only in the bar was the reason the bar could not be trimmed.
              //
              // Watch Party is the one that hard-requires an account — tapping
              // it signed out only bounces to /login — so a guest is not shown
              // a door that opens onto a sign-in wall.
              if (widget.signedIn) ...[
                const _TileDivider(),
                _Tile(
                  icon: Icons.groups_rounded,
                  title: 'watch_party.title'.tr(),
                  trailing: const _TileChevron(),
                  onTap: () => showPartyEntrySheet(context),
                ),
              ],
              const _TileDivider(),
              _Tile(
                icon: Icons.track_changes_rounded,
                title: 'navigation.anilist'.tr(),
                trailing: const _TileChevron(),
                onTap: () => context.push('/anilist'),
              ),
              const _TileDivider(),
              _Tile(
                icon: Icons.live_tv_rounded,
                title: 'navigation.live_tv'.tr(),
                trailing: const _TileChevron(),
                onTap: () => context.push('/live-tv'),
              ),
              const _TileDivider(),
              _Tile(
                icon: Icons.devices_rounded,
                title: BridgeControl.canHost
                    ? 'profile.share_sources_desktop'.tr()
                    : Platform.isIOS
                    ? 'ios.sources_title'.tr()
                    : 'profile.desktop_sources'.tr(),
                trailing: const _TileChevron(),
                onTap: () => context.push('/desktop-share'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Sits directly under the streak card: the offer to connect a tracker only
/// works if it is seen, and it was previously buried in the Activity list.
class _ConnectionsSection extends StatelessWidget {
  const _ConnectionsSection();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel('profile.section_connections'.tr()),
          _SectionCard(
            children: [
              const _ConnectionsTile(),
              const _TileDivider(),
              // Link a TV, not Live TV: the channel line-up moved to the home
              // bar, and pairing a television — a thing you genuinely connect —
              // had no entry point anywhere in the app except a deep link.
              _Tile(
                icon: Icons.cast_connected_rounded,
                title: 'link_tv.title'.tr(),
                subtitle: 'link_tv.tile_subtitle'.tr(),
                trailing: const _TileChevron(),
                onTap: () => context.push('/link-tv'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The Connections row, which shows the trackers' state inline.
///
/// A tile of its own rather than a plain link: whether a tracker is connected
/// is the entire question a user opens this row to answer, and making them
/// navigate to find out defeats the point.
///
/// It speaks for BOTH trackers rather than for AniList alone. Branded as one
/// service, it read as an AniList row — so someone looking for MyAnimeList had
/// no reason to tap it and reasonably concluded the app did not support it.
/// Listens to both services so connecting elsewhere updates it without a
/// manual refresh.
class _ConnectionsTile extends StatefulWidget {
  const _ConnectionsTile();

  @override
  State<_ConnectionsTile> createState() => _ConnectionsTileState();
}

class _ConnectionsTileState extends State<_ConnectionsTile> {
  final AnilistService _anilist = getIt<AnilistService>();
  final MalService _mal = getIt<MalService>();

  @override
  void initState() {
    super.initState();
    _anilist.addListener(_onChange);
    _mal.addListener(_onChange);
  }

  @override
  void dispose() {
    _anilist.removeListener(_onChange);
    _mal.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  /// Who is connected, in one line.
  ///
  /// Account names rather than service names: two people with both trackers
  /// linked want to see WHICH accounts, and the logos beside this already say
  /// which services. Falls back to the service name when a link carries no
  /// username yet.
  String _subtitle() {
    final names = <String>[
      if (_anilist.isConnected)
        (_anilist.viewer?.name.trim().isNotEmpty ?? false)
            ? _anilist.viewer!.name.trim()
            : 'AniList',
      if (_mal.isConnected)
        (_mal.viewer?.name.trim().isNotEmpty ?? false)
            ? _mal.viewer!.name.trim()
            : 'MyAnimeList',
    ];
    return names.isEmpty ? 'anilist.connect_tagline'.tr() : names.join('  ·  ');
  }

  @override
  Widget build(BuildContext context) {
    final anyConnected = _anilist.isConnected || _mal.isConnected;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.push('/connections'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 11, 12, 11),
          child: Row(
            children: [
              // Both marks, so the row names what it actually offers. Dimmed
              // when that tracker is not connected, so the pair doubles as a
              // status readout at a glance.
              _TrackerMark(
                connected: _anilist.isConnected,
                child: const AnilistLogo(size: 28, radius: 8),
              ),
              const SizedBox(width: 7),
              _TrackerMark(
                connected: _mal.isConnected,
                child: const MalLogo(size: 28, radius: 8),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'anilist.connections_title'.tr(),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitle(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: anyConnected ? kAnilistBlue : AppColors.textHint,
                        fontSize: 12.5,
                        fontWeight:
                            anyConnected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              if (!anyConnected)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: kAnilistBlue.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'anilist.connect_short'.tr(),
                    style: const TextStyle(
                      color: kAnilistBlue,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else
                const _TileChevron(),
            ],
          ),
        ),
      ),
    );
  }
}

/// A tracker logo, dimmed while that tracker is not connected.
class _TrackerMark extends StatelessWidget {
  const _TrackerMark({required this.connected, required this.child});

  final bool connected;
  final Widget child;

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: connected ? 1 : 0.38,
        child: child,
      );
}

class _SecuritySection extends StatefulWidget {
  const _SecuritySection();

  @override
  State<_SecuritySection> createState() => _SecuritySectionState();
}

class _SecuritySectionState extends State<_SecuritySection> {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel('app_lock.section_label'.tr()),
          const _SectionCard(children: [_SecurityRows()]),
        ],
      ),
    );
  }
}

/// App lock + private list, as two bare rows.
///
/// Split out of [_SecuritySection] so the mobile SETTINGS card can hold them
/// next to Appearance and Player — where they belong — while desktop keeps its
/// own "Security" panel.
class _SecurityRows extends StatefulWidget {
  const _SecurityRows();

  @override
  State<_SecurityRows> createState() => _SecurityRowsState();
}

class _SecurityRowsState extends State<_SecurityRows> {
  late final AppLockRepository _lock = getIt<AppLockRepository>();

  @override
  Widget build(BuildContext context) {
    final enabled = _lock.isEnabled;
    return Column(
            children: [
              _Tile(
                icon: Icons.lock_rounded,
                title: 'app_lock.app_lock'.tr(),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      enabled
                          ? 'app_lock.state_on'.tr()
                          : 'app_lock.state_off'.tr(),
                      style: TextStyle(
                        color: enabled
                            ? AppColors.primary
                            : AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const _TileChevron(),
                  ],
                ),
                onTap: () async {
                  await context.push('/app-lock-settings');
                  if (mounted) setState(() {});
                },
              ),
              const _TileDivider(),
              _Tile(
                icon: Icons.folder_special_rounded,
                title: 'app_lock.private_list'.tr(),
                trailing: const _TileChevron(),
                onTap: () async {
                  final unlocked = await requestPrivateUnlock(context);
                  if (unlocked && context.mounted) {
                    context.push('/private-list');
                  }
                },
              ),
            ],
          );
  }
}

class _AppearanceSection extends StatefulWidget {
  const _AppearanceSection({this.showLabel = true});

  /// When false (the standalone Navigation-bar page), the "APPEARANCE" label
  /// and the redundant inner "Navigation bar" header are hidden.
  final bool showLabel;

  @override
  State<_AppearanceSection> createState() => _AppearanceSectionState();
}

class _AppearanceSectionState extends State<_AppearanceSection> {
  late bool _native = getIt<HiveService>().useNativeTitleBar;
  late String _navStyle = getIt<HiveService>().navStyle;

  Future<void> _toggle(bool value) async {
    setState(() => _native = value);
    await getIt<HiveService>().setUseNativeTitleBar(value);
    await DesktopWindow.setNativeTitleBar(value);
  }

  Future<void> _setNavStyle(String value) async {
    if (value == _navStyle) return;
    setState(() => _navStyle = value);
    await getIt<HiveService>().setNavStyle(value);
    // Push to the shared notifier so the floating nav rebuilds instantly.
    NavPrefs.navStyle.value = value;
  }

  // A tiny realistic mock of each nav style: solid/glass = a floating pill,
  // classic = a full-width bar — with mini tab icons (the first = selected,
  // in a little pill, like the real bar) instead of plain dots.
  Widget _navPreview(String value, Color accent) {
    const icons = [
      Icons.home_rounded,
      Icons.search_rounded,
      Icons.play_arrow_rounded,
      Icons.person_rounded,
    ];
    final muted = accent.withValues(alpha: 0.4);
    Widget miniIcon(int i) {
      if (i == 0) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 2.5, vertical: 1),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Icon(icons[i], size: 9, color: accent),
        );
      }
      return Icon(icons[i], size: 9, color: muted);
    }

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < icons.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1.5),
            child: miniIcon(i),
          ),
      ],
    );

    if (value == 'classic') {
      return Container(
        width: double.infinity,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.10),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
          border: Border(
            top: BorderSide(color: accent.withValues(alpha: 0.4), width: 0.6),
          ),
        ),
        child: row,
      );
    }
    // solid / glass: floating rounded pill
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: value == 'glass'
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  accent.withValues(alpha: 0.26),
                  accent.withValues(alpha: 0.06),
                ],
              )
            : null,
        color: value == 'solid' ? accent.withValues(alpha: 0.16) : null,
        border: Border.all(color: accent.withValues(alpha: 0.45), width: 0.8),
      ),
      child: row,
    );
  }

  Widget _navSegment(String value, String labelKey) {
    final selected = _navStyle == value;
    final accent = selected ? AppColors.primary : AppColors.textSecondary;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _setNavStyle(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          margin: const EdgeInsets.all(3),
          padding: const EdgeInsets.fromLTRB(6, 9, 6, 7),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: selected
                  ? AppColors.primary.withValues(alpha: 0.5)
                  : Colors.transparent,
            ),
          ),
          child: Column(
            children: [
              SizedBox(
                height: 24,
                child: Center(child: _navPreview(value, accent)),
              ),
              const SizedBox(height: 7),
              Text(
                labelKey.tr(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showLabel) ...[
            _SectionLabel('profile.section_appearance'.tr()),
          ],
          _SectionCard(
            children: [
              if (isDesktopPlatform)
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  value: _native,
                  activeThumbColor: AppColors.primary,
                  secondary: const Icon(
                    Icons.web_asset_rounded,
                    color: AppColors.textSecondary,
                  ),
                  title: Text(
                    'profile.native_window_bar'.tr(),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                    ),
                  ),
                  subtitle: Text(
                    'profile.native_window_bar_subtitle'.tr(),
                    style: const TextStyle(
                      color: AppColors.textHint,
                      fontSize: 12,
                    ),
                  ),
                  onChanged: _toggle,
                ),
              if (isMobilePlatform) ...[
                if (widget.showLabel)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.dashboard_customize_rounded,
                          size: 18,
                          color: AppColors.textHint,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'profile.nav_style'.tr(),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        _navSegment('solid', 'profile.nav_style_solid'),
                        _navSegment('glass', 'profile.nav_style_glass'),
                        _navSegment('classic', 'profile.nav_style_classic'),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Material(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(14),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      leading: const Icon(
                        Icons.view_week_rounded,
                        color: AppColors.textSecondary,
                      ),
                      title: Text(
                        'nav_customize.entry_title'.tr(),
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                        ),
                      ),
                      subtitle: Text(
                        'nav_customize.entry_subtitle'.tr(),
                        style: const TextStyle(
                          color: AppColors.textHint,
                          fontSize: 12,
                        ),
                      ),
                      trailing: const _TileChevron(),
                      onTap: () => showTabCustomizer(context),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Standalone Navigation-bar settings page (tab-bar style + tab customizer),
/// opened from the Profile "Navigation bar" tile.
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

/// Everything the user can configure, in ONE card.
///
/// Appearance, the navigation bar and the player used to be a three-row card
/// with app lock and the private list in a separate labelled "Security" card
/// directly above it. Two labels for five rows that are all "settings" made the
/// page read as longer than it is; one label reads as one place to look.
///
/// The Player row is unconditional — the page behind it owns playback defaults
/// and subtitle appearance, which apply everywhere; only its engine block is
/// platform-gated.
class _SettingsEntriesSection extends StatelessWidget {
  const _SettingsEntriesSection();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel('profile.section_settings'.tr()),
          _SectionCard(
            children: [
              _Tile(
                icon: Icons.palette_outlined,
                title: 'appearance.title'.tr(),
                subtitle: 'appearance.entry_subtitle'.tr(),
                trailing: const _AccentDotChevron(),
                onTap: () => context.push('/appearance'),
              ),
              const _TileDivider(),
              _Tile(
                icon: Icons.view_week_rounded,
                title: 'profile.nav_style'.tr(),
                trailing: const _TileChevron(),
                onTap: () => context.push('/navbar'),
              ),
              const _TileDivider(),
              _Tile(
                icon: Icons.play_circle_outline_rounded,
                title: 'profile.section_player'.tr(),
                trailing: const _TileChevron(),
                onTap: () => context.push('/player-settings'),
              ),
              const _TileDivider(),
              const _SecurityRows(),
            ],
          ),
        ],
      ),
    );
  }
}

/// Where the content comes from: the active provider, and — folded away behind
/// one row — the installable extension ecosystems.
///
/// These were two labelled cards and five rows. Four of those rows were
/// extension stores most people open once and never again, so they are collapsed
/// by default; the row still says how many there are, and opens them in place.
class _ContentSection extends StatefulWidget {
  const _ContentSection();

  @override
  State<_ContentSection> createState() => _ContentSectionState();
}

class _ContentSectionState extends State<_ContentSection> {
  bool _sourcesOpen = false;

  @override
  Widget build(BuildContext context) {
    final sources = _ExtensionSourcesSection.rowsFor(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel('profile.section_content'.tr()),
          _SectionCard(
            children: [
              _ProvidersSection.row(),
              if (sources.isNotEmpty) ...[
                const _TileDivider(),
                _Tile(
                  icon: Icons.extension_outlined,
                  title: 'profile.sources_row'.tr(),
                  subtitle: 'profile.sources_row_subtitle'.tr(),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${sources.length}',
                        style: const TextStyle(
                          color: AppColors.textHint,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 6),
                      AnimatedRotation(
                        turns: _sourcesOpen ? 0.25 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: const _TileChevron(),
                      ),
                    ],
                  ),
                  onTap: () => setState(() => _sourcesOpen = !_sourcesOpen),
                ),
                // AnimatedSize rather than a route: the stores are one tap
                // away either way, and expanding in place keeps the user's
                // place on a long page.
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: _sourcesOpen
                      ? Column(
                          children: [
                            for (final row in sources) ...[
                              const _TileDivider(),
                              row,
                            ],
                          ],
                        )
                      : const SizedBox(width: double.infinity),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  /// Resolved once. Rebuilt per build() it dropped the version row back to "…"
  /// on every rebuild of the list.
  static final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  void _showDeveloper(BuildContext context) {
    showAdaptiveModal<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Image.network(
                  'https://avatars.githubusercontent.com/u/108933534?v=4',
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    width: 56,
                    height: 56,
                    color: AppColors.primary,
                    child: const Center(
                      child: Text(
                        'AX',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Azamov X',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'profile.developer_role'.tr(),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: Material(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _open('https://t.me/ackles'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.telegram,
                            color: Color(0xFF2AABEE),
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            '@ackles',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          const Icon(
                            Icons.open_in_new_rounded,
                            color: AppColors.textHint,
                            size: 16,
                          ),
                        ],
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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel('profile.section_about'.tr()),
          _SectionCard(
            children: [
              _Tile(
                icon: Icons.info_outline_rounded,
                title: 'Sozo',
                trailing: FutureBuilder<PackageInfo>(
                  future: _packageInfo,
                  builder: (_, snap) => Text(
                    snap.hasData
                        ? 'v${snap.data!.version} (${snap.data!.buildNumber})'
                        : '…',
                    style: const TextStyle(
                      color: AppColors.textHint,
                      fontSize: 13,
                    ),
                  ),
                ),
                onTap: null,
              ),
              const _TileDivider(),
              _Tile(
                icon: Icons.person_outline_rounded,
                title: 'profile.developer'.tr(),
                trailing: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Azamov X',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    SizedBox(width: 4),
                    _TileChevron(),
                  ],
                ),
                onTap: () => _showDeveloper(context),
              ),
              const _TileDivider(),
              const _ServerCountdownTile(),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _SocialIcon(
                icon: Icons.telegram,
                label: 'Telegram',
                onTap: () => _open('https://t.me/sozoApp'),
              ),
              const SizedBox(width: 16),
              _SocialIcon(
                icon: Icons.language_rounded,
                label: 'profile.website'.tr(),
                onTap: () => _open('https://sozo.azamov.me'),
              ),
              const SizedBox(width: 16),
              _SocialIcon(
                icon: Icons.code_rounded,
                label: 'GitHub',
                onTap: () => _open('https://github.com/professorDeveloper'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SocialIcon extends StatelessWidget {
  const _SocialIcon({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return HoverTap(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
                width: 0.5,
              ),
            ),
            child: Icon(icon, color: AppColors.textSecondary, size: 22),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textHint,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.05),
          width: 0.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

/// A section heading, with the same accent tick Home puts in front of every
/// row title. Two jobs: it carries the chosen colour down a screen that is
/// otherwise all greys, and it gives a long settings list a visual rhythm so
/// the sections read as separate rather than as one endless column.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Row(
        children: [
          Container(
            width: 2.5,
            height: 11,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.primary,
                  AppColors.primary.withValues(alpha: 0.5),
                ],
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textHint,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

/// A Profile row. Metrics are the ones in `settings_tiles.dart` so a row here
/// and a row on the page it opens sit on the same grid.
class _Tile extends StatelessWidget {
  const _Tile({
    this.icon,
    this.leading,
    required this.title,
    required this.trailing,
    required this.onTap,
    this.subtitle,
    this.destructive = false,
  });

  final IconData? icon;

  /// Signing out is the one row on this page that undoes something, and a row
  /// that reads exactly like "Appearance" gives no sign of that.
  final bool destructive;

  /// Drawn in place of the icon chip, in the same 34px box so the column of
  /// leading marks does not shift between rows.
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final sub = subtitle;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 11, 12, 11),
          child: LayoutBuilder(
            builder: (context, constraints) => Row(
              children: [
                _TileLeading(
                  icon: icon,
                  destructive: destructive,
                  child: leading,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: destructive
                              ? AppColors.error
                              : AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: destructive
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                      if (sub != null && sub.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          sub,
                          style: const TextStyle(
                            color: AppColors.textHint,
                            fontSize: 11.5,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Half the row at most: past that the value wins the tug of
                // war with the title and pushes it into a wrapped column.
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth * 0.5,
                  ),
                  child: trailing,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TileLeading extends StatelessWidget {
  const _TileLeading({this.icon, this.child, this.destructive = false});

  final IconData? icon;
  final Widget? child;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final custom = child;
    if (custom != null) {
      return SizedBox(width: 34, height: 34, child: custom);
    }
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: destructive
            ? AppColors.error.withValues(alpha: 0.12)
            : AppColors.textSecondary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: icon == null
          ? null
          : Icon(
              icon,
              color: destructive ? AppColors.error : AppColors.textSecondary,
              size: 18,
            ),
    );
  }
}

/// Inset to the title column, like [SettingsDivider] on the sub-pages.
class _TileDivider extends StatelessWidget {
  const _TileDivider();

  @override
  Widget build(BuildContext context) =>
      Divider(color: AppColors.divider, height: 1, indent: 64);
}

/// Chevron with the accent in front of it, for the Appearance row.
///
/// The row's whole subject is a colour, so the current one belongs on the row —
/// it turns "Appearance ›" into an answer as well as a destination.
class _AccentDotChevron extends StatelessWidget {
  const _AccentDotChevron();

  @override
  Widget build(BuildContext context) {
    final accent = getIt<ThemeController>().accent;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: accent.base,
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 0.8,
            ),
          ),
        ),
        const SizedBox(width: 8),
        const _TileChevron(),
      ],
    );
  }
}

/// Chevron used by every row that opens something.
class _TileChevron extends StatelessWidget {
  const _TileChevron();

  @override
  Widget build(BuildContext context) => const Icon(
    Icons.chevron_right_rounded,
    color: AppColors.textHint,
    size: 20,
  );
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.user});
  final UserEntity user;

  @override
  Widget build(BuildContext context) {
    final photoUrl = user.photoURL;
    final initials = _initials(user.displayIdentifier);

    // No coloured ring. A Google picture already arrives as a saturated tile,
    // and a red band around it read as an error state rather than a frame.
    return Container(
      width: 66,
      height: 66,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(17),
        ),
        clipBehavior: Clip.antiAlias,
        child: photoUrl != null && photoUrl.isNotEmpty
            ? Image.network(
                photoUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, e, s) => _Initials(initials: initials),
              )
            : _Initials(initials: initials),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length > 1 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isEmpty ? 'S' : name[0].toUpperCase();
  }
}

class _Initials extends StatelessWidget {
  const _Initials({required this.initials});
  final String initials;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ServerCountdownTile extends StatefulWidget {
  const _ServerCountdownTile();

  @override
  State<_ServerCountdownTile> createState() => _ServerCountdownTileState();
}

class _ServerCountdownTileState extends State<_ServerCountdownTile> {
  static final DateTime _deadline = DateTime.utc(2026, 10, 1);
  late final Timer _timer;
  final _remaining = ValueNotifier<Duration>(Duration.zero);

  @override
  void initState() {
    super.initState();
    _updateRemaining();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateRemaining(),
    );
  }

  void _updateRemaining() {
    final diff = _deadline.difference(DateTime.now().toUtc());
    _remaining.value = diff.isNegative ? Duration.zero : diff;
  }

  @override
  void dispose() {
    _timer.cancel();
    _remaining.dispose();
    super.dispose();
  }

  void _showSupportSheet(BuildContext context) {
    showAdaptiveModal<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ServerSupportSheet(remaining: _remaining),
    );
  }

  static String _fmt(Duration rem) {
    final d = rem.inDays;
    final h = rem.inHours.remainder(24);
    final m = rem.inMinutes.remainder(60);
    final s = rem.inSeconds.remainder(60);
    if (d > 0) return '${d}d ${h}h ${m}m';
    return '${h}h ${m}m ${s}s';
  }

  @override
  Widget build(BuildContext context) {
    return _Tile(
      icon: Icons.dns_outlined,
      title: 'profile.server'.tr(),
      onTap: () => _showSupportSheet(context),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: ValueListenableBuilder<Duration>(
              valueListenable: _remaining,
              builder: (_, rem, _) {
                return Text(
                  rem == Duration.zero ? 'profile.expired'.tr() : _fmt(rem),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    // "Expired" means the server is down and nothing will load.
                    // That is an error, not a place to show the theme.
                    color: rem == Duration.zero
                        ? AppColors.error
                        : AppColors.textSecondary,
                    fontSize: 13,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 4),
          const _TileChevron(),
        ],
      ),
    );
  }
}

class _ServerSupportSheet extends StatelessWidget {
  const _ServerSupportSheet({required this.remaining});

  final ValueNotifier<Duration> remaining;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.dns_rounded,
              color: AppColors.textSecondary,
              size: 24,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'profile.support_title'.tr(),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          ValueListenableBuilder<Duration>(
            valueListenable: remaining,
            builder: (_, rem, _) {
              final expired = rem == Duration.zero;
              if (expired) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    // Same reasoning as the countdown row above it.
                    'profile.server_expired'.tr(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.error,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              }
              final d = rem.inDays;
              final h = rem.inHours.remainder(24);
              final m = rem.inMinutes.remainder(60);
              final s = rem.inSeconds.remainder(60);
              return Row(
                children: [
                  _SheetCountdownCell(value: d, label: 'profile.days'.tr()),
                  const SizedBox(width: 8),
                  _SheetCountdownCell(value: h, label: 'profile.hours'.tr()),
                  const SizedBox(width: 8),
                  _SheetCountdownCell(value: m, label: 'profile.min'.tr()),
                  const SizedBox(width: 8),
                  _SheetCountdownCell(value: s, label: 'profile.sec'.tr()),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          ValueListenableBuilder<Duration>(
            valueListenable: remaining,
            builder: (_, rem, _) {
              final expired = rem == Duration.zero;
              return Text(
                expired
                    ? 'profile.support_body_expired'.tr()
                    : 'profile.support_body'.tr(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.5,
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                launchUrl(
                  Uri.parse('https://t.me/ackles'),
                  mode: LaunchMode.externalApplication,
                );
              },
              icon: const Icon(Icons.favorite_rounded, size: 18),
              label: Text('profile.support_developer'.tr()),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetCountdownCell extends StatelessWidget {
  const _SheetCountdownCell({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              value.toString().padLeft(2, '0'),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                height: 1,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textHint,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The installable-extension entries, in one card instead of four free-standing
/// ones. Which of them exist depends on the platform, so the card builds itself
/// out of whatever is supported and disappears entirely when nothing is.
class _ExtensionSourcesSection extends StatelessWidget {
  const _ExtensionSourcesSection();

  /// The rows themselves, so the mobile CONTENT card can host them behind an
  /// expander instead of standing up a fifth labelled card of its own.
  static List<Widget> rowsFor(BuildContext context) => <Widget>[
      if (BridgeControl.canHost && CloudStreamChannel.isSupported)
        _Tile(
          leading: const _TileLogo(
            url:
                'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcTRzeluIShlMnhgHeVHgTSkvsthvQEK2xaS5A&s',
            fallback: Icons.extension_outlined,
          ),
          title: 'profile.cloudstream_sources'.tr(),
          trailing: const _TileChevron(),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const CloudStreamSourcesPage()),
          ),
        ),
      if (BridgeControl.canHost && AniyomiChannel.isSupported)
        _Tile(
          leading: const _TileLogo(
            url:
                'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcShNP_m0078YcYRUbudCuZhohC2U143Re4MfQ&s',
            fallback: Icons.play_circle_outline,
          ),
          title: 'profile.aniyomi_sources'.tr(),
          trailing: const _TileChevron(),
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const AniyomiSourcesPage())),
        ),
      if (BridgeControl.canHost && MangaChannel.isSupported)
        _Tile(
          leading: const _TileLogo(
            url:
                'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcShNP_m0078YcYRUbudCuZhohC2U143Re4MfQ&s',
            fallback: Icons.menu_book_outlined,
          ),
          title: 'manga.sources_title'.tr(),
          trailing: const _TileChevron(),
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const MangaSourcesPage())),
        ),
      // Not gated on BridgeControl.canHost / a platform channel: these
      // extensions are JavaScript, so this entry is valid on iOS, macOS and
      // Windows as well as Android — the only extension ecosystem that is.
      if (MangayomiRuntime.isSupported)
        _Tile(
          leading: const _TileLogo(
            url:
                'https://raw.githubusercontent.com/kodjodevf/mangayomi/main/assets/app_icons/icon-red.png',
            fallback: Icons.javascript_outlined,
          ),
          title: 'Mangayomi Sources',
          trailing: const _TileChevron(),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const MangayomiSourcesPage()),
          ),
        ),
    ];

  @override
  Widget build(BuildContext context) {
    final rows = rowsFor(context);
    if (rows.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel('profile.section_extensions'.tr()),
          _SectionCard(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const _TileDivider(),
                rows[i],
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Remote logo in the leading slot. Shows the plain icon chip while loading and
/// if the load fails, so the row never has a hole where its mark should be.
class _TileLogo extends StatelessWidget {
  const _TileLogo({required this.url, required this.fallback});

  final String url;
  final IconData fallback;

  @override
  Widget build(BuildContext context) {
    final cache = (34 * MediaQuery.devicePixelRatioOf(context)).round();
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: CachedNetworkImage(
        imageUrl: url,
        width: 34,
        height: 34,
        fit: BoxFit.cover,
        memCacheWidth: cache,
        memCacheHeight: cache,
        placeholder: (_, _) => _TileLeading(icon: fallback),
        errorWidget: (_, _, _) => _TileLeading(icon: fallback),
      ),
    );
  }
}
