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
import 'package:soplay/features/download/data/download_service.dart';
import 'package:soplay/features/download/domain/entities/download_item.dart';
import 'package:soplay/features/home/presentation/bloc/home/home_bloc.dart';
import 'package:soplay/features/home/presentation/bloc/home/home_event.dart';
import 'package:soplay/features/notifications/domain/repositories/notifications_repository.dart';
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
      padding: EdgeInsets.fromLTRB(20, topPad + 10, 12, 10),
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
              alignment: Alignment.centerRight,
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
              padding: const EdgeInsets.fromLTRB(5, 4, 7, 4),
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

  Future<void> _openSwitcher(BuildContext context, ProviderLoaded state) async {
    final bloc = context.read<ProviderBloc>();
    final favorites = _resolveFavorites(state);
    if (favorites.isEmpty) {
      openProviderPicker(context, bloc);
      return;
    }
    final result = await showAdaptiveModal<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ProviderQuickSwitchSheet(
        favorites: favorites,
        currentProviderId: state.currentProviderId,
      ),
    );
    if (result == null || !context.mounted) return;
    if (result == _kAllProvidersAction) {
      openProviderPicker(context, bloc);
    } else {
      bloc.add(ProviderSelect(result));
    }
  }
}

const String _kAllProvidersAction = '__all_providers__';

class _ProviderQuickSwitchSheet extends StatelessWidget {
  const _ProviderQuickSwitchSheet({
    required this.favorites,
    required this.currentProviderId,
  });

  final List<ProviderEntity> favorites;
  final String currentProviderId;

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    return SafeArea(
      top: false,
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
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Row(
              children: [
                const Icon(Icons.star, color: Colors.amber, size: 18),
                const SizedBox(width: 8),
                Text(
                  'profile.favorites'.tr(),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (isDesktopPlatform)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: favorites.length,
                itemBuilder: (context, i) => _favoriteProviderTile(
                  context,
                  favorites[i],
                  currentProviderId,
                ),
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: favorites.length,
                itemBuilder: (context, i) => _favoriteProviderTile(
                  context,
                  favorites[i],
                  currentProviderId,
                ),
              ),
            ),
          Divider(color: AppColors.divider, height: 1),
          ListTile(
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.apps_rounded,
                color: AppColors.textSecondary,
                size: 18,
              ),
            ),
            title: Text(
              'profile.all_providers'.tr(),
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
  final DownloadService _service = getIt<DownloadService>();
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
    _service.revision.addListener(_check);
    _check();
  }

  @override
  void dispose() {
    _service.revision.removeListener(_check);
    _pulse.dispose();
    super.dispose();
  }

  void _check() {
    if (!mounted) return;
    final items = _service.getAll();
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
