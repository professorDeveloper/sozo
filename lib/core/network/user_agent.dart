import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// The single User-Agent this app presents.
///
/// Cloudflare binds cf_clearance to the exact User-Agent that solved the
/// challenge, so a clearance earned under one and replayed under another is
/// rejected. The Dart side carried five different strings — and the extension
/// HTTP client carried none at all, which means dart:io stamped
/// `Dart/3.x (dart:io)` on every request an extension made. Cloudflare and
/// plenty of ordinary WAFs refuse that outright.
///
/// The Android TV app had the same disease and the same cure.
///
/// One string, but not a *made-up* one. A managed challenge does not only read
/// the header: it compares what the header claims against what the engine
/// actually is — client hints, `navigator.userAgentData`, platform, engine
/// version. A hard-coded `Chrome/125` on a device whose WebView is 130-something
/// is exactly that kind of mismatch, and the challenge then never clears no
/// matter how long the WebView is left running. Measured against animepahe.pw,
/// which is behind a managed challenge: a browser presenting a User-Agent that
/// matched its real platform cleared in ~4s, while every UA that misdescribed
/// the platform sat at "Just a moment..." until the 35s watchdog gave up.
///
/// So the value is the device's OWN WebView User-Agent, read once at startup
/// and reused everywhere. [kSozoUserAgentFallback] only applies when that read
/// fails (a platform with no WebView, or an early call).
const String kSozoUserAgentFallback =
    'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36';

String _resolved = kSozoUserAgentFallback;

/// The agent every request in this app must carry.
///
/// Synchronous on purpose — it is read from header maps all over the codebase.
/// Before [initSozoUserAgent] completes it returns the fallback, which is
/// harmless: nothing that needs a clearance runs that early.
String get kSozoUserAgent => _resolved;

/// Whether the value in use came from the device rather than the fallback.
bool get sozoUserAgentIsDeviceReported => _resolved != kSozoUserAgentFallback;

/// Adopt the device's real WebView User-Agent. Call once, during startup.
///
/// Safe to call more than once and safe to fail: on any error the fallback
/// stays in place and the app behaves exactly as it did before.
Future<void> initSozoUserAgent() async {
  try {
    final ua = (await InAppWebViewController.getDefaultUserAgent()).trim();
    // A WebView that reports something implausible is worse than the fallback:
    // the whole point is that the string matches the engine behind it.
    if (ua.length >= 40 && ua.startsWith('Mozilla/')) {
      // Verbatim, `; wv` and all.
      //
      // An earlier version stripped that token so the string would not announce
      // an embedded browser. That was the same mistake in a smaller costume: the
      // engine behind this really is an Android WebView, and a challenge that
      // compares the header against the engine sees a UA claiming plain Chrome
      // and a WebView answering. The whole point of reading the device's agent
      // is that it is TRUE — editing it puts the lie back.
      _resolved = ua;
    }
  } catch (_) {
    // Keep the fallback.
  }
}
