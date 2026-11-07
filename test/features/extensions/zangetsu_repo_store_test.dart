import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/js/extractor_cache.dart';
import 'package:soplay/features/extensions/data/zangetsu_repo_store.dart';
import 'package:soplay/features/extensions/domain/entities/zangetsu_source.dart';
import 'package:soplay/features/profile/domain/entities/provider_entity.dart';

const repo = 'https://raw.githubusercontent.com/owner/repo/main/index.json';

Map<String, Object?> entry(
  String id, {
  String version = '1.0.0',
  String type = 'movie',
  bool nsfw = false,
  bool builtIn = false,
}) => {
  'id': id,
  'providerId': 'zx-$id',
  'name': id.toUpperCase(),
  'lang': 'en',
  'type': type,
  'version': version,
  'file': 'https://raw.githubusercontent.com/owner/repo/main/providers/$id.js',
  'icon': null,
  'nsfw': nsfw,
  'builtIn': builtIn,
};

ProviderEntity provider(String id) => ProviderEntity(
  id: id,
  name: id,
  image: '',
  url: '',
  description: '',
  domains: const [],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  late Directory dir;
  late HttpServer server;
  late ZangetsuRepoStore store;
  late ExtractorCache cache;
  var status = 200;
  Object body = {};
  final asked = <String>[];

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sozo-zangetsu-');
    Hive.init(dir.path);
    await Hive.openBox(AppConstants.settingsBox);
    await Hive.openBox(AppConstants.extractorsBox);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    status = 200;
    body = {};
    asked.clear();
    server.listen((request) async {
      asked.add(request.uri.queryParameters['url'] ?? '');
      request.response
        ..statusCode = request.uri.path == '/extension-repos/zangetsu'
            ? status
            : 404
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(body));
      await request.response.close();
    });
    cache = ExtractorCache();
    store = ZangetsuRepoStore(
      dio: Dio(BaseOptions(baseUrl: 'http://127.0.0.1:${server.port}')),
      cache: cache,
    );
  });

  tearDown(() async {
    await server.close(force: true);
    await Hive.close();
    await dir.delete(recursive: true);
  });

  void serve(List<Map<String, Object?>> sources) =>
      body = {'url': repo, 'sources': sources};

  group('url validation', () {
    test('only https raw GitHub and gist links pass', () {
      expect(ZangetsuRepoStore.isAllowedUrl(repo), isTrue);
      expect(
        ZangetsuRepoStore.isAllowedUrl(
          'https://gist.githubusercontent.com/u/abc/raw/index.json',
        ),
        isTrue,
      );
      expect(
        ZangetsuRepoStore.isAllowedUrl(
          'http://raw.githubusercontent.com/a/b/index.json',
        ),
        isFalse,
      );
      expect(
        ZangetsuRepoStore.isAllowedUrl('https://evil.example/index.json'),
        isFalse,
      );
      expect(
        ZangetsuRepoStore.isAllowedUrl(
          'https://user:pw@raw.githubusercontent.com/a/b/index.json',
        ),
        isFalse,
      );
      expect(ZangetsuRepoStore.isAllowedUrl('not a url'), isFalse);
      expect(
        ZangetsuRepoStore.isAllowedUrl('https://raw.githubusercontent.com/'),
        isFalse,
      );
    });

    test('a bad url is refused before any request', () async {
      await expectLater(
        store.addRepo('https://evil.example/index.json'),
        throwsA(
          isA<ZangetsuRepoException>().having(
            (e) => e.error,
            'error',
            ZangetsuRepoError.invalidUrl,
          ),
        ),
      );
      expect(asked, isEmpty);
      expect(store.repos(), isEmpty);
    });
  });

  test('version strings become stable ints', () {
    expect(ZangetsuRepoStore.versionCode('1.0.3'), 10003);
    expect(ZangetsuRepoStore.versionCode('2.10.0'), 21000);
    expect(ZangetsuRepoStore.versionCode('1.2'), 10200);
    expect(ZangetsuRepoStore.versionCode('v3'), 30000);
    expect(ZangetsuRepoStore.versionCode('0'), 1);
    expect(ZangetsuRepoStore.versionCode(''), 1);
    expect(
      ZangetsuRepoStore.versionCode('1.0.3'),
      ZangetsuRepoStore.versionCode('1.0.3'),
    );
  });

  group('repos', () {
    test('adding a repo stores it and its manifest', () async {
      serve([entry('alpha'), entry('beta', type: 'anime')]);
      final sources = await store.addRepo(repo);
      expect(asked, [repo]);
      expect(sources.map((s) => s.providerId), ['zx-alpha', 'zx-beta']);
      expect(store.repos(), [repo]);
      expect(store.manifest(repo).length, 2);
      expect(store.manifest(repo).first.repoUrl, repo);

      await store.addRepo(repo);
      expect(store.repos(), [repo]);
    });

    test('an unreachable repo and an invalid index are told apart', () async {
      status = 502;
      body = {'message': 'could not read', 'code': 'REPO_UNREACHABLE'};
      await expectLater(
        store.addRepo(repo),
        throwsA(
          isA<ZangetsuRepoException>().having(
            (e) => e.error,
            'error',
            ZangetsuRepoError.unreachable,
          ),
        ),
      );
      status = 422;
      body = {'message': 'not JSON', 'code': 'REPO_INDEX_INVALID'};
      await expectLater(
        store.addRepo(repo),
        throwsA(
          isA<ZangetsuRepoException>().having(
            (e) => e.error,
            'error',
            ZangetsuRepoError.invalidIndex,
          ),
        ),
      );
      status = 200;
      body = {'hello': 1};
      await expectLater(
        store.addRepo(repo),
        throwsA(
          isA<ZangetsuRepoException>().having(
            (e) => e.error,
            'error',
            ZangetsuRepoError.invalidIndex,
          ),
        ),
      );
      expect(store.repos(), isEmpty);
    });

    test('removing a repo drops its sources and their cached code', () async {
      serve([entry('alpha')]);
      final sources = await store.addRepo(repo);
      await store.install(sources.single);
      await cache.writeCode(name: 'zx-alpha', version: 10000, code: 'x');

      await store.removeRepo(repo);
      expect(store.repos(), isEmpty);
      expect(store.installed(), isEmpty);
      expect(store.manifest(repo), isEmpty);
      expect(cache.readCode('zx-alpha', 10000), isNull);
      expect(cache.readVersion('zx-alpha'), isNull);
    });
  });

  group('installed sources', () {
    test('install, disable and remove', () async {
      serve([entry('alpha')]);
      final alpha = (await store.addRepo(repo)).single;
      await store.install(alpha);
      expect(store.installed().single.enabled, isTrue);

      await store.setEnabled('zx-alpha', false);
      expect(store.installedById('zx-alpha')!.enabled, isFalse);

      await cache.writeCode(name: 'zx-alpha', version: 10000, code: 'x');
      await store.remove('zx-alpha');
      expect(store.installed(), isEmpty);
      expect(cache.readCode('zx-alpha', 10000), isNull);
    });

    test('a built-in source is never installed', () async {
      serve([entry('nyaa', builtIn: true)]);
      await store.install((await store.addRepo(repo)).single);
      expect(store.installed(), isEmpty);
    });

    test('a manifest version change is an update', () async {
      serve([entry('alpha'), entry('beta')]);
      final first = await store.addRepo(repo);
      for (final s in first) {
        await store.install(s);
      }
      await store.setEnabled('zx-beta', false);
      expect(store.updates(), isEmpty);

      serve([entry('alpha', version: '1.0.1'), entry('beta', version: '2.0.0')]);
      await store.refreshAll();
      expect(store.updates().map((s) => s.providerId), ['zx-alpha', 'zx-beta']);
      expect(store.installedById('zx-alpha')!.version, '1.0.0');

      await cache.writeCode(name: 'zx-alpha', version: 10000, code: 'old');
      expect(await store.update('zx-alpha'), isTrue);
      expect(store.installedById('zx-alpha')!.version, '1.0.1');
      expect(cache.readCode('zx-alpha', 10000), isNull);

      expect(await store.updateAll(), 1);
      expect(store.updates(), isEmpty);
      final beta = store.installedById('zx-beta')!;
      expect(beta.version, '2.0.0');
      expect(beta.enabled, isFalse);
    });
  });

  group('providers', () {
    Future<void> installAll(List<Map<String, Object?>> entries) async {
      serve(entries);
      for (final s in await store.addRepo(repo)) {
        await store.install(s);
      }
    }

    test('an installed source runs on the device through its bundle', () async {
      await installAll([entry('alpha', version: '1.0.3', type: 'anime')]);
      final p = store.providers(allowAdult: false).single;
      expect(p.id, 'zx-alpha');
      expect(p.mode, 'client');
      expect(p.category, 'anime');
      expect(p.description, contains('owner'));
      expect(p.extractor!.name, 'zx-alpha');
      expect(p.extractor!.scope, 'all');
      expect(p.extractor!.version, 10003);
      expect(
        p.extractor!.url,
        '/extractors/zangetsu-ext?src='
        '${Uri.encodeQueryComponent('https://raw.githubusercontent.com/owner/repo/main/providers/alpha.js')}'
        '&id=zx-alpha',
      );
    });

    test('disabled and adult sources are hidden', () async {
      await installAll([
        entry('alpha'),
        entry('beta'),
        entry('hot', nsfw: true),
      ]);
      await store.setEnabled('zx-beta', false);
      expect(store.providers(allowAdult: false).map((p) => p.id), [
        'zx-alpha',
      ]);
      expect(store.providers(allowAdult: true).map((p) => p.id), [
        'zx-alpha',
        'zx-hot',
      ]);
      expect(store.providerById('zx-beta', allowAdult: true), isNull);
      expect(store.providerById('zx-hot', allowAdult: false), isNull);
      expect(store.providerById('zx-hot', allowAdult: true)?.id, 'zx-hot');
      expect(store.providerById('alpha', allowAdult: true), isNull);
    });

    test('a source that becomes built in stops registering', () async {
      await installAll([entry('alpha')]);
      serve([entry('alpha', builtIn: true)]);
      await store.refreshAll();
      expect(store.providers(allowAdult: true), isEmpty);
    });

    test('built-in providers always win', () {
      final external = [
        ZangetsuRepoStore.toProvider(
          const ZangetsuSource(
            id: 'nyaa',
            providerId: 'zx-nyaa',
            name: 'Nyaa',
            repoUrl: repo,
            file: 'x.js',
          ),
        ),
        ZangetsuRepoStore.toProvider(
          const ZangetsuSource(
            id: 'taken',
            providerId: 'zx-taken',
            name: 'Taken',
            repoUrl: repo,
            file: 'x.js',
          ),
        ),
        ZangetsuRepoStore.toProvider(
          const ZangetsuSource(
            id: 'fresh',
            providerId: 'zx-fresh',
            name: 'Fresh',
            repoUrl: repo,
            file: 'x.js',
          ),
        ),
      ];
      final merged = ZangetsuRepoStore.merge([
        provider('nyaa'),
        provider('zx-taken'),
      ], external);
      expect(merged.map((p) => p.id), ['nyaa', 'zx-taken', 'zx-fresh']);
      expect(merged[1].name, 'zx-taken');
    });
  });
}
