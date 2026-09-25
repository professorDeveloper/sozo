import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/features/tracker/data/release_feed_store.dart';
import 'package:soplay/features/tracker/domain/release_entry.dart';

ReleaseEntry _e(String url, DateTime at, {int ep = 5, int? from, bool seen = false}) =>
    ReleaseEntry(
      provider: 'p',
      contentUrl: url,
      title: url,
      thumbnail: '',
      mode: 'video',
      episode: ep,
      fromEpisode: from ?? ep,
      at: at.millisecondsSinceEpoch,
      seen: seen,
    );

void main() {
  group('grouping', () {
    final now = DateTime(2026, 9, 24, 0, 10);

    test('calendar days, newest first, empty buckets left out', () {
      final groups = groupReleases([
        _e('old', DateTime(2026, 9, 10)),
        _e('late-last-night', DateTime(2026, 9, 23, 23, 50)),
        _e('just-now', DateTime(2026, 9, 24, 0, 5)),
        _e('monday', DateTime(2026, 9, 21, 12)),
      ], now);
      expect(groups.map((g) => g.$1).toList(), [
        ReleaseBucket.today,
        ReleaseBucket.yesterday,
        ReleaseBucket.thisWeek,
        ReleaseBucket.earlier,
      ]);
      expect(groups[1].$2.single.contentUrl, 'late-last-night');
    });

    test('within a day the newest leads', () {
      final groups = groupReleases([
        _e('a', DateTime(2026, 9, 24, 0, 1)),
        _e('b', DateTime(2026, 9, 24, 0, 9)),
      ], now);
      expect(groups.single.$2.map((e) => e.contentUrl), ['b', 'a']);
    });
  });

  group('absorbing', () {
    final t = DateTime(2026, 9, 24);

    test('an unseen release grows its range', () {
      final merged = _e('a', t, ep: 11, from: 10).absorb(_e('a', t, ep: 12));
      expect(merged.fromEpisode, 10);
      expect(merged.episode, 12);
    });

    test('a seen one starts over after what was seen', () {
      final merged = _e('a', t, ep: 11, seen: true).absorb(_e('a', t, ep: 13, from: 13));
      expect(merged.fromEpisode, 13);
      expect(merged.seen, isFalse);
    });

    test('the same episode twice (push and device) changes nothing', () {
      final first = _e('a', t, ep: 12);
      expect(identical(first.absorb(_e('a', t, ep: 12)), first), isTrue);
    });
  });

  group('store', () {
    late Box box;
    setUpAll(() async {
      Hive.init('${Directory.systemTemp.path}/sozo_release_feed');
      box = await Hive.openBox('sozo_release_feed');
    });
    tearDownAll(() async => Hive.close());
    setUp(() => box.clear());

    test('one row per title, NEW until seen', () async {
      final store = ReleaseFeedStore(box: box, now: () => DateTime(2026, 9, 24));
      await store.add(_e('a', DateTime(2026, 9, 23), ep: 3));
      await store.add(_e('a', DateTime(2026, 9, 24), ep: 4));
      expect(store.entries(), hasLength(1));
      expect(store.unseenFor('a')?.newCount, 2);
      await store.markTitleSeen('a');
      expect(store.unseenFor('a'), isNull);
      expect(store.unseenCount, 0);
    });

    test('old rows age out', () async {
      final store = ReleaseFeedStore(box: box, now: () => DateTime(2026, 9, 24));
      await store.add(_e('old', DateTime(2026, 7, 1)));
      await store.add(_e('new', DateTime(2026, 9, 23)));
      expect(store.entries().map((e) => e.contentUrl), ['new']);
    });

    test('dismiss and undo', () async {
      final store = ReleaseFeedStore(box: box, now: () => DateTime(2026, 9, 24));
      final e = _e('a', DateTime(2026, 9, 23));
      await store.add(e);
      await store.dismiss(e.key);
      expect(store.entries(), isEmpty);
      await store.restore(e);
      expect(store.entries(), hasLength(1));
    });
  });
}
