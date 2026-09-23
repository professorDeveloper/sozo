import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:soplay/core/aniyomi/aniyomi_channel.dart';
import 'package:soplay/core/cloudstream/cloudstream_channel.dart';
import 'package:soplay/core/manga/manga_channel.dart';

/// One native extension system, as a backup sees it.
///
/// CloudStream, Aniyomi and Mihon keep their repos and installed sources in
/// Android's own storage, not in Hive, so a backup made of Hive boxes alone
/// restored everything except the thing that takes longest to set up again:
/// the sources. This is the narrow surface a backup needs from each of them,
/// and what a test stands in for.
abstract class ExtensionHost {
  /// `cloudstream`, `aniyomi` or `manga` — the key in the backup file.
  String get id;

  bool get supported;

  Future<List<String>> repos();

  /// Installed sources, id to display name.
  Future<Map<String, String>> sources();

  /// Installed plugins per repo, for a host that installs one at a time. An
  /// empty map for one that installs a repo whole.
  Future<Map<String, List<String>>> plugins() async => const {};

  Future<bool> addRepo(String url);

  Future<bool> installPlugin(String repo, String name) async => false;

  /// A source's settings, `[{key, type, value}]`, for a host that has them.
  Future<List<Map<String, dynamic>>> preferences(String source) async =>
      const [];

  Future<void> setPreference(
    String source,
    String key,
    Object? value,
    String type,
  ) async {}
}

/// What restoring the extensions did — and, more to the point, what it could
/// not do, by name.
class ExtensionRestoreReport {
  const ExtensionRestoreReport({
    this.reposAdded = 0,
    this.pluginsInstalled = 0,
    this.preferencesRestored = 0,
    this.failedRepos = const [],
    this.missingSources = const [],
  });

  final int reposAdded;
  final int pluginsInstalled;
  final int preferencesRestored;

  /// Repos that could not be added: gone, moved, or unreachable just now.
  final List<String> failedRepos;

  /// Sources the backup had that this device still does not, by name.
  final List<String> missingSources;

  bool get complete => failedRepos.isEmpty && missingSources.isEmpty;

  static const empty = ExtensionRestoreReport();

  ExtensionRestoreReport operator +(ExtensionRestoreReport o) =>
      ExtensionRestoreReport(
        reposAdded: reposAdded + o.reposAdded,
        pluginsInstalled: pluginsInstalled + o.pluginsInstalled,
        preferencesRestored: preferencesRestored + o.preferencesRestored,
        failedRepos: [...failedRepos, ...o.failedRepos],
        missingSources: [...missingSources, ...o.missingSources],
      );
}

/// Backs up and restores the native extension systems.
///
/// ## What is carried
///
/// Repo urls, which sources were installed (by id and name, so a restore can
/// say which ones did not come back), CloudStream's per-plugin choice — a
/// repo of sixty plugins where somebody kept four should come back as four —
/// and Mihon source settings.
///
/// Not the extension files. They are code for this device's architecture and
/// app version, and the repo is where a current, signed copy lives; carrying
/// a stale APK in a file someone sends through a messenger is worse on both
/// counts.
///
/// Not settings that look like credentials either — the same rule the rest of
/// the backup keeps for the auth box.
class ExtensionBackup {
  ExtensionBackup({List<ExtensionHost>? hosts})
    : _hosts = hosts ?? [_CloudStreamHost(), _AniyomiHost(), _MangaHost()];

  final List<ExtensionHost> _hosts;

  static const String _tag = '[backup:ext]';

  /// A setting whose key reads like a secret stays on the device.
  static final RegExp _secret = RegExp(
    r'pass|token|cookie|secret|session|auth|api.?key',
    caseSensitive: false,
  );

  /// Longest a single source may take to answer for its settings. Loading a
  /// source to ask it is not free, and one that hangs must not hold up a
  /// backup of everything else.
  static const Duration _perSource = Duration(seconds: 4);

