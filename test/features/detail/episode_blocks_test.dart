import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/detail/domain/episode_blocks.dart';

void main() {
  List<String> labels(List<EpisodeBlock> blocks) =>
      [for (final b in blocks) b.label];

  group('when there is nothing to jump over', () {
    test('a single page produces no blocks', () {
      // A strip with one chip on it is decoration over a list that is already
      // entirely on screen.
      expect(
        episodeBlocks(total: 12, size: 50, descending: false, firstNumber: 1),
        isEmpty,
      );
      expect(
        episodeBlocks(total: 50, size: 50, descending: false, firstNumber: 1),
        isEmpty,
        reason: 'exactly one full page is still one page',
      );
    });

    test('nonsense input produces nothing rather than throwing', () {
      expect(episodeBlocks(total: 0, size: 50, descending: false, firstNumber: 1), isEmpty);
      expect(episodeBlocks(total: 100, size: 0, descending: false, firstNumber: 1), isEmpty);
    });
  });

  group('ascending', () {
    test('blocks run in reading order and cover the whole series', () {
      final blocks =
          episodeBlocks(total: 120, size: 50, descending: false, firstNumber: 1);
      expect(labels(blocks), ['1–50', '51–100', '101–120']);
      expect([for (final b in blocks) b.page], [1, 2, 3]);
    });

    test('the last block stops at the last episode, not at a round number', () {
      // Labelling the tail "101–150" on a 120-episode run puts thirty numbers
      // on a chip that has nothing behind them.
      final blocks =
          episodeBlocks(total: 120, size: 50, descending: false, firstNumber: 1);
      expect(blocks.last.to, 120);
    });
  });

  group('descending', () {
    test('blocks count down, matching the rows underneath them', () {
      // The shape the feature was built for: One Piece, newest first.
      final blocks =
          episodeBlocks(total: 1176, size: 50, descending: true, firstNumber: 1);
      expect(labels(blocks).take(4), ['1176–1127', '1126–1077', '1076–1027', '1026–977']);
    });

    test('the final block ends on the first episode', () {
      final blocks =
          episodeBlocks(total: 1176, size: 50, descending: true, firstNumber: 1);
      expect(blocks.last.to, 1, reason: 'the run ends where it starts');
      expect(blocks.length, 24);
    });

    test('a label never runs the opposite way to its list', () {
      final blocks =
          episodeBlocks(total: 300, size: 50, descending: true, firstNumber: 1);
      for (final b in blocks) {
        expect(b.from, greaterThanOrEqualTo(b.to),
            reason: 'descending blocks read high to low');
      }
    });
  });

  group('runs that do not start at 1', () {
    test('numbering from 0 is respected', () {
      // Several sources put a pilot or a recap at episode 0. Labelling from 1
      // would print a number that appears nowhere in the list.
      final blocks =
          episodeBlocks(total: 100, size: 50, descending: false, firstNumber: 0);
      expect(labels(blocks), ['0–49', '50–99']);
    });

    test('absolute numbering mid-series is respected', () {
      // A season carrying absolute numbers: episodes 201 onward.
      final blocks =
          episodeBlocks(total: 120, size: 50, descending: false, firstNumber: 201);
      expect(labels(blocks), ['201–250', '251–300', '301–320']);
    });

    test('descending absolute numbering ends on the real first episode', () {
      final blocks =
          episodeBlocks(total: 120, size: 50, descending: true, firstNumber: 201);
      expect(blocks.first.from, 320);
      expect(blocks.last.to, 201);
    });
  });

  group('block boundaries', () {
    test('every episode falls in exactly one block', () {
      // The property that matters: no gap means no episode is unreachable, and
      // no overlap means no chip lies about what it holds.
      for (final desc in [false, true]) {
        final blocks =
            episodeBlocks(total: 237, size: 50, descending: desc, firstNumber: 1);
        final covered = <int>{};
        for (final b in blocks) {
          final lo = b.from < b.to ? b.from : b.to;
          final hi = b.from < b.to ? b.to : b.from;
          for (var n = lo; n <= hi; n++) {
            expect(covered.add(n), isTrue, reason: '$n is in two blocks (desc=$desc)');
          }
        }
        expect(covered.length, 237, reason: 'every episode is reachable (desc=$desc)');
      }
    });

    test('a single trailing episode reads as one number, not a range', () {
      final blocks =
          episodeBlocks(total: 101, size: 50, descending: false, firstNumber: 1);
      expect(blocks.last.label, '101');
    });
  });
}
