import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/router/app_router.dart';

class NoInternetInterceptor extends Interceptor {
  static int _lastRedirectMs = 0;
  static int _lastProbeMs = 0;
  static bool _lastProbeOnline = true;
  static Future<bool>? _inFlightProbe;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // A background API request must never replace a local reader, player or
    // source manager. Their own error/retry states can preserve useful content.
    // Whole-screen redirection is reserved for an explicitly opted-in request.
    if (err.requestOptions.extra['redirectOnOffline'] == true &&
        _looksOffline(err)) {
      unawaited(_maybeRedirect());
    }
    handler.next(err);
  }

  bool _looksOffline(DioException err) {
    if (err.type == DioExceptionType.cancel) return false;
    if (err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.sendTimeout) {
      return true;
    }
    final error = err.error;
    return error is SocketException;
  }

  Future<void> _maybeRedirect() async {
    final path = AppRouter.router.routeInformationProvider.value.uri.path;
    if (path == '/no-internet' || path == '/downloads') return;

    final online = await _probeInternet();
    if (online) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastRedirectMs < 1200) return;
    _lastRedirectMs = now;

    final currentPath =
        AppRouter.router.routeInformationProvider.value.uri.path;
    if (currentPath == '/no-internet' || currentPath == '/downloads') return;

    scheduleMicrotask(() {
      AppRouter.router.go('/no-internet');
    });
  }

  Future<bool> _probeInternet() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastProbeMs < 2000) {
      return Future.value(_lastProbeOnline);
    }
    final existing = _inFlightProbe;
    if (existing != null) return existing;
    final probe = _runProbe();
    _inFlightProbe = probe;
    probe.whenComplete(() {
      _inFlightProbe = null;
    });
    return probe;
  }

  /// Hosts the probe will accept as proof of connectivity, most meaningful
  /// first. Our own API leads deliberately: if it resolves, the app can work,
  /// which is the only question this probe actually needs to answer.
  ///
  /// The previous implementation asked for `one.one.one.one` alone. That is
  /// Cloudflare's resolver hostname, and it is routinely blocked or throttled
  /// by ISPs in the regions this app serves — so a perfectly healthy connection
  /// was reported as offline whenever that single lookup failed, which is why
  /// the failure came and went instead of being consistent.
  static List<String> get _probeHosts {
    final api = Uri.tryParse(AppConstants.baseUrl)?.host;
    return <String>[
      if (api != null && api.isNotEmpty) api,
      'cloudflare.com',
      'google.com',
    ];
  }

  static const _probeTimeout = Duration(seconds: 5);

  Future<bool> _runProbe() async {
    // Any single success proves connectivity, so race them and take the first
    // host that answers rather than paying the timeout for each in turn. A TV
    // on Wi-Fi resolves noticeably slower than a phone, hence 5s over 3s.
    bool online = false;
    try {
      final lookups = _probeHosts.map(
        (host) => InternetAddress.lookup(
          host,
        ).then((r) => r.isNotEmpty && r.first.rawAddress.isNotEmpty),
      );
      final results = await Future.wait(
        lookups.map((f) => f.catchError((Object _) => false)),
      ).timeout(_probeTimeout, onTimeout: () => const <bool>[]);
      online = results.any((ok) => ok);
    } catch (_) {
      online = false;
    }
    _lastProbeMs = DateTime.now().millisecondsSinceEpoch;
    _lastProbeOnline = online;
    return online;
  }
}
