import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/services.dart' show PlatformException, rootBundle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:soplay/core/js/dart_fetch.dart';
import 'package:soplay/core/js/js_log.dart';
import 'package:soplay/core/js/js_timeouts.dart';
import 'package:soplay/core/system/webview_env.dart';
import 'package:soplay/features/extensions/data/mangayomi_repo_store.dart';
import 'package:soplay/features/extensions/domain/entities/mangayomi_source.dart';

/// Runs Mangayomi JavaScript extensions in a headless WebView.
///
/// **This is the cross-platform extension path.** CloudStream, Aniyomi and Mihon
/// extensions are Android APKs loaded via `DexClassLoader`; there is no iOS
/// equivalent, which is why those three are Android-only. Mangayomi extensions
/// are JavaScript, and `flutter_inappwebview` gives us a JS engine on Android,
/// iOS, macOS and Windows alike — so everything here works on an iPhone.
///
/// Structure deliberately mirrors [JsRuntimeService]: one shared headless
/// WebView, a `dartFetch` handler bridging HTTP to Dio (which brings the cookie
/// jar and Cloudflare solver with it), and a **serialised** call section,
/// because all extensions share one `globalThis.__sozoProvider` slot.
class MangayomiRuntime {
  MangayomiRuntime({required this.store, required this.dartFetch});

  final MangayomiRepoStore store;
  final DartFetch dartFetch;

  HeadlessInAppWebView? _webView;
  InAppWebViewController? _controller;
  Future<void>? _ready;

  /// Which extension is currently loaded into the shared JS context.
  String? _activeId;
  String? _activeVersion;

  /// Version of each extension compiled into the page this session, by id.
  final Map<String, String> _loaded = <String, String>{};

  /// Serialises "swap the extension, then call it". Without this, two
  /// concurrent cross-search legs would race on the single `__sozoProvider`
  /// global and one source's results would be returned under another's name.
  Future<void> _gate = Future<void>.value();

  /// `flutter_inappwebview` has no Linux implementation, so JS extensions can't
  /// run there. Everywhere else — including iOS — they can.
  static bool get isSupported => !Platform.isLinux;

  Future<void> ensureReady() {
    if (!isSupported) return Future<void>.value();
    return _ready ??= _boot().catchError((Object e) {
      _ready = null;
      JsLog.err('mangayomi', 'boot failed: $e');
      throw e;
    });
  }

  static const String _bootstrapHtml = '''
<!doctype html>
<html><head><meta charset="utf-8"></head>
<body><script>
  window.dartFetch = function (req) {
    return window.flutter_inappwebview.callHandler('dartFetch', req);
  };
  window.__sozoHostReady = true;
</script></body></html>
''';

  Future<void> _boot() async {
    try {
      await _bootOnce();
    } on PlatformException catch (e) {
      // Windows: a locked WebView2 profile. Rotating to a fresh one is the
      // documented recovery — same handling as the extractor runtime.
      JsLog.err('mangayomi', 'headless webview failed: ${e.message}');
      if (!await WebViewEnv.rotate()) rethrow;
      await _bootOnce();
    }
  }

  Future<void> _bootOnce() async {
    final completer = Completer<InAppWebViewController>();
    final environment = await WebViewEnv.ensure();

    final webView = HeadlessInAppWebView(
      webViewEnvironment: environment,
      initialUrlRequest: URLRequest(url: WebUri('about:blank')),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        javaScriptCanOpenWindowsAutomatically: false,
        mediaPlaybackRequiresUserGesture: true,
        clearCache: false,
        cacheEnabled: false,
        transparentBackground: true,
        thirdPartyCookiesEnabled: true,
      ),
      onWebViewCreated: (controller) {
        controller.addJavaScriptHandler(
          handlerName: 'dartFetch',
          callback: (args) async {
            if (args.isEmpty) {
              return {'status': 0, 'data': null, 'headers': {}};
            }
            return await dartFetch.call(args.first);
          },
        );
        if (!completer.isCompleted) completer.complete(controller);
      },
      onConsoleMessage: (_, msg) =>
          JsLog.info('mangayomi', 'console: ${msg.message}'),
    );

