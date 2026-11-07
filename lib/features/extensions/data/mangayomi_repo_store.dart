import 'package:soplay/core/network/user_agent.dart';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:hive_flutter/hive_flutter.dart';

import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/features/extensions/data/lnreader_patches.dart';
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
  MangayomiRepoStore({
    required this.dio,
    Future<String> Function(String key)? loadAsset,
  }) : _loadAsset = loadAsset ?? rootBundle.loadString;

  final Dio dio;
  final Future<String> Function(String key) _loadAsset;

  static const _reposKey = 'mangayomi_repos';
  static const _sourcesKey = 'mangayomi_sources';
  static const _codePrefix = 'mangayomi_code:';
  static const _prefsPrefix = 'mangayomi_prefs:';
  static const _excludedKey = 'mangayomi_excluded';
  static const _disabledKey = 'mangayomi_disabled';
  static const _updatesKey = 'mangayomi_updates';

  Box get _box => Hive.box(AppConstants.settingsBox);
  Object? _sourcesRaw;
  Map<String, MangayomiSource> _sourcesById = {};
  final _codeRequests = <String, Future<String>>{};

  void _readSources() {
    final raw = _box.get(_sourcesKey);
    if (identical(raw, _sourcesRaw) || raw == _sourcesRaw) return;
    _sourcesRaw = raw;
    _sourcesById = {};
    if (raw is! String || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      for (final entry in decoded.whereType<Map>()) {
        final source = MangayomiSource.fromJson(
          Map<String, dynamic>.from(entry),
        );
        _sourcesById[source.id] = source;
      }
    } catch (_) {
      _sourcesById = {};
    }
  }

  /// A dedicated Dio: the app's shared instance is pinned to our own API with a
  /// baseUrl, auth interceptors and certificate pinning, none of which apply to
  /// a third-party GitHub raw url.
  late final Dio _net = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
      responseType: ResponseType.plain,
      headers: {'User-Agent': kSozoUserAgent},
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
      return list is List ? list.map((e) => e.toString()).toList() : <String>[];
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
    _readSources();
    return _sourcesById.values.toList();
  }

  Future<void> _saveSources(List<MangayomiSource> list) =>
      _box.put(_sourcesKey, jsonEncode(list.map((e) => e.toJson()).toList()));

  MangayomiSource? sourceById(String id) {
    final bare = id.startsWith('my:') ? id.substring(3) : id;
    _readSources();
    return _sourcesById[bare];
  }

  // --- install / remove ----------------------------------------------------

  /// Fetches and parses [indexUrl] without installing anything.
  Future<MangayomiRepoIndex> fetchIndex(String indexUrl) async {
    final url = indexUrl.trim();
    final resp = await _net.get<String>(url);
    if (resp.statusCode == null ||
        resp.statusCode! < 200 ||
        resp.statusCode! >= 300) {
      throw Exception('HTTP ${resp.statusCode} for $url');
    }

    final body = resp.data;
    if (body == null || body.trim().isEmpty) {
      throw const FormatException('Repository returned an empty response');
    }
    final decoded = jsonDecode(body);
    if (decoded is! List) throw Exception('Unexpected index format');

    // Two index shapes, told apart by what the entries carry rather than by
    // where they came from — so a mirror, a fork or a local copy of either one
    // still works. See [MangayomiSource.looksLikeLnReaderIndex].
    final lnReader = MangayomiSource.looksLikeLnReaderIndex(decoded);
    final sources = <MangayomiSource>[];
    var skippedDart = 0;
    var validEntries = 0;
    for (final entry in decoded.whereType<Map>()) {
      final json = Map<String, dynamic>.from(entry);
      final src = lnReader
          ? MangayomiSource.fromLnReaderJson(json, repoUrl: url)
          : MangayomiSource.fromIndexJson(json, repoUrl: url);
      if (src == null) continue;
      validEntries++;
      if (!src.isJavaScript) {
        skippedDart++;
        continue;
      }
      sources.add(src);
    }

    if (decoded.isNotEmpty && validEntries == 0) {
      throw const FormatException(
        'Repository contains no valid source entries',
      );
    }
    return MangayomiRepoIndex(
      url: url,
      sources: sources,
      skippedDart: skippedDart,
    );
  }

  /// Fetches [indexUrl] and installs every JavaScript source in it, including
  /// ones the user removed earlier.
  ///
  /// Returns `{added, total, skippedDart}`. `skippedDart` is reported rather
  /// than hidden: several large repos are majority-Dart, and a user who
  /// installs one and sees a third of the advertised count needs to know why.
  Future<Map<String, int>> addRepo(String indexUrl) async {
    final url = indexUrl.trim();
    if (url.isEmpty) return const {'added': 0, 'total': 0, 'skippedDart': 0};
    final index = await fetchIndex(url);

    final existing = sources();
    // Replace this repository's snapshot; a successful refresh can retire IDs.
    // Keep other repositories until their own index has been fetched successfully.
    final byId = {
      for (final s in existing.where((s) => s.repoUrl != url)) s.id: s,
    };
    final oldIds = existing.map((s) => s.id).toSet();
    var added = 0;
    for (final src in index.sources) {
      if (!oldIds.contains(src.id)) added++;
      byId[src.id] = src;
    }
    final retired = existing
        .where((s) => s.repoUrl == url && !byId.containsKey(s.id))
        .map((s) => s.id)
        .toList();

    await _saveSources(byId.values.toList());
    await _forget(retired);
    await _setExcluded(url, const <String>{});
    await _dropUpdates(index.sources.map((s) => s.id));
    await _addRepoUrl(url);
    return {
      'added': added,
      'total': byId.values.where((s) => s.repoUrl == url).length,
      'skippedDart': index.skippedDart,
    };
  }

  /// Installs only the sources of [index] whose ids are in [ids].
  ///
  /// Sources of this repo the user did not pick are remembered as excluded, so
  /// a later refresh does not install them behind the user's back. Picking one
  /// here lifts its exclusion.
  Future<Map<String, int>> installSources(
    MangayomiRepoIndex index,
    Set<String> ids,
  ) async {
    final url = index.url;
    final existing = sources();
    final byId = {for (final s in existing) s.id: s};
    final installedHere = existing
        .where((s) => s.repoUrl == url)
        .map((s) => s.id)
        .toSet();
    var added = 0;
    var total = 0;
    for (final src in index.sources) {
      if (!ids.contains(src.id)) continue;
      if (!byId.containsKey(src.id)) added++;
      total++;
      byId[src.id] = src;
    }
    final excluded = {
      ...excludedIds(url),
      ...index.sources
          .map((s) => s.id)
          .where((id) => !ids.contains(id) && !installedHere.contains(id)),
    }..removeAll(ids);

    await _saveSources(byId.values.toList());
    await _setExcluded(url, excluded);
    await _dropUpdates(ids);
    await _addRepoUrl(url);
    return {'added': added, 'total': total, 'skippedDart': index.skippedDart};
  }

  Future<void> _addRepoUrl(String url) async {
    final list = repos();
    if (!list.contains(url)) await _saveRepos([...list, url]);
  }

  /// Uninstalls one source and keeps it out of later refreshes of its repo.
  Future<void> removeSource(String id) async {
    final bare = id.startsWith('my:') ? id.substring(3) : id;
    final source = sourceById(bare);
    if (source == null) return;
    final all = sources();
    await _saveSources(all.where((s) => s.id != bare).toList());
    if (source.repoUrl.isNotEmpty) {
      await _setExcluded(source.repoUrl, {
        ...excludedIds(source.repoUrl),
        bare,
      });
    }
    await _forget([bare]);
  }

  Future<void> removeRepo(String indexUrl) async {
    final url = indexUrl.trim();
    final all = sources();
    final dropped = all.where((s) => s.repoUrl == url).map((s) => s.id);
    await _saveSources(all.where((s) => s.repoUrl != url).toList());
    await _saveRepos(repos().where((r) => r != url).toList());
    await _setExcluded(url, const <String>{});
    await _forget(dropped.toList());
  }

  /// Drops everything stored for sources that are no longer installed.
  Future<void> _forget(List<String> ids) async {
    if (ids.isEmpty) return;
    await _box.deleteAll([
      for (final id in ids) ...['$_codePrefix$id', '$_prefsPrefix$id'],
    ]);
    await _dropUpdates(ids);
    final disabled = disabledIds();
    if (disabled.any(ids.contains)) {
      await _saveDisabled(disabled..removeAll(ids));
    }
  }

  /// Re-fetches every installed repo index and records which installed
  /// sources have a newer build, without applying them.
  ///
  /// Sources that left their index are retired and new, non-excluded ones are
  /// installed. A repo that cannot be fetched keeps its previous snapshot and
  /// is reported in [MangayomiUpdateCheck.failures].
  Future<MangayomiUpdateCheck> checkUpdates() async {
    final failures = <String, String>{};
    var added = 0;
    for (final repo in repos()) {
      try {
        added += await _refresh(await fetchIndex(repo));
      } catch (e) {
        failures[repo] = '$e';
      }
    }
    return MangayomiUpdateCheck(
      updates: availableUpdates(),
      failures: failures,
      added: added,
    );
  }

  Future<int> _refresh(MangayomiRepoIndex index) async {
    final url = index.url;
    final existing = sources();
    final byId = {for (final s in existing) s.id: s};
    final latest = {for (final s in index.sources) s.id: s};
    final excluded = excludedIds(url);
    final updates = _readUpdates();
    final retired = <String>[];
    var added = 0;

    for (final s in existing.where((s) => s.repoUrl == url)) {
      final next = latest[s.id];
      if (next == null) {
        byId.remove(s.id);
        retired.add(s.id);
      } else if (next.runtimeIdentity != s.runtimeIdentity) {
        updates[s.id] = next;
      } else {
        updates.remove(s.id);
      }
    }
    for (final s in index.sources) {
      if (byId.containsKey(s.id) || excluded.contains(s.id)) continue;
      byId[s.id] = s;
      added++;
    }

    await _saveSources(byId.values.toList());
    await _saveUpdates(updates);
    await _forget(retired);
    return added;
  }

  // --- updates -------------------------------------------------------------

  /// Newer builds found by [checkUpdates] that the user has not applied yet.
  Map<String, MangayomiSource> availableUpdates() {
    final out = <String, MangayomiSource>{};
    _readSources();
    for (final entry in _readUpdates().entries) {
      final installed = _sourcesById[entry.key];
      if (installed == null || installed.repoUrl != entry.value.repoUrl) {
        continue;
      }
      if (installed.runtimeIdentity == entry.value.runtimeIdentity) continue;
      out[entry.key] = entry.value;
    }
    return out;
  }

  /// Applies the pending updates for [ids], or all of them when null.
  /// Returns the ids that were updated.
  Future<List<String>> applyUpdates([Iterable<String>? ids]) async {
    final pending = availableUpdates();
    final wanted = ids?.toSet() ?? pending.keys.toSet();
    final byId = {for (final s in sources()) s.id: s};
    final applied = <String>[];
    for (final id in wanted) {
      final next = pending[id];
      if (next == null) continue;
      byId[id] = next;
      applied.add(id);
      await _box.delete('$_codePrefix$id');
    }
    if (applied.isEmpty) return applied;
    await _saveSources(byId.values.toList());
    await _dropUpdates(applied);
    return applied;
  }

  Map<String, MangayomiSource> _readUpdates() {
    final raw = _box.get(_updatesKey);
    if (raw is! String || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return {};
      return {
        for (final e in decoded.whereType<Map>())
          e['id'].toString(): MangayomiSource.fromJson(
            Map<String, dynamic>.from(e),
          ),
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveUpdates(Map<String, MangayomiSource> updates) => _box.put(
    _updatesKey,
    jsonEncode(updates.values.map((e) => e.toJson()).toList()),
  );

  Future<void> _dropUpdates(Iterable<String> ids) async {
    final updates = _readUpdates();
    final before = updates.length;
    for (final id in ids) {
      updates.remove(id);
    }
    if (updates.length != before) await _saveUpdates(updates);
  }

  // --- exclusions ----------------------------------------------------------

  /// Ids from [repoUrl] the user removed or chose not to install.
  Set<String> excludedIds(String repoUrl) =>
      (_readExcluded()[repoUrl] ?? const <String>{}).toSet();

  Map<String, Set<String>> _readExcluded() {
    final raw = _box.get(_excludedKey);
    if (raw is! String || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return {
        for (final e in decoded.entries)
          if (e.value is List)
            e.key.toString(): (e.value as List).map((v) => '$v').toSet(),
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> _setExcluded(String repoUrl, Set<String> ids) async {
    final all = _readExcluded();
    if (ids.isEmpty) {
      if (all.remove(repoUrl) == null) return;
    } else {
      all[repoUrl] = ids;
    }
    await _box.put(
      _excludedKey,
      jsonEncode({for (final e in all.entries) e.key: e.value.toList()}),
    );
  }

  // --- enabled / disabled --------------------------------------------------

  /// Installed sources the user switched off. They stay installed, with their
  /// settings, but are left out of the provider list.
  Set<String> disabledIds() {
    final raw = _box.get(_disabledKey);
    if (raw is! String || raw.isEmpty) return <String>{};
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded.map((e) => '$e').toSet() : <String>{};
    } catch (_) {
      return <String>{};
    }
  }

  bool isEnabled(String id) => !disabledIds().contains(id);

  Future<void> setEnabled(String id, bool enabled) async {
    final disabled = disabledIds();
    final changed = enabled ? disabled.remove(id) : disabled.add(id);
    if (changed) await _saveDisabled(disabled);
  }

  Future<void> _saveDisabled(Set<String> ids) =>
      _box.put(_disabledKey, jsonEncode(ids.toList()));

  /// Installed sources that are switched on.
  List<MangayomiSource> enabledSources() {
    final disabled = disabledIds();
    return sources().where((s) => !disabled.contains(s.id)).toList();
  }

  // --- extension code ------------------------------------------------------

  /// The extension's JavaScript, downloaded once and cached under its version.
  ///
  /// Cached per (id, version) so a repo bump invalidates it automatically —
  /// keying on id alone would pin the first version forever, which is exactly
  /// the bug the APK hosts had. An official LNReader plugin the app carries a
  /// fixed build of runs that instead; see [LnReaderPatches].
  Future<String> code(MangayomiSource source) async {
    final patch = LnReaderPatches.forSource(source);
    if (patch != null) return _loadAsset(patch.asset);
    final key = '$_codePrefix${source.id}';
    final cached = _box.get(key);
    if (cached is Map && cached['identity'] == source.runtimeIdentity) {
      final js = cached['code'];
      if (js is String && js.isNotEmpty) return js;
    }
    final identity = '${source.id}\u0000${source.runtimeIdentity}';
    return _codeRequests.putIfAbsent(identity, () async {
      try {
        return await _downloadCode(source, key);
      } finally {
        _codeRequests.remove(identity);
      }
    });
  }

  Future<String> _downloadCode(MangayomiSource source, String key) async {
    final resp = await _net.get<String>(source.sourceCodeUrl);
    final body = resp.data ?? '';
    if (resp.statusCode == null ||
        resp.statusCode! < 200 ||
        resp.statusCode! >= 300 ||
        body.isEmpty) {
      throw Exception(
        'Could not download ${source.name} (HTTP ${resp.statusCode})',
      );
    }
    await _box.put(key, {'identity': source.runtimeIdentity, 'code': body});
    return body;
  }

  Future<void> clearCode(String sourceId) =>
      _box.delete('$_codePrefix$sourceId');

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

/// A parsed repository index. Only JavaScript sources are kept; the Dart ones
/// are counted in [skippedDart].
class MangayomiRepoIndex {
  const MangayomiRepoIndex({
    required this.url,
    required this.sources,
    this.skippedDart = 0,
  });

  final String url;
  final List<MangayomiSource> sources;
  final int skippedDart;
}

class MangayomiUpdateCheck {
  const MangayomiUpdateCheck({
    required this.updates,
    this.failures = const {},
    this.added = 0,
  });

  /// Newer builds keyed by source id.
  final Map<String, MangayomiSource> updates;

  /// Repo url to error, for indexes that could not be fetched.
  final Map<String, String> failures;

  /// New sources that appeared in an index and were installed.
  final int added;
}
