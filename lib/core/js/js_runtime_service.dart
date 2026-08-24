import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:soplay/core/system/webview_env.dart';

import 'dart_fetch.dart';
import 'extractor_cache.dart';
import 'extractor_remote.dart';
import 'js_log.dart';
import 'js_timeouts.dart';
import 'provider_registry.dart';

class JsRuntimeService {
  final ExtractorRemote remote;
  final ExtractorCache cache;
  final DartFetch dartFetch;
  final ProviderRegistry providers;

  HeadlessInAppWebView? _webView;
  InAppWebViewController? _controller;
  Future<void>? _ready;
  ExtractorManifest? _manifest;
  /// Extractors already evaluated into the page, keyed `name@version`.
  ///
  /// Each is registered ONCE per session. The previous design kept a single
  /// mutable `globalThis.Provider` and re-evaluated the whole extractor source
  /// whenever a different provider was asked for — so a cross-search over six
  /// providers re-parsed six scripts, in sequence, on every query.
  final Set<String> _registered = <String>{};

  /// Registrations in flight, so two legs racing for the same provider fetch
  /// and evaluate it once rather than twice.
  final Map<String, Future<void>> _registering = <String, Future<void>>{};

  // Serializes registration only. Calls no longer need a gate: they resolve
  // their provider from a registry rather than a shared mutable global, so a
  // second leg can no longer swap it out mid-flight.
  Future<void> _jsGate = Future<void>.value();

  static const String _runtimeName = '__runtime__';
  static const String _bootstrapHtml = '''
<!doctype html>
<html><head><meta charset="utf-8"></head>
<body><script>
  window.dartFetch = function(req) {
    return window.flutter_inappwebview.callHandler('dartFetch', req);
  };
  window.__sozoReady = true;
</script></body></html>
''';

  JsRuntimeService({
    required this.remote,
    required this.cache,
    required this.dartFetch,
    required this.providers,
  });

  /// flutter_inappwebview ships no Linux implementation, so client/hybrid
  /// providers (which run their extractor inside a webview) can't work there.
  static bool get isSupported => !Platform.isLinux;

  Future<void> ensureReady() {
    if (!isSupported) return Future<void>.value();
    return _ready ??= _boot().catchError((Object e) {
      _ready = null;
      JsLog.err('js', 'boot failed: $e');
      throw e;
    });
  }

  Future<bool> isClientCatalog(String provider) async {
    final p = await providers.getById(provider);
    return p?.scopesAll == true;
  }

  Future<bool> isJsResolveMedia(String provider) async {
    final p = await providers.getById(provider);
    return p?.scopesResolveMedia == true;
  }

  Future<Map<String, dynamic>?> tryGetHome(String provider) =>
      _callObject(provider, 'getHome', requireAll: true);

  Future<Map<String, dynamic>?> tryGetCategory(
    String provider,
    String slug,
    int page,
  ) =>
      _callObject(
        provider,
        'getCategory',
        requireAll: true,
        args: [slug, page],
      );

  Future<Map<String, dynamic>?> trySearch(
    String provider,
    String query,
    int page,
  ) =>
      _callObject(
        provider,
        'search',
        requireAll: true,
        args: [query, page],
      );

  Future<Map<String, dynamic>?> tryGetDetail(String provider, String url) =>
      _callObject(provider, 'getDetail', requireAll: true, args: [url]);

  Future<Map<String, dynamic>?> tryGetEpisodes(String provider, String url) =>
      _callObject(provider, 'getEpisodes', requireAll: true, args: [url]);

  Future<Map<String, dynamic>?> tryResolveMedia({
    required String provider,
    required String ref,
    String? lang,
  }) =>
      _callObject(
        provider,
        'resolveMedia',
        requireAll: false,
        args: [ref, {'lang': lang ?? 'sub'}],
      );

