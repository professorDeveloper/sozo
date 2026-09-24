// Highlights persist per title and chapter, survive clearing history, and
// never break the reader when the stored data does not parse.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/storage/profile_scope.dart';
import 'package:soplay/features/manga/data/novel_highlight_store.dart';
import 'package:soplay/features/manga/domain/reading/novel_highlight.dart';

NovelHighlight mark(
  String id, {
  String ref = 'ch-1',
  int chapter = 1,
  int block = 0,
  int start = 0,
  int end = 5,
  HighlightColor color = HighlightColor.yellow,
  String note = '',
}) => NovelHighlight(
  id: id,
  chapterRef: ref,
  chapter: chapter,
  chapterLabel: 'Chapter $chapter',
  block: block,
  start: start,
  end: end,
  text: 'text $id',
  color: color,
  note: note,
  createdAt: 1,
);

void main() {
  late Directory dir;
  late NovelHighlightStore store;
  const p = 'ln:1';
  const url = 'https://novels.test/book';

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('highlights');
    Hive.init(dir.path);
    await Hive.openBox(AppConstants.settingsBox);
    await Hive.openBox(AppConstants.historyBox);
    store = NovelHighlightStore();
  });

  tearDown(() async {
    ProfileScope.reset();
    await Hive.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('nothing until something is highlighted', () {
    expect(store.all(p, url), isEmpty);
  });

  test(
    'a highlight reads back with its colour and note, from a fresh store',
    () async {
      await store.add(
        p,
        url,
        mark('a', color: HighlightColor.blue, note: 'remember this'),
      );
      final read = NovelHighlightStore().all(p, url).single;
      expect(read.id, 'a');
      expect(read.color, HighlightColor.blue);
      expect(read.note, 'remember this');
      expect((read.block, read.start, read.end), (0, 0, 5));
    },
  );

  test('per chapter, by ref or, when the ref moved, by number', () async {
    await store.add(p, url, mark('a'));
    await store.add(p, url, mark('b', ref: 'ch-2', chapter: 2));
    expect(store.forChapter(p, url, ref: 'ch-1', number: 1).map((h) => h.id), [
      'a',
    ]);
    expect(
      store.forChapter(p, url, ref: 'moved/ch-2', number: 2).map((h) => h.id),
      ['b'],
    );
    expect(store.forChapter(p, url, ref: 'ch-3', number: 3), isEmpty);
  });

  test('per title and source', () async {
    await store.add(p, url, mark('a'));
    expect(store.all('other', url), isEmpty);
    expect(store.all(p, '$url/2'), isEmpty);
  });

  test('listed in reading order', () async {
    await store.add(p, url, mark('late', chapter: 2, ref: 'ch-2'));
    await store.add(p, url, mark('mid', block: 3));
    await store.add(p, url, mark('early', block: 3, start: 1, end: 2));
    await store.add(p, url, mark('first', block: 0, start: 9, end: 12));
    expect(store.all(p, url).map((h) => h.id), [
      'first',
      'mid',
      'early',
      'late',
    ]);
  });

  test('update changes colour and note; remove forgets', () async {
    await store.add(p, url, mark('a'));
    await store.add(p, url, mark('b', block: 1));
    final a = store.all(p, url).first;
    await store.update(
      p,
      url,
      a.copyWith(color: HighlightColor.pink, note: 'n'),
    );
    expect(store.all(p, url).first.color, HighlightColor.pink);
    expect(store.all(p, url).first.note, 'n');
    await store.remove(p, url, {'a', 'b'});
    expect(store.all(p, url), isEmpty);
    expect(
      Hive.box(
        AppConstants.settingsBox,
      ).containsKey(NovelHighlightStore.keyFor(p, url)),
      isFalse,
    );
  });

  test('clearing history leaves highlights alone', () async {
    await store.add(p, url, mark('a'));
    await Hive.box(AppConstants.historyBox).clear();
    expect(store.all(p, url), hasLength(1));
  });

  test('each profile has its own', () async {
    await store.add(p, url, mark('mine'));
    ProfileScope.set(namespace: 'kid');
    expect(store.all(p, url), isEmpty);
    await store.add(p, url, mark('theirs'));
    ProfileScope.reset();
    expect(store.all(p, url).map((h) => h.id), ['mine']);
  });

  test('damaged data reads as none, and bad records are skipped', () async {
    final box = Hive.box(AppConstants.settingsBox);
    await box.put(NovelHighlightStore.keyFor(p, url), '{not json');
    expect(store.all(p, url), isEmpty);
    await box.put(
      NovelHighlightStore.keyFor(p, url),
      '[{"id":"ok","b":0,"s":1,"e":4},{"id":"bad","b":0,"s":4,"e":1},7]',
    );
    expect(store.all(p, url).map((h) => h.id), ['ok']);
  });

  test('without Hive open the reader carries on', () async {
    await Hive.close();
    expect(store.all(p, url), isEmpty);
    await store.add(p, url, mark('a'));
  });

  test('overlap is by block and characters', () {
    final h = mark('a', block: 2, start: 10, end: 20);
    expect(h.overlaps(2, 15, 30), isTrue);
    expect(h.overlaps(2, 20, 30), isFalse);
    expect(h.overlaps(1, 15, 30), isFalse);
  });
}
