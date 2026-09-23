// Sources live in Android's own storage, not in Hive, so a backup of the
// boxes alone brought back everything except the sources. These are the rules
// for carrying them.
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/profile/data/extension_backup.dart';

class _FakeHost extends ExtensionHost {
  _FakeHost(
    this.id, {
    List<String>? repos,
    Map<String, String>? sources,
    Map<String, List<String>>? plugins,
    this.catalog = const {},
    this.prefs = const {},
    this.unreachable = const {},
  }) : _repos = repos ?? [],
       _sources = sources ?? {},
       _plugins = plugins ?? {};

  @override
  final String id;
  @override
  bool get supported => true;

  final List<String> _repos;
  final Map<String, String> _sources;
  final Map<String, List<String>> _plugins;

  /// What each repo would install: repo → {sourceId: name}.
  final Map<String, Map<String, String>> catalog;
  final Map<String, List<Map<String, dynamic>>> prefs;
  final Set<String> unreachable;
  final List<(String, String, Object?)> written = [];

  @override
  Future<List<String>> repos() async => [..._repos];
  @override
  Future<Map<String, String>> sources() async => {..._sources};
  @override
  Future<Map<String, List<String>>> plugins() async => {
    for (final e in _plugins.entries) e.key: [...e.value],
  };

  @override
  Future<bool> addRepo(String url) async {
    if (unreachable.contains(url)) return false;
    _repos.add(url);
    _sources.addAll(catalog[url] ?? const {});
    return true;
  }

  @override
  Future<bool> installPlugin(String repo, String name) async {
    if (unreachable.contains(repo)) return false;
    if (!_repos.contains(repo)) _repos.add(repo);
    (_plugins[repo] ??= []).add(name);
    _sources['cs:$name'] = name;
    return true;
  }

  @override
  Future<List<Map<String, dynamic>>> preferences(String source) async =>
      prefs[source] ?? const [];

  @override
  Future<void> setPreference(
    String source,
    String key,
    Object? value,
    String type,
  ) async => written.add((source, key, value));
}

void main() {
  test(
    'export carries repos, sources, chosen plugins and safe settings',
    () async {
      final host = _FakeHost(
        'manga',
        repos: ['https://repo.test/index.json'],
        sources: {'mn:1': 'MangaDex'},
        prefs: {
          'mn:1': [
            {'key': 'quality', 'type': 'list', 'value': 'data-saver'},
            {'key': 'password', 'type': 'text', 'value': 'hunter2'},
            {'key': 'about', 'type': 'info', 'value': null},
          ],
        },
      );
      final data = await ExtensionBackup(hosts: [host]).export();
      final manga = data['manga'] as Map;
      expect(manga['repos'], ['https://repo.test/index.json']);
      expect(manga['sources'], {'mn:1': 'MangaDex'});
      expect(
        manga['preferences'],
        {
          'mn:1': [
            {'key': 'quality', 'type': 'list', 'value': 'data-saver'},
          ],
        },
        reason: 'a credential never goes into a file sent through a messenger',
      );
    },
  );

  test('an empty system is left out of the file', () async {
    final data = await ExtensionBackup(hosts: [_FakeHost('aniyomi')]).export();
    expect(data, isEmpty);
  });

  test('restore adds missing repos and names what did not come back', () async {
    final host = _FakeHost(
      'manga',
      catalog: {
        'https://a.test': {'mn:1': 'MangaDex'},
      },
      unreachable: {'https://gone.test'},
    );
    final report = await ExtensionBackup(hosts: [host]).restore({
      'manga': {
        'repos': ['https://a.test', 'https://gone.test'],
        'sources': {'mn:1': 'MangaDex', 'mn:2': 'Old Source'},
        'preferences': {
          'mn:1': [
            {'key': 'quality', 'type': 'list', 'value': 'data-saver'},
          ],
          'mn:2': [
            {'key': 'x', 'type': 'switch', 'value': true},
          ],
        },
      },
    });
    expect(report.reposAdded, 1);
    expect(report.failedRepos, ['https://gone.test']);
    expect(report.missingSources, ['Old Source']);
    expect(report.preferencesRestored, 1);
    expect(host.written.single, ('mn:1', 'quality', 'data-saver'));
    expect(report.complete, isFalse);
  });

  test('CloudStream comes back plugin by plugin, not the whole repo', () async {
    final host = _FakeHost(
      'cloudstream',
      repos: ['https://cs.test'],
      plugins: {
        'https://cs.test': ['Kept'],
      },
      sources: {'cs:Kept': 'Kept'},
    );
    final report = await ExtensionBackup(hosts: [host]).restore({
      'cloudstream': {
        'repos': ['https://cs.test'],
        'plugins': {
          'https://cs.test': ['Kept', 'Second'],
        },
        'sources': {'cs:Kept': 'Kept', 'cs:Second': 'Second'},
      },
    });
    expect(report.pluginsInstalled, 1, reason: 'Kept was already there');
    expect(report.reposAdded, 0);
    expect(report.complete, isTrue);
  });

  test('a restore onto a device already set up changes nothing', () async {
    final host = _FakeHost(
      'aniyomi',
      repos: ['https://a.test'],
      sources: {'an:1': 'One'},
    );
    final report = await ExtensionBackup(hosts: [host]).restore({
      'aniyomi': {
        'repos': ['https://a.test'],
        'sources': {'an:1': 'One'},
      },
    });
    expect(report.reposAdded, 0);
    expect(report.complete, isTrue);
  });
}
