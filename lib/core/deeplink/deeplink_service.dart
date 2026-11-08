import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'package:soplay/core/deeplink/deeplink_links.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/router/app_router.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/anilist/data/anilist_constants.dart';
import 'package:soplay/features/anilist/data/anilist_service.dart';
import 'package:soplay/features/mal/data/mal_constants.dart';
import 'package:soplay/features/mal/data/mal_service.dart';
import 'package:soplay/features/watch_party/domain/pending_party_code.dart';
import 'package:soplay/features/watch_party/presentation/party_entry.dart';

/// Where links are opened. [GoRouterDeeplinkNavigator] in the app; a fake in
/// tests.
abstract class DeeplinkNavigator implements Listenable {
  /// The topmost location, without its query.
  String get location;

  /// Resets to Home and pushes [location] on it, so back returns Home.
  Future<void> openOverHome(String location, Object? extra);
}

class GoRouterDeeplinkNavigator implements DeeplinkNavigator {
  GoRouterDeeplinkNavigator(this.router);

  final GoRouter router;

  @override
  void addListener(VoidCallback listener) =>
      router.routerDelegate.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      router.routerDelegate.removeListener(listener);

  @override
  String get location {
    final config = router.routerDelegate.currentConfiguration;
    return config.isEmpty ? '' : config.last.matchedLocation;
  }

  @override
  Future<void> openOverHome(String location, Object? extra) async {
    final onBareHome =
        router.routerDelegate.currentConfiguration.matches.length == 1 &&
        this.location == '/main';
    if (!onBareHome) {
      router.go('/main');
      await _untilHome();
    }
    unawaited(router.push(location, extra: extra));
  }

  /// `go` lands asynchronously; the push has to stack on Home, not on what
  /// was there before.
  Future<void> _untilHome() async {
    if (location != '/main') {
      final done = Completer<void>();
      void check() {
        if (!done.isCompleted && location == '/main') done.complete();
      }

      addListener(check);
      try {
        await done.future.timeout(const Duration(seconds: 2), onTimeout: () {});
      } finally {
        removeListener(check);
      }
    }
    await WidgetsBinding.instance.endOfFrame;
  }
}

/// The one consumer of incoming links (Flutter's own deep linking is off in
/// the manifest and Info.plist, so the router never sees them).
///
/// A link opens over Home: `/main` first, then the target pushed with its
/// typed args, so back returns to the app instead of closing it. A link that
/// arrives while the splash, first-run setup or the profile picker is up is
/// held and opened once they finish.
class DeeplinkService {
  DeeplinkService({
    AppLinks? appLinks,
    DeeplinkNavigator Function()? navigator,
    Future<Uri?> Function()? initialLink,
    Stream<Uri>? linkStream,
  }) : _appLinksOverride = appLinks,
       _navigatorOf =
           navigator ?? (() => GoRouterDeeplinkNavigator(AppRouter.router)),
       _initialLink = initialLink,
       _linkStream = linkStream;

  static const _tag = '[Deeplink]';

  final AppLinks? _appLinksOverride;
  final DeeplinkNavigator Function() _navigatorOf;
  final Future<Uri?> Function()? _initialLink;
  final Stream<Uri>? _linkStream;
  AppLinks? _appLinks;

  StreamSubscription<Uri>? _sub;
  DeeplinkNavigator? _nav;
  bool _started = false;
  DeeplinkTarget? _held;
  bool _delivering = false;

  AppLinks get _links => _appLinks ??= _appLinksOverride ?? AppLinks();

  /// The link waiting for setup to finish, if any.
  @visibleForTesting
  DeeplinkTarget? get held => _held;

  /// Routes a link must not interrupt.
  static bool isGatedPath(String path) =>
      path == '/splash' ||
      path == '/onboarding' ||
      path.startsWith('/onboarding/') ||
      path == '/profiles' ||
      path == '/pin-verify';

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _attach();

    try {
      final initial = await (_initialLink?.call() ?? _links.getInitialLink());
      if (initial != null) await handle(initial);
    } catch (e) {
      debugPrint('$_tag initial link failed: $e');
    }

    _sub = (_linkStream ?? _links.uriLinkStream).listen(
      handle,
      onError: (Object e) => debugPrint('$_tag stream error: $e'),
    );
  }

  Future<void> stop() async {
    final sub = _sub;
    _sub = null;
    _nav?.removeListener(_onRouteChanged);
    _nav = null;
    _started = false;
    await sub?.cancel();
  }

  DeeplinkNavigator _attach() {
    final existing = _nav;
    if (existing != null) return existing;
    final nav = _navigatorOf()..addListener(_onRouteChanged);
    return _nav = nav;
  }

  String _location(DeeplinkNavigator nav) {
    try {
      return nav.location;
    } catch (_) {
      return '';
    }
  }

  void _onRouteChanged() {
    final nav = _nav;
    if (_held == null || _delivering || nav == null) return;
    if (isGatedPath(_location(nav))) return;
    // Not from inside the delegate's own notification.
    scheduleMicrotask(() {
      final target = _held;
      if (target == null || isGatedPath(_location(nav))) return;
      _held = null;
      unawaited(_open(nav, target));
    });
  }

  @visibleForTesting
  Future<void> handle(Uri uri) async {
    debugPrint('$_tag received: $uri');
    if (!isSozoLink(uri)) {
      debugPrint('$_tag ignoring unknown link');
      return;
    }

    // OAuth redirects carry a one-time code to exchange, not a destination.
    final isCustom = uri.scheme == kDeeplinkScheme;
    if (isCustom && uri.host == AnilistConstants.callbackHost) {
      if (getIt.isRegistered<AnilistService>()) {
        await getIt<AnilistService>().handleCallback(uri);
      }
      return;
    }
    if (isCustom && uri.host == MalConstants.callbackHost) {
      if (getIt.isRegistered<MalService>()) {
        await getIt<MalService>().handleCallback(uri);
      }
      return;
    }

    final target = parseDeeplink(uri);
    if (target == null) {
      debugPrint('$_tag no route for ${deeplinkPath(uri)}');
      return;
    }
    _rememberParty(target);

    final nav = _attach();
    if (isGatedPath(_location(nav))) {
      debugPrint('$_tag holding $target until setup finishes');
      _held = target;
      return;
    }
    await _open(nav, target);
  }

  /// A signed-out or first-run user goes through sign-in or setup before the
  /// room can open; the code waits for them.
  void _rememberParty(DeeplinkTarget target) {
    final extra = target.extra;
    if (extra is! WatchPartyArgs) return;
    if (!getIt.isRegistered<HiveService>() ||
        !getIt.isRegistered<PendingPartyCode>()) {
      return;
    }
    if (!getIt<HiveService>().isLoggedIn) {
      unawaited(getIt<PendingPartyCode>().remember(extra.code));
    }
  }

  Future<void> _open(DeeplinkNavigator nav, DeeplinkTarget target) async {
    debugPrint('$_tag opening $target');
    _delivering = true;
    try {
      await nav.openOverHome(target.location, target.extra);
    } finally {
      _delivering = false;
    }
  }
}
