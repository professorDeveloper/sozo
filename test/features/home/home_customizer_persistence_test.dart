import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/home/domain/home_rail.dart';

void main() {
  late Directory directory;
  late HiveService store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sozo-home-editor-');
    Hive.init(directory.path);
    await Hive.openBox(AppConstants.authBox);
    await Hive.openBox(AppConstants.settingsBox);
    store = HiveService();
  });
  tearDown(() async {
    store.homeRailsChanged.dispose();
    await Hive.close();
    await directory.delete(recursive: true);
  });
  test(
    'an optional rail enabled in the editor stays enabled after reload',
    () async {
      expect(store.getHomeRailHidden(), isNot(contains('watch_services')));
      await store.saveHomeRails(
        HomeRail.defaults.map((r) => r.id).toList(),
        {},
        fromCustomizer: true,
      );
      expect(
        HiveService().getHomeRailHidden(),
        isNot(contains('watch_services')),
      );
      expect(store.getHomeRailHidden(), isEmpty);
    },
  );
  test('explicitly hidden streaming services stay hidden', () async {
    final order = HomeRail.defaults.map((r) => r.id).toList();
    await store.saveHomeRails(order, {});
    expect(store.hasAnsweredHomeSuggestion('watch_services'), isFalse);
    await store.saveHomeRails(order, {'watch_services'}, fromCustomizer: true);
    expect(store.getHomeRailHidden(), contains('watch_services'));
  });
}
