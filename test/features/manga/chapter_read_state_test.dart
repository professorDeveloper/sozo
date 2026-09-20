// A chapter list has to show what has been read.
//
// The app knew whether a chapter had been REPORTED to a tracker this session,
// and where the reader had got to in the one chapter it was last in. Neither
// survives as "I have read this", so a list of four hundred chapters looked
// identical whether you had read one of them or three hundred.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/features/manga/data/chapter_read_store.dart';

void main() {
  late Directory dir;
  late ChapterReadStore store;
  const p = 'mn:497';
  const url = 'https://source.test/manga/x';

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('chapters_read');
    Hive.init(dir.path);
    await Hive.openBox(AppConstants.historyBox);
    store = ChapterReadStore();
  });

  tearDown(() async {
    await Hive.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('nothing is read until something says so', () {
    expect(store.read(p, url), isEmpty);
    expect(store.isRead(p, url, 1), isFalse);
  });

  test('a mark survives and reads back', () async {
    await store.mark(p, url, [3]);
    expect(store.isRead(p, url, 3), isTrue);
    expect(store.read(p, url), {3});
  });

  test('marking is append-only, so reading on keeps the earlier ones', () async {
    // The bug this exists to prevent: finishing chapter 4 must not be what
    // un-marks chapter 3.
    await store.mark(p, url, [3]);
    await store.mark(p, url, [4]);
    await store.mark(p, url, [5]);
    expect(store.read(p, url), {3, 4, 5});
  });

  test('and re-reading a finished chapter changes nothing', () async {
    await store.mark(p, url, [3]);
    final before = store.read(p, url);
    await store.mark(p, url, [3]);
    expect(store.read(p, url), before);
  });

  test('extras and omakes are not markable', () async {
    // A source numbers those 0 or less, and a mark on one is a mark the reader
    // can neither see nor undo — the same rule the tracker ledger applies.
    await store.mark(p, url, [0, -1, 2]);
    expect(store.read(p, url), {2});
  });

  test('unmark removes exactly what it was given', () async {
    await store.mark(p, url, [1, 2, 3]);
    await store.unmark(p, url, [2]);
    expect(store.read(p, url), {1, 3});
  });

  test('two sources of one work do not share a ledger', () async {
    // Two sources rarely agree on numbering, so merging them would mark
    // chapters read that nobody opened.
    await store.mark(p, url, [1, 2, 3]);
    expect(store.read('mn:998', url), isEmpty);
    expect(store.read(p, 'https://other.test/manga/x'), isEmpty);
  });

  test('clearing a title forgets only that title', () async {
    await store.mark(p, url, [1]);
    await store.mark(p, 'https://source.test/manga/y', [1]);
    await store.clear(p, url);
    expect(store.read(p, url), isEmpty);
    expect(store.read(p, 'https://source.test/manga/y'), {1});
  });

  test('an emptied ledger leaves no row behind', () async {
    await store.mark(p, url, [1]);
    await store.unmark(p, url, [1]);
    expect(
      Hive.box(AppConstants.historyBox).containsKey(
        ChapterReadStore.keyFor(p, url),
      ),
      isFalse,
      reason: 'an empty list is a row that will never be read again',
    );
  });

  test('with no box open at all, nothing throws', () async {
    await Hive.close();
    expect(store.read(p, url), isEmpty);
    expect(() async => store.mark(p, url, [1]), returnsNormally);
  });

  group('where it is written and shown', () {
    String read(String path) => File(path).readAsStringSync();

    test('the reader marks without waiting for a tracker', () {
      // Whether a chapter has been read is a fact about this device; whether
      // anybody was told is a different question with its own preconditions.
      // Tying them together meant the list could only show progress to somebody
      // signed in to AniList.
      final reader = read('lib/features/manga/presentation/pages/reader_page.dart');
      final markAt = reader.indexOf('_readStore.mark(');
      final gateAt = reader.indexOf('if (!anilist.isConnected) return;');
      expect(markAt, greaterThan(-1));
      expect(gateAt, greaterThan(-1));
      expect(
        markAt,
        lessThan(gateAt),
        reason: 'the local mark sits behind the tracker gate',
      );
    });

    test('and not in incognito', () {
      final reader = read('lib/features/manga/presentation/pages/reader_page.dart');
      final guard = reader.indexOf('if (_hive.isIncognito) return;');
      expect(guard, greaterThan(-1));
      expect(guard, lessThan(reader.indexOf('_readStore.mark(')));
    });

    test('the list dims a read row but keeps the current one', () {
      final page = read('lib/features/detail/presentation/pages/episodes_page.dart');
      expect(page, contains('opacity: read && progress == null ? 0.45 : 1'));
    });

    test('and the action is reading-only', () {
      // An episode has watch history with a position in it; a chapter has
      // neither, which is why only one of them needs telling.
      final page = read('lib/features/detail/presentation/pages/episodes_page.dart');
      expect(page, contains('onToggleRead: _isManga ? _toggleReadSelected : null'));
    });
  });
}
