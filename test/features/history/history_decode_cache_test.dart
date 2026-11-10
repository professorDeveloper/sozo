// History is read on every Home rebuild, every profile visit and every
// Continue rail refresh. Decoding the whole box each time was the cost; the
// cache must never hand back a row the box no longer holds.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/features/history/data/history_service.dart';
import 'package:soplay/features/history/domain/entities/history_item.dart';

HistoryItem _item(String url, int at) =>
    HistoryItem(contentUrl: url, provider: 'p', title: url, watchedAt: at);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUpAll(() async {
    await getIt.reset();
    dir = await Directory.systemTemp.createTemp('sozo_history_cache_');
    Hive.init(dir.path);
    await Hive.openBox(AppConstants.historyBox);
  });

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  setUp(() async => Hive.box(AppConstants.historyBox).clear());

  test('a second read decodes nothing', () async {
    final service = HistoryService();
    await service.save(_item('a', 1));
    await service.save(_item('b', 2));

    expect(service.getAll().map((e) => e.contentUrl), ['b', 'a']);
    final after = service.decodes;
    expect(service.getAll().map((e) => e.contentUrl), ['b', 'a']);
    expect(service.decodes, after);
  });

  test('a save, a remove and a clear are seen at once', () async {
    final service = HistoryService();
    await service.save(_item('a', 1));
    service.getAll();

    await service.save(_item('a', 5).copyWithPosition(10));
    expect(service.getAll().single.positionMs, 10);

    await service.save(_item('b', 6));
    expect(service.count, 2);
    await service.remove(_item('b', 6).storageKey);
    expect(service.getAll().map((e) => e.contentUrl), ['a']);

    await service.clearLocalOnly();
    expect(service.getAll(), isEmpty);
    expect(service.count, 0);
  });

  test('a write to the box from elsewhere drops the cached row', () async {
    final service = HistoryService();
    await service.save(_item('a', 1));
    service.getAll();

    final box = Hive.box(AppConstants.historyBox);
    await box.put(
      _item('a', 1).storageKey,
      jsonEncode(_item('a', 1).copyWithPosition(42).toJson()),
    );
    await pumpEventQueue();

    expect(service.getAll().single.positionMs, 42);
  });

  test('count skips the reader\'s chapter marks and decodes nothing', () async {
    final service = HistoryService();
    await service.save(_item('a', 1));
    await Hive.box(AppConstants.historyBox).put('chapters_read:p|m', [1, 2]);
    final before = service.decodes;
    expect(service.count, 1);
    expect(service.decodes, before);
  });

  test('the returned list cannot corrupt the cache', () async {
    final service = HistoryService();
    await service.save(_item('a', 1));
    service.getAll().clear();
    expect(service.getAll(), hasLength(1));
  });
}

extension on HistoryItem {
  HistoryItem copyWithPosition(int ms) => HistoryItem(
    contentUrl: contentUrl,
    provider: provider,
    title: title,
    watchedAt: watchedAt,
    positionMs: ms,
    durationMs: 100,
  );
}
