import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:soplay/core/extensions/extension_bridge.dart';

class CloudStreamChannel {
  CloudStreamChannel._();

  static const MethodChannel _ch = MethodChannel('soplay/cloudstream');

  static bool get isSupported =>
      Platform.isAndroid || ExtensionBridge.isEnabled;

  static final StreamController<({int current, int total})> _progressCtrl =
      StreamController<({int current, int total})>.broadcast();
  static bool _handlerSet = false;

  static void _ensureHandler() {
    if (_handlerSet || !isSupported) return;
    _handlerSet = true;
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'installProgress') {
        final a = call.arguments;
        if (a is Map) {
          _progressCtrl.add((
            current: (a['current'] as num?)?.toInt() ?? 0,
            total: (a['total'] as num?)?.toInt() ?? 0,
          ));
        }
      }
      return null;
    });
  }

  static Stream<({int current, int total})> get installProgress {
    _ensureHandler();
    return _progressCtrl.stream;
  }

  static Future<String?> _call(
    String method, [
    Map<String, dynamic>? args,
  ]) async {
    if (Platform.isAndroid) {
      try {
        return await _ch.invokeMethod<String>(method, args);
      } on PlatformException {
        return null;
      } on MissingPluginException {
        return null;
      }
    }
    if (ExtensionBridge.isEnabled) {
      return ExtensionBridge.instance.call('cloudstream', method, args);
    }
    return null;
  }

  static Map<String, dynamic> _obj(String? s) {
    if (s == null || s.isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(s);
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }

  static List<dynamic> _arr(String? s) {
    if (s == null || s.isEmpty) return const [];
    final decoded = jsonDecode(s);
    return decoded is List ? decoded : const [];
  }

  static Future<List<dynamic>> listProviders() async =>
      _arr(await _call('listProviders'));

  static Future<List<dynamic>> ensureLoaded() async =>
      _arr(await _call('ensureLoaded'));

  static Future<List<dynamic>> listRepos() async =>
      _arr(await _call('listRepos'));

  static Future<Map<String, dynamic>> removeRepo(String url) async =>
      _obj(await _call('removeRepo', {'url': url}));

  static Future<Map<String, dynamic>> addRepo(String url) async =>
      _obj(await _call('addRepo', {'url': url}));

  static Future<Map<String, dynamic>> checkUpdates() async =>
      _obj(await _call('checkUpdates'));

  /// List every plugin in a repo (without installing), each flagged `installed`.
  static Future<Map<String, dynamic>> listRepoPlugins(String url) async =>
      _obj(await _call('listRepoPlugins', {'url': url}));

  /// Install a single plugin from a repo by its `internalName`.
  static Future<Map<String, dynamic>> installPlugin(
    String url,
    String internalName,
  ) async => _obj(
    await _call('installPlugin', {'url': url, 'internalName': internalName}),
  );

  /// Uninstall a single plugin by its `internalName`.
  static Future<Map<String, dynamic>> uninstallPlugin(
    String url,
    String internalName,
  ) async => _obj(
    await _call('uninstallPlugin', {'url': url, 'internalName': internalName}),
  );

  static Future<List<dynamic>> getGenres(String provider) async =>
      _arr(await _call('getGenres', {'provider': provider}));

  static Future<Map<String, dynamic>> getMainPage(
    String provider, {
    int page = 1,
  }) async =>
      _obj(await _call('getMainPage', {'provider': provider, 'page': page}));

  static Future<Map<String, dynamic>> getSection(
    String provider,
    String data, {
    int page = 1,
  }) async => _obj(
    await _call('getSection', {
      'provider': provider,
      'data': data,
      'page': page,
    }),
  );

  static Future<Map<String, dynamic>> search(
    String provider,
    String query, {
    int page = 1,
  }) async => _obj(
    await _call('search', {'provider': provider, 'query': query, 'page': page}),
  );

  static Future<Map<String, dynamic>> load(String provider, String url) async =>
      _obj(await _call('load', {'provider': provider, 'url': url}));

  static Future<Map<String, dynamic>> loadLinks(
    String provider,
    String data,
  ) async =>
      _obj(await _call('loadLinks', {'provider': provider, 'data': data}));

  static Future<Map<String, dynamic>> cloudflareInfo(String id) async =>
      _obj(await _call('cloudflareInfo', {'id': id}));
}
