import 'dart:async';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:soplay/core/js/js_log.dart';
import 'package:soplay/core/system/webview_env.dart';

class CfBypassService {
  static const _pollInterval = Duration(milliseconds: 600);
  static const _defaultTimeout = Duration(seconds: 30);

  final Map<String, Future<String?>> _inflight = {};

  Future<String?> solve({
    required String host,
    required String url,
    required String userAgent,
    Duration timeout = _defaultTimeout,
  }) {
    final existing = _inflight[host];
    if (existing != null) return existing;
    final future = _runSolve(host: host, url: url, userAgent: userAgent, timeout: timeout)
        .whenComplete(() => _inflight.remove(host));
    _inflight[host] = future;
    return future;
  }

  /// Whatever [host]'s zone currently holds in the shared WebView cookie jar,
  /// as a `Cookie:` header — or null when there is no clearance in it.
  ///
  /// [solve] earns one headlessly and hands it straight back, so nothing else
  /// has needed to read the jar. A challenge that wants a *person* — a
  /// checkbox, a captcha — cannot be answered that way, and the interactive
  /// `CloudflareSolverPage` earns it in a visible WebView instead. The jar is
  /// the only trace that leaves; this is how the value reaches a caller that
  /// keeps cookies of its own.
  Future<String?> readClearance(String host) async {
    try {
      final cookies =
          await CookieManager.instance().getCookies(url: WebUri('https://$host/'));
      final hasClearance = cookies.any(
        (c) => c.name == 'cf_clearance' && '${c.value}'.isNotEmpty,
      );
      return hasClearance ? _cookieHeader(cookies) : null;
    } catch (_) {
      return null;
    }
  }

  /// The jar as one `Cookie:` header. Everything in it travels together —
  /// Cloudflare pairs cf_clearance with the `__cf_bm` and `_cfuvid` it was
  /// issued alongside, and sending the clearance on its own gets it refused.
  static String _cookieHeader(List<Cookie> cookies) => cookies
      .where((c) => '${c.value}'.isNotEmpty)
      .map((c) => '${c.name}=${c.value}')
      .join('; ');

  /// Drive a headless WebView until Cloudflare hands out a clearance.
  ///
  /// Written as a plain loop that returns its answer directly. It used to hang
  /// the result off a Completer that timer callbacks filled in, and the value
  /// never reached the caller: the log read `solved animepahe.pw (613ms)` and
  /// then nothing at all — not the replay, not even the caller's own 60s
  /// timeout. It behaved like a Heisenbug too, since an extra log statement
  /// near the completion was enough to let the call through. There is nothing
  /// here a Completer buys: the poll is the only producer, so it can simply be
  /// the thing that returns.
  /// One real turn of the event loop.
  ///
  /// Every exit from [_runSolve] goes through this. Without it the caller's
  /// continuation never ran: the log read `solved animepahe.pw (7889ms)` — or
  /// the watchdog's `no cf_clearance after 30s` — and then nothing at all, not
  /// even the caller's own 60s timeout. It presented as a Heisenbug, because a
  /// print or log placed between the solve and the return was enough to let the
  /// call through and removing it brought the hang straight back. The WebView
  /// work leaves the platform channel busy; this is what lets it drain before
  /// the value is delivered, and it costs one tick against a solve measured in
  /// seconds.
  static Future<void> _yield() =>
      Future<void>.delayed(const Duration(milliseconds: 16));

