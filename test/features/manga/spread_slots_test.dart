import 'package:flutter_test/flutter_test.dart';

/// How pages are paired in the double-page reader.
///
/// Extracted here as the same arithmetic the reader uses, because getting it
/// wrong is not a visual glitch: every spread after the mistake is one page out
/// of step with how the book was drawn, which is the entire reason to show two
/// at a time.
List<List<int>> spreadSlots(int pageCount) {
  final slots = <List<int>>[];
  if (pageCount == 0) return slots;
  slots.add([0]);
  for (var i = 1; i < pageCount; i += 2) {
    slots.add([i, if (i + 1 < pageCount) i + 1]);
  }
  return slots;
}

/// Which slot holds [page] — used when the setting is switched mid-chapter.
int slotForPage(int page) => page == 0 ? 0 : ((page - 1) ~/ 2) + 1;

void main() {
  group('pairing', () {
    test('the cover stands alone', () {
      // A comic's first page is its cover. Pairing it with page two puts every
      // subsequent spread one page out of step.
      expect(spreadSlots(6).first, [0]);
    });

    test('the rest pair up from page two', () {
      expect(spreadSlots(7), [
        [0],
        [1, 2],
        [3, 4],
        [5, 6],
      ]);
    });

    test('an odd last page is shown alone rather than dropped', () {
      final slots = spreadSlots(6);
      expect(slots.last, [5]);
      expect(slots.expand((s) => s).toList(), [0, 1, 2, 3, 4, 5]);
    });

    test('every page appears exactly once', () {
      for (final count in [1, 2, 3, 10, 47]) {
        final seen = spreadSlots(count).expand((s) => s).toList();
        expect(seen.length, count, reason: '$count pages');
        expect(seen.toSet().length, count, reason: 'no page twice ($count)');
      }
    });

    test('a single-page chapter is one slot', () {
      expect(spreadSlots(1), [[0]]);
    });

    test('no pages is no slots, not one empty slot', () {
      expect(spreadSlots(0), isEmpty);
    });
  });

  group('switching mid-chapter', () {
    test('the reader lands on the slot holding the page being read', () {
      // Jumping to the page index would land at slot 40 of 20 — the two count
      // different things.
      final slots = spreadSlots(20);
      for (var page = 0; page < 20; page++) {
        final slot = slotForPage(page);
        expect(slot, lessThan(slots.length), reason: 'page $page');
        expect(slots[slot].contains(page), isTrue, reason: 'page $page');
      }
    });

    test('page zero is slot zero', () {
      expect(slotForPage(0), 0);
    });
  });
}
