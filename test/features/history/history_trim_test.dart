// Fifty episodes of one show used to erase everything else the viewer watched.
//
// History is keyed per episode; Continue watching and the History screen both
// collapse it to one card per title. The cap counted rows, so a viewer under
// two cours into a weekly anime had a store containing nothing but that anime,
// and a home screen with one card on it.
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/history/domain/history_trim.dart';

typedef Row = ({String key, String contentUrl, int watchedAt});

/// Rows for [count] episodes of [title], watched in order from [from].
List<Row> episodes(String title, int count, {int from = 0}) => [
  for (var i = 0; i < count; i++)
    (key: '$title::episode::$i', contentUrl: title, watchedAt: from + i),
];

void main() {
  group('one series cannot evict every other title', () {
    test('the defect, at the scale it happens at', () {
      // Fifty episodes of Frieren, then one film watched after them. Under the
      // old fifty-row cap the film was the fifty-first row and went straight
      // back out — or, watched first, was evicted by episode fifty.
      final rows = [
        ...episodes('frieren', 50),
        (key: 'film', contentUrl: 'film', watchedAt: 100),
      ];

      final dropped = HistoryTrim.keysToDrop(rows).toSet();

      expect(dropped, isEmpty, reason: '51 rows is nowhere near the budget');
    });

    test('and when the budget really is reached, the cards survive', () {
      // Two hundred titles with one row each, plus a single series long enough
      // to blow the budget on its own. Every title's card must still be there.
      final rows = <Row>[
        ...episodes('onepiece', 1400),
        for (var i = 0; i < 200; i++)
          (key: 'title$i', contentUrl: 'title$i', watchedAt: 10000 + i),
      ];

      final dropped = HistoryTrim.keysToDrop(rows).toSet();
      final kept = rows.where((r) => !dropped.contains(r.key)).toList();

      expect(kept, hasLength(HistoryTrim.maxRows));
      for (var i = 0; i < 200; i++) {
        expect(
          dropped.contains('title$i'),
          isFalse,
          reason:
              'title$i is a whole title, and the only thing dropped should be '
              'a long series\' older episodes',
        );
      }
      expect(
        kept.where((r) => r.contentUrl == 'onepiece'),
        isNotEmpty,
        reason: 'the series itself must not be erased either',
      );
    });

    test('the episodes dropped are the oldest ones', () {
      final rows = episodes('onepiece', HistoryTrim.maxRows + 10);

      final dropped = HistoryTrim.keysToDrop(rows).toSet();

      expect(dropped, hasLength(10));
      for (var i = 0; i < 10; i++) {
        expect(dropped, contains('onepiece::episode::$i'));
      }
      expect(
        dropped.contains('onepiece::episode::${HistoryTrim.maxRows + 9}'),
        isFalse,
        reason: 'the newest episode is the card — it goes last, if ever',
      );
    });
  });

  group('the trim always terminates', () {
    test('a store of nothing but cards still gets trimmed', () {
      // The case the second pass exists for: every row is its own title's most
      // recent, so the first pass can protect nothing and would loop forever
      // or give up over budget.
      final rows = [
        for (var i = 0; i < HistoryTrim.maxRows + 25; i++)
          (key: 't$i', contentUrl: 't$i', watchedAt: i),
      ];

      final dropped = HistoryTrim.keysToDrop(rows).toSet();

      expect(dropped, hasLength(25));
      for (var i = 0; i < 25; i++) {
        expect(dropped, contains('t$i'), reason: 'oldest titles go first');
      }
    });

    test('nothing is dropped under the budget', () {
      final rows = episodes('anything', HistoryTrim.maxRows);
      expect(HistoryTrim.keysToDrop(rows), isEmpty);
    });

    test('an empty store is not a special case', () {
      expect(HistoryTrim.keysToDrop(const <Row>[]), isEmpty);
    });

    test('no key is returned twice', () {
      // The two passes share a set; returning a key twice would make the
      // caller delete something already gone and miscount what it freed.
      final rows = [
        ...episodes('a', 800),
        ...episodes('b', 800, from: 5000),
      ];
      final dropped = HistoryTrim.keysToDrop(rows);
      expect(dropped.toSet(), hasLength(dropped.length));
      expect(dropped, hasLength(1600 - HistoryTrim.maxRows));
    });
  });
}