    await webView.run();
    _webView = webView;
    final controller = await completer.future;
    _controller = controller;

    await controller.loadData(
      data: _bootstrapHtml,
      mimeType: 'text/html',
      encoding: 'utf-8',
      // A real https origin, not about:blank: DOMParser, crypto.subtle and
      // atob/btoa are all gated on a secure context in some engines.
      baseUrl: WebUri('https://sozo.local/'),
    );
    await _waitForHost(controller);

    final bridge = await rootBundle.loadString('assets/js/mangayomi_bridge.js');
    await controller.evaluateJavascript(source: bridge);
  }

  Future<void> _waitForHost(InAppWebViewController controller) async {
    for (var i = 0; i < 60; i++) {
      final flag = await controller.evaluateJavascript(
        source: 'window.__sozoHostReady === true',
      );
      if (flag == true) return;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    throw StateError('Mangayomi JS context did not initialize');
  }

  Future<T> _locked<T>(Future<T> Function() action) {
    final run = _gate.then((_) => action());
    _gate = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<void> _ensureExtension(MangayomiSource source) async {
    if (_activeId == source.id && _activeVersion == source.version) {
      // Still refresh preferences: the user may have changed one since the
      // extension was loaded, and `SharedPreferences` reads a plain global.
      await _seedPrefs(source);
      return;
    }

    // Already compiled this session — swapping back is a pointer assignment.
    // Reloading meant re-running new Function(code) on every source switch,
    // which a cross-search does once per source per query.
    if (_loaded[source.id] == source.version) {
      await _seedPrefs(source);
      final activated = await _controller!.callAsyncJavaScript(
        functionBody: r'return __sozoActivateMangayomi(id);',
        arguments: {'id': source.id},
      );
      if (activated?.value == true) {
        _activeId = source.id;
        _activeVersion = source.version;
        return;
      }
      // The page was reloaded underneath us; fall through and compile again.
      _loaded.remove(source.id);
    }

    final code = await store.code(source);
    await _seedPrefs(source);
    final result = await _controller!.callAsyncJavaScript(
      functionBody: r'return __sozoLoadMangayomi(code, source);',
      arguments: {'code': code, 'source': source.toJs()},
    );
    final error = result?.error;
    if (error != null && error.isNotEmpty) {
      throw Exception('${source.name}: $error');
    }
    _activeId = source.id;
    _activeVersion = source.version;
    _loaded[source.id] = source.version;
  }

  /// Keys extensions conventionally read their host from.
  ///
  /// Mangayomi has no schema for this — each extension picks a name — so this
  /// is the observed set, and an extension using another name still falls back
  /// to whatever the user has set.
  static const List<String> _domainKeys = [
    'domain_url',
    'overrideBaseUrl',
    'baseUrl',
    // kolnovel's own spelling. Harmless where it is unused, and the whole point
    // of this list is that it is the set actually observed in the wild rather
    // than one canonical name nobody agreed on.
    'base_url',
    'preferred_domain',
  ];

  Future<void> _seedPrefs(MangayomiSource source) async {
    final values = <String, dynamic>{};
    // The comment here used to promise defaults and the body never wrote any,
    // so on a fresh install `preference.get('domain_url')` returned '' and the
    // extension built a RELATIVE url. That reaches Dio with no host, throws
    // "No host specified in URI", is caught, and comes back as zero results —
    // indistinguishable from a title genuinely not being there.
    if (source.baseUrl.isNotEmpty) {
      for (final key in _domainKeys) {
        values[key] = source.baseUrl;
      }
    }
    // The user's own choices still win.
    values.addAll(store.prefs(source.id));
    await _controller!.evaluateJavascript(
      source: 'globalThis.__sozoPrefs = ${jsonEncode(values)};'
          'globalThis.__sozoPrefsDirty = false;',
    );
  }

  Future<void> _flushPrefs(MangayomiSource source) async {
    try {
      final dirty = await _controller!
          .evaluateJavascript(source: 'globalThis.__sozoPrefsDirty === true');
      if (dirty != true) return;
      final raw = await _controller!.evaluateJavascript(
        source: 'JSON.stringify(globalThis.__sozoPrefs || {})',
      );
      if (raw is! String || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        await store.savePrefs(source.id, Map<String, dynamic>.from(decoded));
      }
    } catch (e) {
      JsLog.err('mangayomi', 'prefs flush: $e');
    }
  }

  /// Calls one method on [sourceId]'s extension and returns its decoded result.
  ///
  /// Returns null when the source isn't installed or the platform has no JS
  /// engine. Throws with the extension's own error message when the call fails
  /// — those messages ("Cannot read properties of null") are the only real
  /// diagnostic a broken source gives, so they must reach the UI.
  Future<dynamic> call(
    String sourceId,
    String method, {
    List<Object?> args = const [],
  }) async {
    if (!isSupported) return null;
    final source = store.sourceById(sourceId);
    if (source == null) return null;

    final tag = 'mangayomi:${source.name}';
    final sw = Stopwatch()..start();
    JsLog.req(tag, method);
    await ensureReady();

    // Bounded, and bounded INSIDE the lock. Every call queues behind _gate, so a
    // single extension that never answers — a Cloudflare solve that never
    // resolves, most often — used to hold every later call behind it forever,
    // which is a screen left shimmering with nothing to time out.
    final result = await _locked(() async {
      await _ensureExtension(source).timeout(kJsCallTimeout);
      final r = await _controller!.callAsyncJavaScript(
        functionBody: r'''
          const p = globalThis.__sozoProvider;
          const fn = p ? p[fnName] : null;
          if (typeof fn !== 'function') {
            throw new Error('Extension does not implement ' + fnName);
          }
          const out = await fn.apply(p, fnArgs);
          // Stringify here rather than relying on the bridge's own conversion:
          // the WebView<->Dart channel flattens class instances, and every
          // extension returns plain data anyway.
          return out === undefined ? null : JSON.stringify(out);
        ''',
        arguments: {'fnName': method, 'fnArgs': args},
      ).timeout(kJsCallTimeout);
      await _flushPrefs(source);
      return r;
    });

    if (result == null) {
      JsLog.err(tag, '$method returned null');
      return null;
    }
    final error = result.error;
    if (error != null && error.isNotEmpty) {
      JsLog.err(tag, '$method threw: $error');
      throw Exception(error);
    }
    JsLog.res(tag, method, ms: sw.elapsedMilliseconds, status: 200);
    final value = result.value;
    if (value == null) return null;
    if (value is String) {
      if (value.isEmpty || value == 'null') return null;
      try {
        return jsonDecode(value);
      } catch (_) {
        return value;
      }
    }
    return value;
  }

  /// Drops the loaded extension so the next call re-reads its code. Used after
  /// an update or a preference change that alters the base url.
  void invalidate([String? sourceId]) {
    // Must drop the compiled instance too, not just the active pointer: the
    // whole point of this call is to make the next one re-read the code, and a
    // cached instance would be handed straight back instead.
    if (sourceId == null) {
      _loaded.clear();
    } else {
      _loaded.remove(sourceId);
    }
    if (sourceId == null || sourceId == _activeId) {
      _activeId = null;
      _activeVersion = null;
    }
  }

  Future<void> dispose() async {
    try {
      await _webView?.dispose();
    } catch (e) {
      JsLog.err('mangayomi', 'dispose: $e');
    }
    _webView = null;
    _controller = null;
    _ready = null;
    _activeId = null;
    _activeVersion = null;
    _loaded.clear();
  }
}
