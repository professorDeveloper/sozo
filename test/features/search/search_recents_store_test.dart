import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/features/search/data/search_recents_store.dart';

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('sozo_recents_');
    Hive.init(dir.path);
    await Hive.openBox(AppConstants.settingsBox);
  });

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  setUp(() async {
    // Absent, not empty: the state a device is in before its first search.
    await Hive.box(AppConstants.settingsBox).delete('search_recent_queries');
  });

  test('the first search on a fresh device is recorded', () async {
    // The regression this guards took the whole search screen down, not just
    // the recents row. `load()` handed back a `const []` when nothing was
    // stored, `add` mutated it, and the throw came out of SearchBloc between
    // the fetch that had already succeeded and the emit that would have shown
    // its results — so every query fetched 200 OK and then displayed nothing.
    //
    // It could not heal, either: the write that would have created the key
    // sits after the mutation that threw.
    expect(await SearchRecentsStore().add('hello'), ['hello']);
    expect(SearchRecentsStore().load(), ['hello']);
  });

  test('removing from a fresh device does not throw either', () async {
    expect(await SearchRecentsStore().remove('anything'), isEmpty);
  });

  test('the newest query comes first and is not duplicated', () async {
    final store = SearchRecentsStore();
    await store.add('one');
    await store.add('two');
    expect(await store.add('ONE'), ['ONE', 'two']);
  });

  test('only the last maxEntries are kept', () async {
    final store = SearchRecentsStore();
    for (var i = 0; i < SearchRecentsStore.maxEntries + 4; i++) {
      await store.add('q$i');
    }
    final list = store.load();
    expect(list, hasLength(SearchRecentsStore.maxEntries));
    expect(list.first, 'q${SearchRecentsStore.maxEntries + 3}');
  });

  test('a cleared list is still usable', () async {
    final store = SearchRecentsStore();
    await store.add('one');
    expect(await store.clear(), isEmpty);
    expect(await store.add('two'), ['two']);
  });
}
