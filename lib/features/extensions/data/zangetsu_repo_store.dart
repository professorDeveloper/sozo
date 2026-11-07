import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/js/extractor_cache.dart';
import 'package:soplay/features/extensions/domain/entities/zangetsu_source.dart';
import 'package:soplay/features/profile/data/models/provider_model.dart';
import 'package:soplay/features/profile/domain/entities/provider_entity.dart';
import 'package:soplay/features/sources/domain/source_scope.dart';

enum ZangetsuRepoError { invalidUrl, unreachable, invalidIndex }

class ZangetsuRepoException implements Exception {
  const ZangetsuRepoException(this.error, [this.detail]);

  final ZangetsuRepoError error;
  final String? detail;

  @override
  String toString() => detail == null ? error.name : '${error.name}: $detail';
}

/// External Zangetsu repos and the sources installed from them.
///
/// The backend reads the repo's `index.json` and composes each source into a
/// device bundle (`/extractors/zangetsu-ext`); the device only keeps which
/// repos were added, their last manifest, and which sources are installed.
class ZangetsuRepoStore {
  ZangetsuRepoStore({required this.dio, required this.cache});

  final Dio dio;
  final ExtractorCache cache;

  static const allowedHosts = {
    'raw.githubusercontent.com',
    'gist.githubusercontent.com',
  };
  static const externalPrefix = 'zx-';

  static const _reposKey = 'zangetsu_repos';
  static const _installedKey = 'zangetsu_installed';
  static const _manifestPrefix = 'zangetsu_manifest:';

  Box get _box => Hive.box(AppConstants.settingsBox);

  static bool isAllowedUrl(String raw) {
    final uri = Uri.tryParse(raw.trim());
    return uri != null &&
        uri.scheme == 'https' &&
        allowedHosts.contains(uri.host.toLowerCase()) &&
        uri.userInfo.isEmpty &&
        uri.pathSegments.where((s) => s.isNotEmpty).isNotEmpty;
  }

  static bool isExternalId(String id) => id.startsWith(externalPrefix);

  /// A source's version string as the int extractor caches key on:
  /// `1.0.3` → 10003. Never below 1, which the caches treat as "unknown".
  static int versionCode(String version) {
    final parts = RegExp(r'\d+')
        .allMatches(version)
        .take(3)
        .map((m) => int.tryParse(m.group(0)!) ?? 0)
        .toList();
    while (parts.length < 3) {
      parts.add(0);
    }
    final code =
        parts[0].clamp(0, 99999) * 10000 +
        parts[1].clamp(0, 99) * 100 +
        parts[2].clamp(0, 99);
    return code < 1 ? 1 : code;
  }

  // --- repos ---------------------------------------------------------------

  List<String> repos() => _readList(_reposKey).whereType<String>().toList();

  /// The repo's sources as last fetched, adult ones included.
  List<ZangetsuSource> manifest(String repoUrl) =>
      _decodeSources(_readList('$_manifestPrefix${repoUrl.trim()}'));

  /// Adds [url] (or refreshes it) and returns its sources.
  Future<List<ZangetsuSource>> addRepo(String url) async {
    final repo = url.trim();
    if (!isAllowedUrl(repo)) {
      throw const ZangetsuRepoException(ZangetsuRepoError.invalidUrl);
    }
    final sources = await _fetch(repo);
    await _box.put(
      '$_manifestPrefix$repo',
      jsonEncode(sources.map((s) => s.toJson()).toList()),
    );
    final list = repos();
    if (!list.contains(repo)) {
      await _box.put(_reposKey, jsonEncode([...list, repo]));
    }
    // A source Sozo starts shipping stops registering from the repo.
    final byId = {for (final s in sources) s.providerId: s};
    var changed = false;
    final installed = this.installed().map((s) {
      final fresh = s.repoUrl == repo ? byId[s.providerId] : null;
      if (fresh == null || fresh.builtIn == s.builtIn) return s;
      changed = true;
      return s.copyWith(builtIn: fresh.builtIn);
    }).toList();
    if (changed) await _saveInstalled(installed);
    return sources;
  }

  Future<void> removeRepo(String url) async {
    final repo = url.trim();
    final all = installed();
    for (final s in all.where((s) => s.repoUrl == repo)) {
      await _clearCode(s.providerId);
    }
    await _saveInstalled(all.where((s) => s.repoUrl != repo).toList());
    await _box.delete('$_manifestPrefix$repo');
    await _box.put(
      _reposKey,
      jsonEncode(repos().where((r) => r != repo).toList()),
    );
  }

  /// Re-reads every repo. One that fails keeps its last manifest.
  Future<void> refreshAll() async {
    for (final repo in repos()) {
      try {
        await addRepo(repo);
      } catch (_) {}
    }
  }