  Future<String?> _runSolve({
    required String host,
    required String url,
    required String userAgent,
    required Duration timeout,
  }) async {
    final sw = Stopwatch()..start();
    InAppWebViewController? controller;

    // Cloudflare scopes cf_clearance to the whole zone, so the challenge on any
    // page of a host clears every other page of it.
    final origin = 'https://$host/';

    // Drop whatever clearance is already in the jar before solving. Reaching
    // this method means a request just came back challenged, so any clearance
    // still present has been proven not to work, and leaving it would let the
    // loop below accept it immediately and hand back a token the CDN refuses.
    try {
      final cm = CookieManager.instance();
      for (final u in {WebUri(origin), WebUri(url)}) {
        await cm.deleteCookie(url: u, name: 'cf_clearance');
        await cm.deleteCookie(url: u, name: 'cf_clearance', domain: '.$host');
      }
    } catch (_) {
      // A jar we cannot prune still solves whenever the stale cookie has
      // expired on its own; failing the solve outright would be worse.
    }

    final headless = HeadlessInAppWebView(
      webViewEnvironment: await WebViewEnv.ensure(),
      initialUrlRequest: URLRequest(url: WebUri(url)),
      initialSettings: InAppWebViewSettings(
        userAgent: userAgent,
        javaScriptEnabled: true,
        domStorageEnabled: true,
        cacheEnabled: true,
        useShouldInterceptRequest: false,
      ),
      onWebViewCreated: (c) => controller = c,
    );

    var started = true;
    unawaited(headless.run().catchError((Object e) {
      JsLog.err('cf', 'webview failed to start for $host: $e');
      started = false;
    }));

    try {
      var retargeted = false;
      while (sw.elapsed < timeout) {
        await Future<void>.delayed(_pollInterval);
        if (!started) {
          await _yield();
          return null;
        }

        // The failing request is often an API endpoint, and a challenge served
        // for one is a document the WebView renders — but the page it lands on
        // after solving is raw JSON, which Android hands to the download
        // manager instead of loading, aborting the navigation partway through.
        // Half a budget in, fall back to the host root: an ordinary HTML page
        // carrying the same zone-wide challenge.
        if (!retargeted && url != origin && sw.elapsed > timeout ~/ 2) {
          retargeted = true;
          JsLog.info('cf', 'retargeting $host solve to the site root');
          try {
            await controller?.loadUrl(
              urlRequest: URLRequest(url: WebUri(origin)),
            );
          } catch (_) {}
        }

        final cookies = await CookieManager.instance()
            .getCookies(url: WebUri(origin));
        final hasClearance = cookies.any(
          (c) => c.name == 'cf_clearance' && '${c.value}'.isNotEmpty,
        );
        if (!hasClearance) continue;

        // A cf_clearance in the jar is not the same as a challenge that passed.
        // Cloudflare sets the cookie on the interstitial itself, well before the
        // JS work behind "Just a moment..." finishes, so accepting it on sight
        // handed back a token the CDN then answered 403 to. Requiring the
        // WebView to have actually left the interstitial is what makes the
        // cookie mean something.
        final stillChallenged = await controller?.evaluateJavascript(
          source: "(function(){var t=(document.title||'');"
              "return /just a moment|attention required|checking your browser/i"
              ".test(t) || !!document.getElementById('challenge-running');})()",
        );
        if (stillChallenged == true) continue;

        JsLog.res('cf', 'solved $host', ms: sw.elapsedMilliseconds);
        // Give the loop a real turn before handing the answer back.
        //
        // Without it the caller's continuation simply never ran: the log read
        // `solved animepahe.pw (7889ms)` and then nothing — no replay, not even
        // the caller's own 60s timeout. It presented as a Heisenbug, since any
        // print or log placed between the solve and the return was enough to
        // let the call through, and removing it brought the hang straight back.
        // The WebView work above leaves the platform channel busy, and this
        // yield is what lets it drain before the value is delivered. One tick
        // against a solve that already took seconds.
        await _yield();
        return _cookieHeader(cookies);
      }
      JsLog.err('cf', 'no cf_clearance for $host after ${timeout.inSeconds}s');
      await _yield();
      return null;
    } finally {
      // Tear down well clear of the return. Disposing in the same breath as
      // answering starved the caller's continuation.
      unawaited(
        Future<void>.delayed(const Duration(seconds: 2)).then((_) async {
          try {
            await headless.dispose();
          } catch (_) {}
        }),
      );
    }
  }
}
