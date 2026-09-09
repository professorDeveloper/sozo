import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:soplay/core/extensions/extension_bridge.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/storage/hive_service.dart';

class MangaChannel {
  MangaChannel._();

  static const MethodChannel _ch = MethodChannel('soplay/manga');

  static bool get isSupported => Platform.isAndroid || ExtensionBridge.isEnabled;

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

  static Future<T?> _call<T>(String method, [Map<String, dynamic>? args]) async {
    if (Platform.isAndroid) {
      try {
        return await _ch.invokeMethod<T>(method, args);
      } on PlatformException {
        return null;
      } on MissingPluginException {
        return null;
      }
    }
    if (ExtensionBridge.isEnabled) {
      return await ExtensionBridge.instance.call('manga', method, args) as T?;
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

  /// The host collapses same-named sources down to one entry, and until now it
  /// always kept the English one. Sending the picker's language row lets it
  /// keep the user's instead — and keep each selected language as its own
  /// entry, so an aggregator that publishes one source per language stops
  /// showing up as English only. An empty list is the shipped default and
  /// reproduces the old collapsing exactly.
  static Map<String, dynamic> _langArgs() {
    final langs = getIt<HiveService>().getProviderLanguages();
    return {'languages': langs};
  }

  static Future<List<dynamic>> listProviders() async =>
      _arr(await _call<String>('listProviders', _langArgs()));

  static Future<List<dynamic>> ensureLoaded() async =>
      _arr(await _call<String>('ensureLoaded', _langArgs()));

  static Future<List<dynamic>> listRepos() async =>
      _arr(await _call<String>('listRepos'));

  static Future<Map<String, dynamic>> removeRepo(String url) async =>
      _obj(await _call<String>('removeRepo', {'url': url}));

  static Future<Map<String, dynamic>> addRepo(String url) async =>
      _obj(await _call<String>('addRepo', {'url': url}));

  /// Installs an index file opened from another app ("Open with Sozo").
  /// [path] is a copy the native side made in our cache — see `RepoFileIntent`.
  static Future<Map<String, dynamic>> addRepoFile(
    String path, {
    String name = '',
  }) async =>
      _obj(await _call<String>('addRepoFile', {'path': path, 'name': name}));

  /// Re-fetches every installed repo index and applies newer extension versions.
  /// Returns `{count, updated:[{pkg,name,version,repo}]}`.
  static Future<Map<String, dynamic>> checkUpdates() async =>
      _obj(await _call<String>('checkUpdates'));

  static Future<List<dynamic>> getGenres(String provider) async =>
      _arr(await _call<String>('getGenres', {'provider': provider}));

  static Future<Map<String, dynamic>> getMainPage(String provider,
          {int page = 1}) async =>
      _obj(await _call<String>('getMainPage', {'provider': provider, 'page': page}));

  static Future<Map<String, dynamic>> getSection(
    String provider,
    String data, {
    int page = 1,
  }) async =>
      _obj(await _call<String>(
          'getSection', {'provider': provider, 'data': data, 'page': page}));

  static Future<Map<String, dynamic>> search(String provider, String query,
          {int page = 1}) async =>
      _obj(await _call<String>(
          'search', {'provider': provider, 'query': query, 'page': page}));

  static Future<Map<String, dynamic>> load(String provider, String url) async =>
      _obj(await _call<String>('load', {'provider': provider, 'url': url}));

  static Future<Map<String, dynamic>> pageList(String provider, String data) async =>
      _obj(await _call<String>('pageList', {'provider': provider, 'data': data}));

  static Future<Map<String, dynamic>> cloudflareInfo(String id) async =>
      _obj(await _call<String>('cloudflareInfo', {'id': id}));

  static Future<List<dynamic>> getPreferences(String provider) async =>
      _arr(await _call<String>('getPreferences', {'provider': provider}));

  static Future<void> setPreference(
    String provider,
    String key,
    Object? value,
    String type,
  ) async {
    await _call<String>('setPreference', {
      'provider': provider,
      'key': key,
      'value': value,
      'type': type,
    });
  }
}
