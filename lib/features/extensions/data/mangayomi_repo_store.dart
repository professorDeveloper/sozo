import 'package:soplay/core/network/user_agent.dart';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:hive/hive.dart';

import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/features/extensions/domain/entities/mangayomi_source.dart';

/// Installs and persists Mangayomi repositories, entirely in Dart.
///
/// Unlike the CloudStream / Aniyomi / Manga hosts — which live in Kotlin because
/// they load Android APKs — nothing here is platform-specific: a Mangayomi
/// "extension" is a `.js` file, so installing one is fetching JSON and caching
/// text. That is what makes the whole feature work on iOS, macOS and Windows as
/// well as Android.
///
/// A repo publishes up to three sibling indexes (`index.json`,
/// `anime_index.json`, `novel_index.json`); each is stored under its own url so
/// removing one doesn't take the others with it.
class MangayomiRepoStore {
  MangayomiRepoStore({required this.dio});

  final Dio dio;

  static const _reposKey = 'mangayomi_repos';
  static const _sourcesKey = 'mangayomi_sources';
  static const _codePrefix = 'mangayomi_code:';
  static const _prefsPrefix = 'mangayomi_prefs:';

  Box get _box => Hive.box(AppConstants.settingsBox);

  /// A dedicated Dio: the app's shared instance is pinned to our own API with a
  /// baseUrl, auth interceptors and certificate pinning, none of which apply to
  /// a third-party GitHub raw url.
  late final Dio _net = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
      responseType: ResponseType.plain,
      headers: {
        'User-Agent': kSozoUserAgent,
      },
      // GitHub raw serves 404s for missing sibling indexes; treat any status as
      // a response so a missing anime_index.json isn't an exception.
      validateStatus: (_) => true,
    ),
  );

  // --- repos ---------------------------------------------------------------

  List<String> repos() {
    final raw = _box.get(_reposKey);
    if (raw is! String || raw.isEmpty) return <String>[];
    try {
      final list = jsonDecode(raw);
      return list is List
          ? list.map((e) => e.toString()).toList()
          : <String>[];
    } catch (_) {
      return <String>[];
    }
  }

  Future<void> _saveRepos(List<String> urls) =>
      _box.put(_reposKey, jsonEncode(urls));

  // --- sources -------------------------------------------------------------

  /// Installed sources. Always a **growable** list: callers sort and filter it,
  /// and `List.sort` throws on an unmodifiable list even when it is empty.
  List<MangayomiSource> sources() {
    final raw = _box.get(_sourcesKey);
    if (raw is! String || raw.isEmpty) return <MangayomiSource>[];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return <MangayomiSource>[];
      return list
          .whereType<Map>()
          .map((e) => MangayomiSource.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return <MangayomiSource>[];
    }
  }

  Future<void> _saveSources(List<MangayomiSource> list) =>
      _box.put(_sourcesKey, jsonEncode(list.map((e) => e.toJson()).toList()));

  MangayomiSource? sourceById(String id) {
    final bare = id.startsWith('my:') ? id.substring(3) : id;
    for (final s in sources()) {
      if (s.id == bare) return s;
    }
    return null;
  }

  // --- install / remove ----------------------------------------------------

  /// Fetches [indexUrl] and merges its JavaScript sources into the installed set.
  ///
  /// Returns `{added, total, skippedDart}`. `skippedDart` is reported rather
  /// than hidden: several large repos are majority-Dart, and a user who
  /// installs one and sees a third of the advertised count needs to know why.
  Future<Map<String, int>> addRepo(String indexUrl) async {
    final url = indexUrl.trim();
    if (url.isEmpty) return const {'added': 0, 'total': 0, 'skippedDart': 0};

    final resp = await _net.get<String>(url);
    if (resp.statusCode == null ||
        resp.statusCode! < 200 ||
        resp.statusCode! >= 300) {
      throw Exception('HTTP ${resp.statusCode} for $url');
    }

    final decoded = jsonDecode(resp.data ?? '[]');
    if (decoded is! List) throw Exception('Unexpected index format');

    final existing = sources();
    final byId = {for (final s in existing) s.id: s};
    var added = 0;
    var skippedDart = 0;

    for (final entry in decoded.whereType<Map>()) {
      final src = MangayomiSource.fromIndexJson(
        Map<String, dynamic>.from(entry),
        repoUrl: url,
      );
      if (src == null) continue;
      if (!src.isJavaScript) {
        skippedDart++;
        continue;
      }
      if (!byId.containsKey(src.id)) added++;
      byId[src.id] = src;
    }

    await _saveSources(byId.values.toList());
    final list = repos();
    if (!list.contains(url)) {
      await _saveRepos([...list, url]);
    }
    return {
      'added': added,
      'total': byId.values.where((s) => s.repoUrl == url).length,
      'skippedDart': skippedDart,
    };
  }

  Future<void> removeRepo(String indexUrl) async {
    final url = indexUrl.trim();
    final kept = sources().where((s) => s.repoUrl != url).toList();
    await _saveSources(kept);
    await _saveRepos(repos().where((r) => r != url).toList());
    // Cached extension code for the dropped sources is left behind on purpose:
    // it is a few KB per source and re-adding the repo is instant with it warm.
    // It is cleaned up by [clearCode] when the user asks explicitly.
  }

  /// Re-fetches every installed repo index, replacing the stored metadata and
  /// dropping cached code for sources whose version changed. Returns how many
  /// sources were updated.
  Future<int> checkUpdates() async {
    final before = {for (final s in sources()) s.id: s.version};
    for (final repo in repos()) {
      try {
        await addRepo(repo);
      } catch (_) {
        // One dead repo must not abort the rest.
      }
    }
    var updated = 0;
    for (final s in sources()) {
      final old = before[s.id];
      if (old != null && old != s.version) {
        updated++;
        await _box.delete('$_codePrefix${s.id}');
      }
    }
    return updated;
  }

  // --- extension code ------------------------------------------------------

  /// The extension's JavaScript, downloaded once and cached under its version.
  ///
  /// Cached per (id, version) so a repo bump invalidates it automatically —
  /// keying on id alone would pin the first version forever, which is exactly
  /// the bug the APK hosts had.
  Future<String> code(MangayomiSource source) async {
    final key = '$_codePrefix${source.id}';
    final cached = _box.get(key);
    if (cached is Map && cached['version'] == source.version) {
      final js = cached['code'];
      if (js is String && js.isNotEmpty) return js;
    }
    final resp = await _net.get<String>(source.sourceCodeUrl);
    final body = resp.data ?? '';
    if (resp.statusCode == null ||
        resp.statusCode! < 200 ||
        resp.statusCode! >= 300 ||
        body.isEmpty) {
      throw Exception(
          'Could not download ${source.name} (HTTP ${resp.statusCode})');
    }
    await _box.put(key, {'version': source.version, 'code': body});
    return body;
  }

  Future<void> clearCode(String sourceId) => _box.delete('$_codePrefix$sourceId');

  // --- per-source preferences ---------------------------------------------

  /// Values behind the extension's `SharedPreferences`. Seeded into the JS
  /// context before each call and written back when the extension changes one.
  Map<String, dynamic> prefs(String sourceId) {
    final raw = _box.get('$_prefsPrefix$sourceId');
    if (raw is! String || raw.isEmpty) return {};
    try {
      final m = jsonDecode(raw);
      return m is Map ? Map<String, dynamic>.from(m) : {};
    } catch (_) {
      return {};
    }
  }

  Future<void> savePrefs(String sourceId, Map<String, dynamic> values) =>
      _box.put('$_prefsPrefix$sourceId', jsonEncode(values));
}