  // Runs [action] after any in-flight locked section completes, so only one
  // holds the shared `Provider` at a time. A failing action never poisons the
  // gate for the next caller.
  Future<T> _locked<T>(Future<T> Function() action) {
    final run = _jsGate.then((_) => action());
    _jsGate = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<Map<String, dynamic>?> _callObject(
    String provider,
    String fn, {
    required bool requireAll,
    List<Object?> args = const [],
  }) async {
    final tag = 'js:$provider';
    final entity = await providers.getById(provider);
    if (entity == null) {
      JsLog.info(tag, 'skip $fn — provider not in registry');
      return null;
    }
    final eligible = requireAll ? entity.scopesAll : entity.scopesResolveMedia;
    if (!eligible) {
      JsLog.info(
        tag,
        'skip $fn — scope=${entity.extractor?.scope ?? "none"} mode=${entity.mode}',
      );
      return null;
    }
    if (!isSupported) {
      JsLog.info(tag, 'skip $fn — no webview runtime on this platform');
      return null;
    }
    final extractor = entity.extractor!;
    final sw = Stopwatch()..start();
    JsLog.req(tag, '$fn(${_summarizeArgs(args)})');
    try {
      await ensureReady().timeout(kJsCallTimeout);
      // Serialize extractor-swap + call: concurrent cross-search legs share one
      // webview and one globalThis.Provider, so without this a second leg could
      // swap Provider between this leg's setup and its call — returning one
      // provider's results under another's name.
      await _ensureExtractor(extractor.name, extractor.version)
          .timeout(kJsCallTimeout);
      // Any request this call refuses is recorded on DartFetch; clearing it
      // first means whatever is left afterwards belongs to THIS call.
      dartFetch.clearBlock();
      // Unlocked on purpose. The provider is looked up by name, so several
      // cross-search legs can be in flight at once and their network waits
      // overlap instead of queueing — which is what made searching several
      // sources feel frozen.
      final result = await _controller!.callAsyncJavaScript(
        functionBody: r'''
            const __registry = (globalThis.__sozo || {}).providers || {};
            const __p = __registry[providerName];
            if (!__p) {
              throw new Error('Provider "' + providerName + '" is not loaded');
            }
            const __fn = __p[fnName];
            if (typeof __fn !== 'function') {
              throw new Error('Provider.' + fnName + ' is not implemented');
            }
            const __r = await __fn.apply(__p, fnArgs);
            return __r === undefined ? null : __r;
          ''',
        arguments: {
          'providerName': extractor.name,
          'fnName': fn,
          'fnArgs': args,
        },
      ).timeout(kJsCallTimeout);

      if (result == null) {
        JsLog.err(tag, '$fn returned null result');
        return null;
      }
      final error = result.error;
      if (error != null && error.isNotEmpty) {
        // An extractor parses whatever body it is handed, so a Cloudflare
        // challenge surfaces as a JSON parse error deep in provider code. When
        // the network layer refused something during this call, that refusal is
        // the cause and the only half a user can act on.
        final blocked = dartFetch.takeBlock();
        JsLog.err(tag, '$fn threw: $error${blocked == null ? '' : ' ($blocked)'}');
        throw Exception(blocked ?? error);
      }
      dartFetch.clearBlock();
      final map = _coerceMap(result.value);
      JsLog.res(
        tag,
        fn,
        ms: sw.elapsedMilliseconds,
        status: map == null ? 0 : 200,
      );
      return map;
    } catch (e) {
      JsLog.err(tag, '$fn — $e');
      rethrow;
    }
  }

  Map<String, dynamic>? _coerceMap(dynamic value) {
    if (value == null) return null;
    if (value is Map) return value.cast<String, dynamic>();
    if (value is String) {
      if (value.isEmpty || value == 'null') return null;
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) return decoded.cast<String, dynamic>();
      } catch (_) {}
    }
    return null;
  }

  String _summarizeArgs(List<Object?> args) {
    if (args.isEmpty) return '';
    return args
        .map((a) {
          final s = a is String ? '"${_clip(a, 60)}"' : a.toString();
          return _clip(s, 80);
        })
        .join(', ');
  }

  String _clip(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}…';

  Future<void> _boot() async {
    try {
      await _bootOnce();
    } on PlatformException catch (e) {
      // Windows: the WebView2 profile is locked (orphaned msedgewebview2, a
      // second window, or a read-only install dir). Move to a fresh profile and
      // try once more — otherwise every client/hybrid provider stays dead.
      JsLog.err('js', 'headless webview failed: ${e.message}');
      if (!await WebViewEnv.rotate()) rethrow;
      await _bootOnce();
    }
  }

  Future<void> _bootOnce() async {
    final controllerCompleter = Completer<InAppWebViewController>();
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
        if (!controllerCompleter.isCompleted) {
          controllerCompleter.complete(controller);
        }
      },
      onConsoleMessage: (_, msg) {
        JsLog.info('js', 'console: ${msg.message}');
      },
    );

    await webView.run();
    _webView = webView;
    final controller = await controllerCompleter.future;
    _controller = controller;

    await controller.loadData(
      data: _bootstrapHtml,
      mimeType: 'text/html',
      encoding: 'utf-8',
      baseUrl: WebUri('https://sozo.local/'),
    );
    await _waitForReady(controller);

    final manifest = await remote.fetchManifest();
    _manifest = manifest;
    await _ensureRuntime(manifest.runtime);
  }

  Future<void> _waitForReady(InAppWebViewController controller) async {
    for (var i = 0; i < 60; i++) {
      final flag = await controller.evaluateJavascript(
        source: 'window.__sozoReady === true',
      );
      if (flag == true) return;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    throw StateError('WebView JS context did not initialize');
  }

  Future<void> _ensureRuntime(ExtractorAsset asset) async {
    final wantedVersion = asset.version > 0 ? asset.version : 1;
    final cachedVersion = cache.readVersion(_runtimeName);
    String? code;
    if (cachedVersion == wantedVersion) {
      code = cache.readCode(_runtimeName, cachedVersion!);
    }
    if (code == null || code.isEmpty) {
      final fetched = await remote.fetchRuntime();
      code = fetched.code;
      final effective = wantedVersion > 0 ? wantedVersion : fetched.version;
      await cache.writeCode(
        name: _runtimeName,
        version: effective > 0 ? effective : 1,
        code: code,
      );
    }
    if (code.isEmpty) throw StateError('Runtime JS is empty');
    await _controller!.evaluateJavascript(source: code);
  }

  /// Evaluates [name] into the page if it is not already there.
  ///
  /// Returns as soon as the extractor is registered; repeat calls are free.
  Future<void> _ensureExtractor(String name, int wantedVersion) {
    final pending = _registering[name];
    if (pending != null) return pending;
    final run = _registerExtractor(name, wantedVersion);
    _registering[name] = run;
    return run.whenComplete(() => _registering.remove(name));
  }

  Future<void> _registerExtractor(String name, int wantedVersion) async {
    final manifest = _manifest ??= await remote.fetchManifest();
    final entry = manifest.byName(name);
    final version = entry?.version ?? wantedVersion;
    if (_registered.contains('$name@$version')) return;

    final cachedVersion = cache.readVersion(name);
    String? code;
    if (cachedVersion == version && version > 0) {
      code = cache.readCode(name, version);
    }
    if (code == null || code.isEmpty) {
      final fetched = await remote.fetchExtractor(name);
      code = fetched.code;
      final effective = version > 0 ? version : fetched.version;
      await cache.writeCode(
        name: name,
        version: effective > 0 ? effective : 1,
        code: code,
      );
    }
    if (code.isEmpty) throw StateError('Extractor "$name" JS is empty');
    // Each extractor keeps its own slot. `Provider` stays lexically scoped to
    // this IIFE, so an extractor's own methods referring to it by name still
    // resolve to their own object rather than to whoever registered last.
    final slot = jsonEncode(name);
    final wrapped = '''
(function(){
  const __sozo = globalThis.__sozo || (globalThis.__sozo = {});
  const __providers = __sozo.providers || (__sozo.providers = {});
  $code
  if (typeof Provider !== 'undefined') {
    __providers[$slot] = Provider;
  }
})();
''';
    // Evaluation mutates the shared page, so one at a time — but only the
    // evaluation, which now happens once per extractor instead of once per call.
    await _locked(() => _controller!.evaluateJavascript(source: wrapped));
    _registered.add('$name@$version');
  }

  Future<void> dispose() async {
    try {
      await _webView?.dispose();
    } catch (e) {
      JsLog.err('js', 'dispose: $e');
    }
    _webView = null;
    _controller = null;
    _ready = null;
    _registered.clear();
    _registering.clear();
  }
}
