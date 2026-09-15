import 'package:soplay/core/content/catalogue.dart';
import 'dart:async';
import 'dart:ui';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/download/domain/entities/download_status.dart';
import 'package:soplay/features/download/domain/usecases/get_downloads_usecase.dart';
import 'package:soplay/features/home/presentation/bloc/home/home_bloc.dart';
import 'package:soplay/features/home/presentation/bloc/home/home_event.dart';
import 'package:soplay/features/notifications/domain/repositories/notifications_repository.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_bloc.dart';
import 'package:soplay/features/profile/presentation/bloc/provider_state.dart';
import 'package:soplay/features/profile/presentation/widgets/provider_quick_switch.dart';

class HomeTopBar extends StatelessWidget {
  const HomeTopBar({super.key, required this.blurProgress});

  final double blurProgress;

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final progress = blurProgress.clamp(0.0, 1.0);

    // Stable destinations: badges change, actions do not disappear or shrink.
    const iconPad = 12.0;
    final compact = MediaQuery.sizeOf(context).width < 430;
    final actions = <Widget>[
      _IncognitoIndicator(pad: iconPad),
      DesktopRefreshButton(
        color: AppColors.textPrimary,
        onRefresh: () => context.read<HomeBloc>().add(HomeLoad(silent: true)),
      ),
      _DownloadIndicator(pad: iconPad),
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
          const Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: _ProviderSwitcher(),
            ),
          ),
          const SizedBox(width: 4),
          ...actions,
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
        final catalogue = Catalogue.fromId(state.currentProviderId);
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => openProviderQuickSwitch(context),
            // Keep a 48dp touch target without making the visible pill bulky.
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Container(
                constraints: const BoxConstraints(minHeight: 36, maxWidth: 180),
                padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 8, 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (catalogue != null)
                      Icon(
                        Icons.auto_awesome_rounded,
                        size: 18,
                        color: catalogue.accent,
                      )
                    else
                      ProviderLogo(image: current?.image ?? '', size: 22),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        catalogue?.labelKey.tr() ?? current?.name ?? '—',
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
          padding: EdgeInsets.symmetric(horizontal: widget.pad, vertical: 12),
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
  bool _reducedMotion = false;
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    if (_reducedMotion) {
      _pulse.stop();
    } else if (_hasActive && !_pulse.isAnimating) {
      _pulse.repeat();
    }
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
      if (hasActive && !_reducedMotion) {
        _pulse.repeat();
      } else {
        _pulse.stop();
        _pulse.value = 0;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => context.push('/downloads'),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: widget.pad, vertical: 12),
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
                      MediaQuery.disableAnimationsOf(context)
                          ? 1
                          : (_pulse.value * 2 - 1).abs(),
                    ),
                    size: 24,
                  ),
                ),
                if (_hasActive)
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
    return IconButton(
      tooltip: 'profile.incognito'.tr(),
      onPressed: _confirmOff,
      icon: Icon(
        Icons.visibility_off_rounded,
        // The one item in this bar that is a warning rather than a
        // shortcut, so it does not wear the same colour as the rest.
        color: AppColors.errorLight,
        size: 22,
      ),
    );
  }
}
