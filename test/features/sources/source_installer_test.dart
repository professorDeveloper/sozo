import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/extensions/extension_bridge.dart';
import 'package:soplay/features/extensions/data/mangayomi_repo_store.dart';
import 'package:soplay/features/extensions/data/source_installer.dart';
import 'package:soplay/features/extensions/domain/entities/catalog_source_entity.dart';
import 'package:soplay/features/extensions/domain/entities/extension_repo_entity.dart';

void main() {
  test(
    'old catalog uses the known novel sibling, custom roots are preserved',
    () {
      const root =
          'https://raw.githubusercontent.com/m2k3a/mangayomi-extensions/main/index.json';
      CatalogSourceEntity novel(String url, {String index = ''}) =>
          CatalogSourceEntity(
            id: '1',
            kind: ExtensionRepoKind.mangayomi,
            name: 'Novel',
            itemType: CatalogItemType.novel,
            repoUrl: url,
            sourceIndexUrl: index,
          );
      expect(
        sourceInstallUrl(novel(root)),
        root.replaceFirst('index.json', 'novel_index.json'),
      );
      expect(
        sourceInstallUrl(novel('https://custom.invalid/mixed.json')),
        'https://custom.invalid/mixed.json',
      );
      expect(
        sourceInstallUrl(
          novel(root, index: 'https://custom.invalid/text.json'),
        ),
        'https://custom.invalid/text.json',
      );
    },
  );

  for (final legacy in [false, true]) {
    test(
      'CloudStream ${legacy ? "legacy" : "current"} catalog installs only the selected plugin',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final requests = <Uri>[];
        server.listen((request) async {
          requests.add(request.uri);
          final response = request.uri.path.endsWith('listRepoPlugins')
              ? {
                  'plugins': [
                    {'name': 'Chosen', 'internalName': 'ChosenPlugin'},
                    {'name': 'Unwanted', 'internalName': 'HugePlugin'},
                  ],
                }
              : {
                  'pluginCount': 1,
                  'providers': ['ChosenProvider'],
                };
          request.response.write(jsonEncode(response));
          await request.response.close();
        });
        ExtensionBridge.setUrl('http://127.0.0.1:${server.port}');
        addTearDown(() async {
          ExtensionBridge.setUrl(null);
          await server.close(force: true);
        });
        final count = await installCatalogSource(
          CatalogSourceEntity(
            id: 'db-id',
            externalId: legacy ? '' : 'ChosenPlugin',
            kind: ExtensionRepoKind.cloudstream,
            name: 'Chosen',
            repoUrl: 'https://fixture.invalid/repo.json',
          ),
          MangayomiRepoStore(dio: Dio()),
        );
        expect(count, 1);
        expect(requests.where((r) => r.path.endsWith('/addRepo')), isEmpty);
        final install = requests.singleWhere(
          (r) => r.path.endsWith('/installPlugin'),
        );
        expect(install.queryParameters['internalName'], 'ChosenPlugin');
        expect(requests.length, legacy ? 2 : 1);
      },
    );
  }

  test(
    'downloaded plugin with no loadable providers is reported as failure',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.write('{"pluginCount":1,"providers":[]}');
        await request.response.close();
      });
      ExtensionBridge.setUrl('http://127.0.0.1:${server.port}');
      addTearDown(() async {
        ExtensionBridge.setUrl(null);
        await server.close(force: true);
      });
      await expectLater(
        installCatalogSource(
          const CatalogSourceEntity(
            id: 'db-id',
            externalId: 'Broken',
            kind: ExtensionRepoKind.cloudstream,
            name: 'Broken',
            repoUrl: 'https://fixture.invalid/repo.json',
          ),
          MangayomiRepoStore(dio: Dio()),
        ),
        throwsStateError,
      );
    },
  );
}
