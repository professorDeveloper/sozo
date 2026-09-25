import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/features/extensions/data/lnreader_patches.dart';
import 'package:soplay/features/extensions/data/mangayomi_repo_store.dart';
import 'package:soplay/features/extensions/domain/entities/mangayomi_source.dart';

const _official =
    'https://raw.githubusercontent.com/LNReader/lnreader-plugins/plugins/v3.0.0/.dist/plugins.min.json';

MangayomiSource _plugin(
  String id,
  String version, {
  String code =
      'https://raw.githubusercontent.com/lnreader/lnreader-plugins/plugins/v3.0.0/.js/src/plugins/x.js',
}) => MangayomiSource.fromLnReaderJson({
  'id': id,
  'name': id,
  'site': 'https://site.example/',
  'version': version,
  'url': code,
}, repoUrl: _official)!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final patch = LnReaderPatches.all.first;

  test('the official plugin at the patched version is replaced', () {
    expect(
      LnReaderPatches.forSource(_plugin(patch.id, patch.version)),
      same(patch),
    );
  });

  test('a newer upstream version runs as published', () {
    expect(LnReaderPatches.forSource(_plugin(patch.id, '99.0.0')), isNull);
  });

  test('a fork reusing the id is left alone', () {
    final fork = _plugin(
      patch.id,
      patch.version,
      code:
          'https://raw.githubusercontent.com/someone/lnreader-plugins/plugins/v3.0.0/.js/src/plugins/x.js',
    );
    expect(LnReaderPatches.forSource(fork), isNull);
  });

  test(
    'every patch has its build in the assets, and nothing else is there',
    () {
      final files = Directory('assets/lnreader/patches')
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .toSet();
      expect(files, {for (final p in LnReaderPatches.all) '${p.id}.js'});
      final built = File('tool/lnreader_patches/plugins.txt')
          .readAsLinesSync()
          .where(
            (l) =>
                l.isNotEmpty && !l.startsWith('#') && !l.startsWith('commit '),
          )
          .map((l) => l.split(' ').first)
          .toSet();
      expect(built, {for (final p in LnReaderPatches.all) p.id});
    },
  );

  group('store', () {
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('sozo-lnreader-patch-');
      Hive.init(dir.path);
      await Hive.openBox(AppConstants.settingsBox);
    });
    tearDown(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });

    test('serves the bundled build instead of downloading', () async {
      final store = MangayomiRepoStore(dio: Dio());
      final code = await store.code(_plugin(patch.id, patch.version));
      expect(code, contains('parseChapter'));
      expect(code, contains(patch.id));
    });
  });
}
