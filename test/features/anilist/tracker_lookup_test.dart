// Giving up on a title has to be the catalogue's decision, not the network's.
//
// Both trackers cache "this title has no match" in an `_autoMatchFailed` set
// that is consulted before any lookup is attempted — a good optimisation, since
// otherwise every episode of an unmatchable show pays for the same hopeless
// search. The bug was what went into it: the matcher returned `null` both when
// the catalogue answered with nothing AND when the request never landed, so one
// failed lookup on a train stopped that title auto-linking for the life of the
// process, long after the connection came back.
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/anilist/domain/entities/tracker_lookup.dart';

void main() {
  group('a lookup says why it found nothing', () {
    test('a match is a match', () {
      const found = TrackerLookup<int>.found(7);
      expect(found.value, 7);
      expect(found.answered, isTrue);
      expect(
        found.isSettledMiss,
        isFalse,
        reason: 'a hit is not a miss of any kind',
      );
    });

    test('an answer of "nothing like this" is worth remembering', () {
      const miss = TrackerLookup<int>.noMatch();
      expect(miss.value, isNull);
      expect(miss.answered, isTrue);
      expect(miss.isSettledMiss, isTrue);
    });

    test('a request that never landed is not', () {
      // The whole point. Identical `value`, opposite meaning.
      const down = TrackerLookup<int>.unreachable();
      expect(down.value, isNull);
      expect(down.answered, isFalse);
      expect(
        down.isSettledMiss,
        isFalse,
        reason:
            'recording this as hopeless is what made an offline moment '
            'permanent',
      );
    });
  });

  group('mapping keeps the reason', () {
    test('an unreachable lookup stays unreachable through a map', () {
      // MAL maps an AniList result to its `idMal`. A missing counterpart and an
      // unanswered request would otherwise arrive at the same place.
      final mapped = const TrackerLookup<int>.unreachable().map((v) => '$v');
      expect(mapped.answered, isFalse);
      expect(mapped.isSettledMiss, isFalse);
    });

    test('a hit whose mapping is absent is a settled miss', () {
      // AniList answered and knows the title; it simply has no MAL id for it.
      // That IS a fact about the title, so it may be remembered.
      final mapped = const TrackerLookup<int>.found(7).map<String>((_) => null);
      expect(mapped.answered, isTrue);
      expect(mapped.isSettledMiss, isTrue);
    });

    test('and a hit whose mapping lands carries the value over', () {
      final mapped = const TrackerLookup<int>.found(7).map((v) => v * 2);
      expect(mapped.value, 14);
      expect(mapped.isSettledMiss, isFalse);
    });

    test('a settled miss stays settled', () {
      final mapped = const TrackerLookup<int>.noMatch().map((v) => '$v');
      expect(mapped.answered, isTrue);
      expect(mapped.isSettledMiss, isTrue);
    });
  });
}
