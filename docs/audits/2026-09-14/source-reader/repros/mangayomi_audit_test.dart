// ignore_for_file: avoid_print
// Audit-only regression probes: assertions document current broken behavior.
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
  Future<dynamic> call(String sourceId, String method,
      {List<Object?> args = const []}) async {
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
  Map<String, Object> source(String id, String code, {int type = 0}) => {
        'id': id, 'name': id, 'baseUrl': 'https://fixture.example',
        'sourceCodeUrl': '$base/$code', 'version': '1.0.0',
        'itemType': type, 'sourceCodeLanguage': 1,
      };
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sozo-mangayomi-audit-');
    Hive.init(dir.path);
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
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('same ID/version replacement uses new metadata but old repository code', () async {
    responses['/a.json'] = [source('shared', 'a.js')];
    responses['/b.json'] = [source('shared', 'b.js')];
    responses['/a.js'] = 'CODE_FROM_A';
    responses['/b.js'] = 'CODE_FROM_B';
    await store.addRepo('$base/a.json');
    expect(await store.code(store.sourceById('shared')!), 'CODE_FROM_A');
    await store.addRepo('$base/b.json');
    expect(store.sourceById('shared')!.sourceCodeUrl, '$base/b.js');
    expect(await store.code(store.sourceById('shared')!), 'CODE_FROM_A');
    print('CONFIRMED: metadata B + executable code A at equal ID/version');
  });

  test('repo refresh retains removed source and JavaScript-to-Dart migration', () async {
    responses['/repo.json'] = [source('removed', 'a.js'), source('migrated', 'b.js')];
    await store.addRepo('$base/repo.json');
    responses['/repo.json'] = [ {...source('migrated', 'b.dart'), 'sourceCodeLanguage': 0} ];
    await store.checkUpdates();
    expect(store.sources().map((s) => s.id).toSet(), {'removed', 'migrated'});
    expect(store.sourceById('migrated')!.isJavaScript, true);
    print('CONFIRMED: upstream removed/Dart-only sources remain installed as JavaScript');
  });

  test('page translation drops per-page headers and never asks getHeaders', () async {
    responses['/repo.json'] = [source('manga', 'a.js')];
    await store.addRepo('$base/repo.json');
    final runtime = FixtureRuntime(store);
    runtime.values['manga:getPageList'] = [
      {'url': 'https://cdn.example/1.jpg', 'headers': {'Authorization': 'PAGE_1'}},
      {'url': 'https://cdn.example/2.jpg', 'headers': {'Authorization': 'PAGE_2'}},
    ];
    final result = await MangayomiBridge(runtime: runtime, store: store).pageList('manga', '/chapter');
    expect(result['headers'], {'Authorization': 'PAGE_2'});
    expect((result['pages'] as List).first['headers'], isNull);
    expect(runtime.calls, ['manga:getPageList']);
    print('CONFIRMED: page 1 now uses PAGE_2 authorization; getHeaders never called');
  });

  test('relative links cross-contaminate detail title between independent sources', () async {
    responses['/repo.json'] = [source('one', 'a.js'), source('two', 'b.js')];
    await store.addRepo('$base/repo.json');
    final runtime = FixtureRuntime(store);
    runtime.values['one:search'] = {'list': [{'link':'/series/1', 'name':'Novel One'}]};
    runtime.values['two:search'] = {'list': [{'link':'/series/1', 'name':'Novel Two'}]};
    runtime.values['one:getDetail'] = {'chapters': []};
    final bridge = MangayomiBridge(runtime: runtime, store: store);
    await bridge.search('one', 'one');
    await bridge.search('two', 'two');
    final detail = await bridge.load('one', '/series/1');
    expect(detail['provider'], 'my:one');
    expect(detail['title'], 'Novel Two');
    print('CONFIRMED: source one detail receives source two title');
  });

  test('novel type routes to text API, not images (positive control)', () async {
    responses['/repo.json'] = [source('novel', 'a.js', type: 2)];
    await store.addRepo('$base/repo.json');
    final runtime = FixtureRuntime(store);
    runtime.values['novel:getHtmlContent'] = ['<p>First</p>', '<p>Second</p>'];
    final result = await MangayomiBridge(runtime: runtime, store: store).pageList('novel', '/chapter');
    expect(result['html'], '<p>First</p><p>Second</p>');
    expect(runtime.calls, ['novel:getHtmlContent']);
    expect(store.sourceById('novel')!.itemType, MangayomiItemType.novel);
  });
}
