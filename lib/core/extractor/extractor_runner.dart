import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:soplay/core/system/webview_env.dart';

import 'extractor_entity.dart';

class ExtractorRunner {
  final Dio _dio;
  final Map<String, String> _jsCache = {};
  HeadlessInAppWebView? _headless;
  InAppWebViewController? _webViewController;
  bool _runtimeLoaded = false;
  String? _runtimeJs;

  ExtractorRunner({required Dio dio}) : _dio = dio;

  Future<void> loadRuntime() async {
    if (_runtimeLoaded) return;
    final response = await _dio.get<String>(
      '/extractors/runtime',
      options: Options(
        responseType: ResponseType.plain,
        extra: const {'skipAuthInterceptor': true},
      ),
    );
    if (response.data != null) {
      _runtimeJs = response.data!;
      _runtimeLoaded = true;
      debugPrint('[ExtractorRunner] runtime loaded');
    }
  }

  Future<void> loadExtractor(ExtractorEntity extractor) async {
    if (_jsCache.containsKey(extractor.name)) return;
    final response = await _dio.get<String>(
      extractor.url,
      options: Options(
        responseType: ResponseType.plain,
        extra: const {'skipAuthInterceptor': true},
      ),
    );
    if (response.data != null) {
      _jsCache[extractor.name] = response.data!;
      debugPrint('[ExtractorRunner] loaded: ${extractor.name}');
    }
  }

  Future<Map<String, dynamic>> call(
    String extractorName,
    String method, [
    dynamic args,
  ]) async {
    if (!_runtimeLoaded || _runtimeJs == null) {
      throw Exception('Runtime not loaded. Call loadRuntime() first.');
    }

    final js = _jsCache[extractorName];
    if (js == null) {
      throw Exception('Extractor "$extractorName" not loaded');
    }

    final argsJson = args != null ? jsonEncode(args) : '{}';
    final functionBody =
        '''
try {
  $_runtimeJs
  $js
  if (typeof Provider === 'undefined' || typeof Provider.$method !== 'function') {
    return JSON.stringify({ "__error": true, "message": "Method $method not available" });
  }
  const __args = $argsJson;
  const __fn = Provider.$method.bind(Provider);
  const result = await (__fn.length <= 1 ? __fn(__args) : __fn(...Object.values(__args)));
  if (result === undefined || result === null) {
    return JSON.stringify({ "__error": true, "message": "Method $method returned empty" });
  }
  return JSON.stringify(result);
} catch (e) {
  return JSON.stringify({ "__error": true, "message": e.message || String(e) });
}
''';

    final result = await _evaluateJs(functionBody);
    debugPrint(
      '[ExtractorRunner] $method raw result: ${result == null ? 'null' : '${result.substring(0, result.length.clamp(0, 200))}${result.length > 200 ? '...' : ''}'}',
    );
    if (result == null || result == 'null') {
      throw Exception('Extractor returned null');
    }

    final decoded = jsonDecode(result) as Map<String, dynamic>;
    if (decoded['__error'] == true) {
      throw Exception(decoded['message'] as String? ?? 'JS execution error');
    }
    return decoded;
  }

  Future<String?> _evaluateJs(String functionBody) async {
    final controller = await _getOrCreateController();
    try {
      final result = await controller
          .callAsyncJavaScript(functionBody: functionBody)
          .timeout(const Duration(seconds: 15));
      if (result == null || result.error != null) return null;
      final value = result.value;
      if (value is String) return value;
      return value?.toString();
    } on TimeoutException {
      debugPrint('[ExtractorRunner] JS evaluation timed out');
      return null;
    }
  }

  Future<InAppWebViewController> _getOrCreateController() async {
    if (_webViewController != null) return _webViewController!;

    final completer = Completer<InAppWebViewController>();

    _headless = HeadlessInAppWebView(
      webViewEnvironment: await WebViewEnv.ensure(),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        domStorageEnabled: false,
        databaseEnabled: false,
        cacheEnabled: false,
        useOnLoadResource: false,
        useShouldOverrideUrlLoading: false,
        mediaPlaybackRequiresUserGesture: false,
      ),
      onWebViewCreated: (controller) {
        _webViewController = controller;
        completer.complete(controller);
      },
    );

    await _headless!.run();
    return completer.future;
  }

  void dispose() {
    _headless?.dispose();
    _headless = null;
    _webViewController = null;
    _jsCache.clear();
    _runtimeJs = null;
    _runtimeLoaded = false;
  }
}
