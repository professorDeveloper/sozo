// Production contracts exercised with temporary Hive and loopback repository fixtures.
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/js/dart_fetch.dart';
import 'package:soplay/features/extensions/data/mangayomi_bridge.dart';
import 'package:soplay/features/extensions/data/mangayomi_repo_store.dart';
import 'package:soplay/features/extensions/data/mangayomi_runtime.dart';
import 'package:soplay/features/extensions/domain/entities/mangayomi_source.dart';

class FixtureRuntime extends MangayomiRuntime {
  FixtureRuntime(MangayomiRepoStore store)
    : super(store: store, dartFetch: DartFetch.create());
  final calls = <String>[];
  final values = <String, dynamic>{};
  @override
  Future<dynamic> call(
    String sourceId,
    String method, {
    List<Object?> args = const [],
  }) async {
    calls.add('$sourceId:$method');
    return values['$sourceId:$method'];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null; // Test-only loopback fixture transport.
  late Directory dir;
  late HttpServer server;
  late String base;
  late MangayomiRepoStore store;
  final responses = <String, Object>{};
  final requests = <String, int>{};
  Map<String, Object> source(String id, String code, {int type = 0}) => {
    'id': id,
    'name': id,
    'baseUrl': 'https://fixture.example',
    'sourceCodeUrl': '$base/$code',
    'version': '1.0.0',
    'itemType': type,
    'sourceCodeLanguage': 1,
  };
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sozo-mangayomi-audit-');
    Hive.init(dir.path);
    await Hive.openBox(AppConstants.settingsBox);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    responses.clear();
    requests.clear();
    server.listen((request) async {
      requests.update(
        request.uri.path,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
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
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('same ID/version replacement fetches the new repository code', () async {
    responses['/a.json'] = [source('shared', 'a.js')];
    responses['/b.json'] = [source('shared', 'b.js')];
    responses['/a.js'] = 'CODE_FROM_A';
    responses['/b.js'] = 'CODE_FROM_B';
    await store.addRepo('$base/a.json');
    expect(await store.code(store.sourceById('shared')!), 'CODE_FROM_A');
    await store.addRepo('$base/b.json');
    expect(store.sourceById('shared')!.sourceCodeUrl, '$base/b.js');
    expect(await store.code(store.sourceById('shared')!), 'CODE_FROM_B');
  });

  test(
    'repo refresh retires removed sources and JavaScript-to-Dart migration',
    () async {
      responses['/repo.json'] = [
        source('removed', 'a.js'),
        source('migrated', 'b.js'),
      ];
      await store.addRepo('$base/repo.json');
      responses['/repo.json'] = [
        {...source('migrated', 'b.dart'), 'sourceCodeLanguage': 0},
      ];
      await store.checkUpdates();
      expect(store.sources(), isEmpty);
      expect(store.sourceById('migrated'), isNull);
    },
  );

  test(
    'page translation preserves headers and batches provider image headers',
    () async {
      responses['/repo.json'] = [source('manga', 'a.js')];
      await store.addRepo('$base/repo.json');
      final runtime = FixtureRuntime(store);
      runtime.values['manga:getPageList'] = [
        {
          'url': 'https://cdn.example/1.jpg',
          'headers': {'Authorization': 'PAGE_1'},
        },
        {
          'url': 'https://cdn.example/2.jpg',
          'headers': {'Authorization': 'PAGE_2'},
        },
      ];
      runtime.values['manga:__sozoImageHeaders'] = [
        {'User-Agent': 'custom'},
        {'Referer': 'https://second.example'},
      ];
      final result = await MangayomiBridge(
        runtime: runtime,
        store: store,
      ).pageList('manga', '/chapter');
      expect(result['headers'], {'Referer': 'https://fixture.example'});
      expect((result['pages'] as List).first['headers'], {
        'Authorization': 'PAGE_1',
        'User-Agent': 'custom',
      });
      expect((result['pages'] as List).last['headers'], {
        'Authorization': 'PAGE_2',
        'Referer': 'https://second.example',
      });
      expect(runtime.calls, ['manga:getPageList', 'manga:__sozoImageHeaders']);
    },
  );

  test('relative detail links retain provider-specific titles', () async {
    responses['/repo.json'] = [source('one', 'a.js'), source('two', 'b.js')];
    await store.addRepo('$base/repo.json');
    final runtime = FixtureRuntime(store);
    runtime.values['one:search'] = {
      'list': [
        {'link': '/series/1', 'name': 'Novel One'},
      ],
    };
    runtime.values['two:search'] = {
      'list': [
        {'link': '/series/1', 'name': 'Novel Two'},
      ],
    };
    runtime.values['one:getDetail'] = {'chapters': []};
    final bridge = MangayomiBridge(runtime: runtime, store: store);
    await bridge.search('one', 'one');
    await bridge.search('two', 'two');
    final detail = await bridge.load('one', '/series/1');
    expect(detail['provider'], 'my:one');
    expect(detail['title'], 'Novel One');
  });

  test(
    'cached source lookups reuse parsed objects and invalidate on remove',
    () async {
      responses['/large.json'] = [
        for (var i = 0; i < 3000; i++) source('source$i', '$i.js'),
      ];
      await store.addRepo('$base/large.json');
      final first = store.sourceById('source42');
      final timer = Stopwatch()..start();
      for (var i = 0; i < 30000; i++) {
        expect(identical(store.sourceById('my:source42'), first), isTrue);
      }
      timer.stop();
      // ignore: avoid_print -- bounded lookup benchmark reported by the test.
      print(
        '30000 cached ID lookups across 3000 sources: ${timer.elapsedMilliseconds} ms',
      );
      final copy = store.sources()..clear();
      expect(copy, isEmpty);
      expect(store.sources(), hasLength(3000));
      await store.removeRepo('$base/large.json');
      expect(store.sourceById('source42'), isNull);
    },
  );

  test('failed refresh preserves the previous repository snapshot', () async {
    responses['/repo.json'] = [source('kept', 'a.js')];
    await store.addRepo('$base/repo.json');
    responses.remove('/repo.json');
    await store.checkUpdates();
    expect(store.sourceById('kept'), isNotNull);
  });

  test(
    'malformed or missing index body preserves sources; explicit empty list retires',
    () async {
      responses['/repo.json'] = [source('kept', 'a.js')];
      await store.addRepo('$base/repo.json');
      for (final invalid in <Object>[
        [null, {}],
        '',
      ]) {
        responses['/repo.json'] = invalid;
        await expectLater(
          store.addRepo('$base/repo.json'),
          throwsFormatException,
        );
        expect(store.sourceById('kept'), isNotNull);
      }
      responses['/repo.json'] = [];
      await store.addRepo('$base/repo.json');
      expect(store.sources(), isEmpty);
    },
  );

  test('concurrent code requests share one download', () async {
    responses['/repo.json'] = [source('shared', 'code.js')];
    responses['/code.js'] = 'class DefaultExtension {}';
    await store.addRepo('$base/repo.json');
    final installed = store.sourceById('shared')!;
    await Future.wait(List.generate(8, (_) => store.code(installed)));
    expect(requests['/code.js'], 1);
  });

  test(
    'EPUB spine order is preserved for non-numbered chapter titles',
    () async {
      responses['/repo.json'] = [source('novel', 'a.js', type: 2)];
      await store.addRepo('$base/repo.json');
      final runtime = FixtureRuntime(store);
      runtime.values['novel:getDetail'] = {
        'chapterOrder': 'ascending',
        'chapters': [
          {'name': 'Opening', 'url': 'a;;;Opening'},
          {'name': 'Afterword', 'url': 'a;;;Afterword'},
        ],
      };
      final result = await MangayomiBridge(
        runtime: runtime,
        store: store,
      ).load('novel', '/book');
      expect((result['episodes'] as List).map((e) => e['label']).toList(), [
        'Opening',
        'Afterword',
      ]);
    },
  );

  test(
    'novel type routes to text API, not images (positive control)',
    () async {
      responses['/repo.json'] = [source('novel', 'a.js', type: 2)];
      await store.addRepo('$base/repo.json');
      final runtime = FixtureRuntime(store);
      runtime.values['novel:getHtmlContent'] = [
        '<p>First</p>',
        '<p>Second</p>',
      ];
      final result = await MangayomiBridge(
        runtime: runtime,
        store: store,
      ).pageList('novel', '/chapter');
      expect(result['html'], '<p>First</p><p>Second</p>');
      expect(runtime.calls, ['novel:getHtmlContent']);
      expect(store.sourceById('novel')!.itemType, MangayomiItemType.novel);
    },
  );
}