  Future<List<ZangetsuSource>> _fetch(String repo) async {
    final Response<dynamic> resp;
    try {
      resp = await dio.get<dynamic>(
        '/extension-repos/zangetsu',
        queryParameters: {'url': repo},
      );
    } on DioException catch (e) {
      final data = e.response?.data;
      final code = data is Map ? data['code'] : null;
      final message = data is Map ? data['message']?.toString() : null;
      throw ZangetsuRepoException(switch (code) {
        'REPO_URL_INVALID' => ZangetsuRepoError.invalidUrl,
        'REPO_INDEX_INVALID' => ZangetsuRepoError.invalidIndex,
        _ => ZangetsuRepoError.unreachable,
      }, message ?? e.message);
    }
    final data = resp.data is String ? _tryDecode(resp.data) : resp.data;
    final raw = data is Map ? data['sources'] : null;
    if (raw is! List) {
      throw const ZangetsuRepoException(ZangetsuRepoError.invalidIndex);
    }
    return [
      for (final e in raw.whereType<Map>())
        ?ZangetsuSource.fromJson(Map<String, dynamic>.from(e), repoUrl: repo),
    ];
  }

  // --- installed sources ---------------------------------------------------

  List<ZangetsuSource> installed() => _decodeSources(_readList(_installedKey));

  ZangetsuSource? installedById(String providerId) {
    for (final s in installed()) {
      if (s.providerId == providerId) return s;
    }
    return null;
  }

  Future<void> install(ZangetsuSource source) async {
    if (source.builtIn) return;
    final current = installedById(source.providerId);
    final kept = installed()
        .where((s) => s.providerId != source.providerId)
        .toList();
    await _saveInstalled([
      ...kept,
      source.copyWith(enabled: current?.enabled ?? true),
    ]);
  }

  Future<void> remove(String providerId) async {
    await _clearCode(providerId);
    await _saveInstalled(
      installed().where((s) => s.providerId != providerId).toList(),
    );
  }

  Future<void> setEnabled(String providerId, bool enabled) async {
    await _saveInstalled([
      for (final s in installed())
        s.providerId == providerId ? s.copyWith(enabled: enabled) : s,
    ]);
  }

  /// The manifest entry that would replace [source], when its version differs.
  ZangetsuSource? updateFor(ZangetsuSource source) {
    for (final m in manifest(source.repoUrl)) {
      if (m.providerId != source.providerId) continue;
      return m.version != source.version || m.file != source.file ? m : null;
    }
    return null;
  }

  List<ZangetsuSource> updates() => [
    for (final s in installed())
      if (updateFor(s) != null) s,
  ];

  /// Moves [providerId] to its repo's current version.
  Future<bool> update(String providerId) async {
    final current = installedById(providerId);
    final next = current == null ? null : updateFor(current);
    if (current == null || next == null) return false;
    await _clearCode(providerId);
    await install(next.copyWith(enabled: current.enabled));
    return true;
  }

  Future<int> updateAll() async {
    var count = 0;
    for (final s in updates()) {
      if (await update(s.providerId)) count++;
    }
    return count;
  }

  // --- providers -----------------------------------------------------------

  /// Installed, enabled sources as providers run on the device.
  List<ProviderModel> providers({required bool allowAdult}) => [
    for (final s in installed())
      if (s.enabled && !s.builtIn && (allowAdult || !s.nsfw)) toProvider(s),
  ];

  ProviderModel? providerById(String id, {required bool allowAdult}) {
    if (!isExternalId(id)) return null;
    for (final p in providers(allowAdult: allowAdult)) {
      if (p.id == id) return p;
    }
    return null;
  }

  static ProviderModel toProvider(ZangetsuSource s) {
    final url =
        '/extractors/zangetsu-ext?src=${Uri.encodeQueryComponent(s.file)}'
        '&id=${Uri.encodeQueryComponent(s.providerId)}'
        '${s.isLive ? '&live=1' : ''}';
    return ProviderModel(
      id: s.providerId,
      name: s.name,
      image: s.icon ?? '',
      url: '',
      description: 'Zangetsu · ${repoLabel(s.repoUrl)}',
      repo: s.repoUrl,
      domains: const [],
      mode: 'client',
      category: s.isAnime ? 'anime' : 'movies',
      lang: s.lang,
      nsfw: s.nsfw,
      extractor: ExtractorRef(
        name: s.providerId,
        version: versionCode(s.version),
        scope: 'all',
        url: url,
      ),
    );
  }

  /// [builtIn] plus the [external] ones whose id is not taken. Sozo's own
  /// providers always win, under either the `zx-` id or the plain one.
  static List<ProviderEntity> merge(
    List<ProviderEntity> builtIn,
    List<ProviderEntity> external,
  ) {
    final taken = {for (final p in builtIn) p.id};
    return [
      ...builtIn,
      for (final p in external)
        if (!taken.contains(p.id) &&
            !(isExternalId(p.id) &&
                taken.contains(p.id.substring(externalPrefix.length))))
          p,
    ];
  }

  // --- storage -------------------------------------------------------------

  Future<void> _clearCode(String providerId) => cache.clear(providerId);

  Future<void> _saveInstalled(List<ZangetsuSource> list) => _box.put(
    _installedKey,
    jsonEncode(list.map((s) => s.toJson()).toList()),
  );

  List<dynamic> _readList(String key) {
    final raw = _box.get(key);
    if (raw is! String || raw.isEmpty) return const [];
    final decoded = _tryDecode(raw);
    return decoded is List ? decoded : const [];
  }

  static Object? _tryDecode(Object? raw) {
    if (raw is! String) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  static List<ZangetsuSource> _decodeSources(List<dynamic> raw) => [
    for (final e in raw.whereType<Map>())
      ?ZangetsuSource.fromJson(Map<String, dynamic>.from(e)),
  ];
}
