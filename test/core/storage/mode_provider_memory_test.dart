// Each content mode keeps the source last picked in it, so Watch → Manga →
// Watch comes back to the CloudStream source rather than the first one.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/storage/hive_service.dart';

void main() {
  late Directory dir;
  late HiveService hive;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sozo_mode_memory_');
    Hive.init(dir.path);
    await Hive.openBox(AppConstants.authBox);
    await Hive.openBox(AppConstants.settingsBox);
    hive = HiveService();
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('each mode keeps its own source', () async {
    expect(hive.providerForMode('video'), isNull);
    await hive.rememberProviderForMode('video', 'cs:SomeProvider');
    await hive.rememberProviderForMode('manga', 'mn:mangadex');
    expect(hive.providerForMode('video'), 'cs:SomeProvider');
    expect(hive.providerForMode('manga'), 'mn:mangadex');
    await hive.rememberProviderForMode('video', 'vidapi');
    expect(hive.providerForMode('video'), 'vidapi');
    expect(hive.providerForMode('novel'), isNull);
  });
}