  Future<Map<String, dynamic>> export() async {
    final out = <String, dynamic>{};
    for (final host in _hosts) {
      if (!host.supported) continue;
      try {
        final repos = await host.repos();
        final sources = await host.sources();
        if (repos.isEmpty && sources.isEmpty) continue;
        final plugins = await host.plugins();
        final prefs = <String, dynamic>{};
        for (final id in sources.keys) {
          final list = await host
              .preferences(id)
              .timeout(_perSource, onTimeout: () => const []);
          final kept = [
            for (final p in list)
              if (p['key'] is String &&
                  p['type'] != 'info' &&
                  !_secret.hasMatch(p['key'] as String))
                {'key': p['key'], 'type': p['type'], 'value': p['value']},
          ];
          if (kept.isNotEmpty) prefs[id] = kept;
        }
        out[host.id] = {
          'repos': repos,
          'sources': sources,
          if (plugins.isNotEmpty) 'plugins': plugins,
          if (prefs.isNotEmpty) 'preferences': prefs,
        };
      } catch (e) {
        // One system failing to answer costs the backup that system, not the
        // whole file.
        debugPrint('$_tag export ${host.id}: $e');
      }
    }
    return out;
  }

  /// Counts for the manifest, so a file can say what it holds before anyone
  /// restores it.
  static Map<String, int> count(Map<String, dynamic> data) {
    var repos = 0, sources = 0;
    for (final v in data.values) {
      if (v is! Map) continue;
      repos += (v['repos'] as List?)?.length ?? 0;
      sources += (v['sources'] as Map?)?.length ?? 0;
    }
    return {'repos': repos, 'sources': sources};
  }

  Future<ExtensionRestoreReport> restore(
    Map<String, dynamic> data, {
    void Function(String hostId)? onHost,
  }) async {
    var report = ExtensionRestoreReport.empty;
    for (final host in _hosts) {
      final section = data[host.id];
      if (section is! Map) continue;
      onHost?.call(host.id);
      if (!host.supported) {
        report += ExtensionRestoreReport(
          missingSources: _names(section['sources']).values.toList(),
        );
        continue;
      }
      try {
        report += await _restoreHost(host, section);
      } catch (e) {
        debugPrint('$_tag restore ${host.id}: $e');
        report += ExtensionRestoreReport(
          failedRepos: [
            for (final r in (section['repos'] as List? ?? const [])) '$r',
          ],
        );
      }
    }
    return report;
  }

  Future<ExtensionRestoreReport> _restoreHost(
    ExtensionHost host,
    Map section,
  ) async {
    final wantedRepos = [
      for (final r in (section['repos'] as List? ?? const [])) '$r',
    ];
    final wantedPlugins = <String, List<String>>{
      for (final e in ((section['plugins'] as Map?) ?? const {}).entries)
        '${e.key}': [for (final n in (e.value as List? ?? const [])) '$n'],
    };
    final wantedSources = _names(section['sources']);

    final have = (await host.repos()).toSet();
    var reposAdded = 0, pluginsInstalled = 0;
    final failed = <String>[];

    if (wantedPlugins.isNotEmpty) {
      // Plugin by plugin: exactly what was kept, not the whole repo.
      final installed = await host.plugins();
      for (final entry in wantedPlugins.entries) {
        final already = installed[entry.key]?.toSet() ?? const <String>{};
        var any = already.isNotEmpty;
        for (final name in entry.value) {
          if (already.contains(name)) continue;
          if (await host.installPlugin(entry.key, name)) {
            pluginsInstalled++;
            any = true;
          }
        }
        if (!any && entry.value.isNotEmpty) failed.add(entry.key);
        if (!have.contains(entry.key) && any) reposAdded++;
      }
    }
    for (final repo in wantedRepos) {
      if (have.contains(repo) || wantedPlugins.containsKey(repo)) continue;
      if (await host.addRepo(repo)) {
        reposAdded++;
      } else {
        failed.add(repo);
      }
    }

    final now = await host.sources();
    final missing = [
      for (final e in wantedSources.entries)
        if (!now.containsKey(e.key)) e.value,
    ];

    var prefsRestored = 0;
    final prefs = section['preferences'];
    if (prefs is Map) {
      for (final e in prefs.entries) {
        final id = '${e.key}';
        if (!now.containsKey(id) || e.value is! List) continue;
        for (final p in e.value as List) {
          if (p is! Map || p['key'] is! String || p['type'] is! String) {
            continue;
          }
          try {
            await host.setPreference(
              id,
              p['key'] as String,
              p['value'],
              p['type'] as String,
            );
            prefsRestored++;
          } catch (_) {}
        }
      }
    }

    return ExtensionRestoreReport(
      reposAdded: reposAdded,
      pluginsInstalled: pluginsInstalled,
      preferencesRestored: prefsRestored,
      failedRepos: failed,
      missingSources: missing,
    );
  }

