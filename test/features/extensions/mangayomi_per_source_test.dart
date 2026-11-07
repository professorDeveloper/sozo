// Per-source install, removal, updates and enable/disable, against temporary
// Hive and a loopback repository fixture.
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/js/dart_fetch.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/extensions/data/mangayomi_bridge.dart';
import 'package:soplay/features/extensions/data/mangayomi_repo_store.dart';
import 'package:soplay/features/extensions/data/mangayomi_runtime.dart';
import 'package:soplay/features/extensions/data/source_installer.dart';
import 'package:soplay/features/extensions/domain/entities/catalog_source_entity.dart';
import 'package:soplay/features/extensions/domain/entities/extension_repo_entity.dart';
import 'package:soplay/features/extensions/domain/entities/mangayomi_source.dart';
import 'package:soplay/features/extensions/domain/mangayomi_source_filter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null; // Test-only loopback fixture transport.
  late Directory dir;
  late HttpServer server;
  late String base;
  late MangayomiRepoStore store;
  final responses = <String, Object>{};

  Map<String, Object> source(
    String id, {
    String version = '1.0.0',
    String lang = 'en',
    int type = 0,
  }) => {
    'id': id,
    'name': id,
    'lang': lang,
    'baseUrl': 'https://fixture.example',
    'sourceCodeUrl': '$base/$id.js',
    'version': version,
    'itemType': type,
    'sourceCodeLanguage': 1,
  };

  Set<String> ids() => store.sources().map((s) => s.id).toSet();

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sozo-mangayomi-per-source-');
    Hive.init(dir.path);
    await Hive.openBox(AppConstants.authBox);
    await Hive.openBox(AppConstants.settingsBox);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    responses.clear();
    server.listen((request) async {
      final result = responses[request.uri.path];
      if (result == null) {
        request.response.statusCode = 404;
      } else {
        request.response.write(result is String ? result : jsonEncode(result));
      }
      await request.response.close();
    });
    store = MangayomiRepoStore(dio: Dio());
  });

  tearDown(() async {
    await server.close(force: true);
    if (getIt.isRegistered<HiveService>()) {
      await getIt.unregister<HiveService>();
    }
    await Hive.close();
    await dir.delete(recursive: true);
  });

  group('per-source removal', () {
    test('a removed source stays removed across refreshes', () async {
      responses['/repo.json'] = [source('a'), source('b'), source('c')];
      await store.addRepo('$base/repo.json');
      await store.savePrefs('b', {'domain': 'x'});
      await Hive.box(
        AppConstants.settingsBox,
      ).put('mangayomi_code:b', {'identity': 'x', 'code': 'js'});

      await store.removeSource('my:b');

      expect(ids(), {'a', 'c'});
      expect(store.prefs('b'), isEmpty);
      expect(Hive.box(AppConstants.settingsBox).get('mangayomi_code:b'), isNull);
      expect(store.excludedIds('$base/repo.json'), {'b'});

      responses['/repo.json'] = [
        source('a'),
        source('b', version: '2.0.0'),
        source('c'),
        source('d'),
      ];
      final check = await store.checkUpdates();
      expect(ids(), {'a', 'c', 'd'});
      expect(check.added, 1);
      expect(check.updates, isEmpty);
    });

    test('picking a removed source again lifts its exclusion', () async {
      responses['/repo.json'] = [source('a'), source('b')];
      await store.addRepo('$base/repo.json');
      await store.removeSource('b');
      final index = await store.fetchIndex('$base/repo.json');
      await store.installSources(index, {'b'});
      expect(ids(), {'a', 'b'});
      expect(store.excludedIds('$base/repo.json'), isEmpty);
      await store.checkUpdates();
      expect(ids(), {'a', 'b'});
    });

    test('removing a repo clears its code, prefs and exclusions', () async {
      responses['/repo.json'] = [source('a'), source('b')];
      await store.addRepo('$base/repo.json');
      await store.removeSource('b');
      await store.savePrefs('a', {'k': 1});
      await store.setEnabled('a', false);
      await Hive.box(
        AppConstants.settingsBox,
      ).put('mangayomi_code:a', {'identity': 'x', 'code': 'js'});

      await store.removeRepo('$base/repo.json');

      expect(store.sources(), isEmpty);
      expect(store.repos(), isEmpty);
      expect(store.prefs('a'), isEmpty);
      expect(Hive.box(AppConstants.settingsBox).get('mangayomi_code:a'), isNull);
      expect(store.disabledIds(), isEmpty);
      expect(store.excludedIds('$base/repo.json'), isEmpty);
    });
  });

  group('choosing sources', () {
    test('only the chosen sources are installed, the rest excluded', () async {
      responses['/repo.json'] = [source('a'), source('b'), source('c')];
      final index = await store.fetchIndex('$base/repo.json');
      final res = await store.installSources(index, {'b'});
      expect(res['added'], 1);
      expect(ids(), {'b'});
      expect(store.repos(), ['$base/repo.json']);

      await store.checkUpdates();
      expect(ids(), {'b'});

      await store.installSources(index, {'a'});
      expect(ids(), {'a', 'b'});
      expect(store.excludedIds('$base/repo.json'), {'c'});
    });

    test('addRepo still installs everything, excluded or not', () async {
      responses['/repo.json'] = [source('a'), source('b')];
      final index = await store.fetchIndex('$base/repo.json');
      await store.installSources(index, {'a'});
      await store.addRepo('$base/repo.json');
      expect(ids(), {'a', 'b'});
      expect(store.excludedIds('$base/repo.json'), isEmpty);
    });

    test('a catalog row installs only its own source', () async {
      responses['/repo.json'] = [source('a'), source('b'), source('c')];
      final count = await installCatalogSource(
        CatalogSourceEntity(
          id: 'db',
          externalId: 'b',
          kind: ExtensionRepoKind.mangayomi,
          name: 'b',
          repoUrl: '$base/repo.json',
        ),
        store,
      );
      expect(count, 1);
      expect(ids(), {'b'});
    });

    test('a catalog row missing from its index is an error', () async {
      responses['/repo.json'] = [source('a')];
      await expectLater(
        installCatalogSource(
          CatalogSourceEntity(
            id: 'db',
            externalId: 'gone',
            kind: ExtensionRepoKind.mangayomi,
            name: 'gone',
            repoUrl: '$base/repo.json',
          ),
          store,
        ),
        throwsStateError,
      );
      expect(store.sources(), isEmpty);
    });

    test('LNReader catalog ids match their prefixed install id', () {
      expect(mangayomiCatalogMatch('ln.royalroad', 'royalroad'), isTrue);
      expect(mangayomiCatalogMatch('royalroad', 'royalroad'), isTrue);
      expect(mangayomiCatalogMatch('ln.royalroad', 'other'), isFalse);
    });
  });

  group('updates', () {
    test('checkUpdates reports newer builds without applying them', () async {
      responses['/repo.json'] = [source('a'), source('b')];
      await store.addRepo('$base/repo.json');
      await Hive.box(AppConstants.settingsBox).put('mangayomi_code:a', {
        'identity': store.sourceById('a')!.runtimeIdentity,
        'code': 'old',
      });
      responses['/repo.json'] = [source('a', version: '1.1.0'), source('b')];

      final check = await store.checkUpdates();

      expect(check.updates.keys, ['a']);
      expect(check.updates['a']!.version, '1.1.0');
      expect(store.sourceById('a')!.version, '1.0.0');
      expect(
        Hive.box(AppConstants.settingsBox).get('mangayomi_code:a'),
        isNotNull,
      );
      expect(store.availableUpdates().keys, ['a']);

      final applied = await store.applyUpdates(['a']);
      expect(applied, ['a']);
      expect(store.sourceById('a')!.version, '1.1.0');
      expect(store.availableUpdates(), isEmpty);
      expect(Hive.box(AppConstants.settingsBox).get('mangayomi_code:a'), isNull);
    });

    test('update all applies every pending update', () async {
      responses['/repo.json'] = [source('a'), source('b')];
      await store.addRepo('$base/repo.json');
      responses['/repo.json'] = [
        source('a', version: '2.0.0'),
        source('b', version: '2.0.0'),
      ];
      await store.checkUpdates();
      final applied = await store.applyUpdates();
      expect(applied.toSet(), {'a', 'b'});
      expect(store.sources().every((s) => s.version == '2.0.0'), isTrue);
    });

    test('a failed repo is reported, the others still checked', () async {
      responses['/good.json'] = [source('a')];
      responses['/bad.json'] = [source('b')];
      await store.addRepo('$base/good.json');
      await store.addRepo('$base/bad.json');
      responses.remove('/bad.json');
      responses['/good.json'] = [source('a', version: '1.2.0')];

      final check = await store.checkUpdates();

      expect(check.failures.keys, ['$base/bad.json']);
      expect(check.updates.keys, ['a']);
      expect(store.sourceById('b'), isNotNull);
    });

    test('removing a source drops its pending update', () async {
      responses['/repo.json'] = [source('a')];
      await store.addRepo('$base/repo.json');
      responses['/repo.json'] = [source('a', version: '2.0.0')];
      await store.checkUpdates();
      await store.removeSource('a');
      expect(store.availableUpdates(), isEmpty);
    });
  });

  group('enable and disable', () {
    test('a disabled source is hidden from listProviders', () async {
      getIt.registerSingleton<HiveService>(HiveService());
      responses['/repo.json'] = [source('a'), source('b')];
      await store.addRepo('$base/repo.json');
      final bridge = MangayomiBridge(
        runtime: MangayomiRuntime(store: store, dartFetch: DartFetch.create()),
        store: store,
      );
      List<String> listed() => bridge
          .listProviders()
          .map((p) => p['id'] as String)
          .toList()
        ..sort();

      expect(listed(), ['my:a', 'my:b']);
      await store.setEnabled('a', false);
      expect(store.isEnabled('a'), isFalse);
      expect(listed(), ['my:b']);
      expect(store.sourceById('a'), isNotNull);
      expect(ids(), {'a', 'b'});

      await store.setEnabled('a', true);
      expect(listed(), ['my:a', 'my:b']);
    });

    test('disabled state survives a refresh', () async {
      responses['/repo.json'] = [source('a')];
      await store.addRepo('$base/repo.json');
      await store.setEnabled('a', false);
      await store.checkUpdates();
      expect(store.enabledSources(), isEmpty);
      expect(ids(), {'a'});
    });
  });

  group('filter', () {
    MangayomiSource s(String name, String lang, MangayomiItemType type) =>
        MangayomiSource(
          id: '$name-$lang',
          name: name,
          baseUrl: 'https://$name.example',
          lang: lang,
          sourceCodeUrl: 'x',
          version: '1',
          itemType: type,
        );

    final all = [
      s('Zeta', 'fr', MangayomiItemType.anime),
      s('Alpha', 'en', MangayomiItemType.manga),
      s('Beta', 'all', MangayomiItemType.manga),
      s('alpha', 'fr', MangayomiItemType.novel),
    ];

    test('sorts by name then language', () {
      expect(
        const MangayomiSourceFilter().apply(all).map((e) => e.id),
        ['Alpha-en', 'alpha-fr', 'Beta-all', 'Zeta-fr'],
      );
    });

    test('type, language and query narrow the list', () {
      expect(
        const MangayomiSourceFilter(
          type: MangayomiItemType.manga,
        ).apply(all).map((e) => e.id),
        ['Alpha-en', 'Beta-all'],
      );
      expect(
        const MangayomiSourceFilter(languages: ['fr']).apply(all).map((e) => e.id),
        ['alpha-fr', 'Beta-all', 'Zeta-fr'],
      );
      expect(
        const MangayomiSourceFilter(query: 'zet').apply(all).map((e) => e.id),
        ['Zeta-fr'],
      );
    });

    test('language counts and toggling', () {
      expect(MangayomiSourceFilter.languageCounts(all), {
        'fr': 2,
        'en': 1,
        'all': 1,
      });
      expect(MangayomiSourceFilter.toggleLanguage(const [], 'fr'), ['fr']);
      expect(MangayomiSourceFilter.toggleLanguage(const ['fr'], 'fr'), isEmpty);
      expect(MangayomiSourceFilter.toggleLanguage(const ['fr'], 'all'), isEmpty);
    });
  });
}