  static Map<String, String> _names(Object? raw) => {
    if (raw is Map)
      for (final e in raw.entries) '${e.key}': '${e.value}',
  };
}

List<String> _repoUrls(List<dynamic> raw) => [
  for (final r in raw)
    if (r is Map && r['url'] != null) '${r['url']}' else if (r is String) r,
];

Map<String, String> _sourceNames(List<dynamic> raw) => {
  for (final p in raw)
    if (p is Map && p['id'] != null) '${p['id']}': '${p['name'] ?? p['id']}',
};

bool _installed(Map<String, dynamic> result) =>
    ((result['pluginCount'] ?? result['count'] ?? 0) as num) > 0 ||
    (result['providers'] is List && (result['providers'] as List).isNotEmpty);

class _CloudStreamHost extends ExtensionHost {
  @override
  String get id => 'cloudstream';
  @override
  bool get supported => CloudStreamChannel.isSupported;
  @override
  Future<List<String>> repos() async =>
      _repoUrls(await CloudStreamChannel.listRepos());
  @override
  Future<Map<String, String>> sources() async =>
      _sourceNames(await CloudStreamChannel.ensureLoaded());
  @override
  Future<Map<String, List<String>>> plugins() async {
    final raw = await CloudStreamChannel.installedPlugins();
    return {
      for (final e in raw.entries)
        e.key: [for (final n in (e.value as List? ?? const [])) '$n'],
    };
  }

  @override
  Future<bool> addRepo(String url) async =>
      _installed(await CloudStreamChannel.addRepo(url));
  @override
  Future<bool> installPlugin(String repo, String name) async =>
      _installed(await CloudStreamChannel.installPlugin(repo, name));
}

class _AniyomiHost extends ExtensionHost {
  @override
  String get id => 'aniyomi';
  @override
  bool get supported => AniyomiChannel.isSupported;
  @override
  Future<List<String>> repos() async =>
      _repoUrls(await AniyomiChannel.listRepos());
  @override
  Future<Map<String, String>> sources() async =>
      _sourceNames(await AniyomiChannel.ensureLoaded());
  @override
  Future<bool> addRepo(String url) async {
    // A failed call comes back as an empty map, not an error.
    final r = await AniyomiChannel.addRepo(url);
    return r.isNotEmpty && r['error'] == null;
  }
}

class _MangaHost extends ExtensionHost {
  @override
  String get id => 'manga';
  @override
  bool get supported => MangaChannel.isSupported;
  @override
  Future<List<String>> repos() async =>
      _repoUrls(await MangaChannel.listRepos());
  @override
  Future<Map<String, String>> sources() async =>
      _sourceNames(await MangaChannel.ensureLoaded());
  @override
  Future<bool> addRepo(String url) async {
    final r = await MangaChannel.addRepo(url);
    return r.isNotEmpty && r['error'] == null;
  }

  @override
  Future<List<Map<String, dynamic>>> preferences(String source) async => [
    for (final p in await MangaChannel.getPreferences(_native(source)))
      if (p is Map) p.cast<String, dynamic>(),
  ];

  @override
  Future<void> setPreference(
    String source,
    String key,
    Object? value,
    String type,
  ) => MangaChannel.setPreference(_native(source), key, value, type);

  /// The channel takes the source's own id; the app lists it with a prefix.
  static String _native(String id) =>
      id.startsWith('mn:') ? id.substring(3) : id;
}
