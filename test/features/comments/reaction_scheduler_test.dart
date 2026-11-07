import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/comments/domain/timed_reactions.dart';

ReactionBucket _b(int t, List<(String, int)> items) => ReactionBucket(
  t: t,
  total: items.fold(0, (n, i) => n + i.$2),
  items: [
    for (final i in items) ReactionItem(kind: 'emoji', value: i.$1, count: i.$2),
  ],
);

Duration _s(int s) => Duration(seconds: s);

/// Plays from [from] to [to] a second at a time, as the position listener
/// would, and returns what is on screen at [to].
List<ReactionPop> _play(ReactionScheduler s, int from, int to) {
  var out = const <ReactionPop>[];
  for (var t = from; t <= to; t++) {
    out = s.at(_s(t));
  }
  return out;
}

void main() {
  test('a reaction shows from its second for the window, then goes', () {
    final s = ReactionScheduler()
      ..load(ReactionTimeline([_b(10, [('🔥', 1)])]));
    expect(_play(s, 0, 9), isEmpty);
    expect(s.at(_s(10)).single.value, '🔥');
    expect(s.at(_s(13)), hasLength(1));
    expect(s.at(_s(14)), isEmpty);
  });

  test('the same emoji in the window groups into one pill with a count', () {
    final s = ReactionScheduler()
      ..load(
        ReactionTimeline([
          _b(10, [('🔥', 5)]),
          _b(11, [('🔥', 7), ('😂', 1)]),
        ]),
      );
    final pops = _play(s, 9, 11);
    expect(pops.first.value, '🔥');
    expect(pops.first.count, 12);
    expect(pops.first.lastSec, 11);
    expect(pops[1].value, '😂');
  });

  test('no more than maxVisible, the most-sent first', () {
    final s = ReactionScheduler(maxVisible: 2)
      ..load(
        ReactionTimeline([
          _b(5, [('😢', 1), ('🔥', 9), ('😂', 4), ('👏', 2)]),
        ]),
      );
    final pops = _play(s, 4, 5);
    expect(pops.map((p) => p.value), ['🔥', '😂']);
  });

  test('after a seek forward nothing from before the landing point bursts in',
      () {
    final s = ReactionScheduler()
      ..load(
        ReactionTimeline([
          _b(98, [('😮', 3)]),
          _b(101, [('🔥', 1)]),
        ]),
      );
    _play(s, 0, 5);
    expect(s.at(_s(100)), isEmpty, reason: 'landed after 98; it stays unseen');
    expect(s.at(_s(101)).single.value, '🔥');
  });

  test('after a seek back reactions replay from the new position', () {
    final s = ReactionScheduler()
      ..load(ReactionTimeline([_b(20, [('👏', 2)])]));
    _play(s, 18, 30);
    expect(s.at(_s(19)), isEmpty);
    expect(s.at(_s(20)).single.count, 2);
  });

  test('landing exactly on a reaction shows it', () {
    final s = ReactionScheduler()
      ..load(ReactionTimeline([_b(50, [('💀', 1)])]));
    _play(s, 0, 3);
    expect(s.at(_s(50)).single.value, '💀');
  });

  test('normal ticks within the jump tolerance are playback, not a seek', () {
    final s = ReactionScheduler()
      ..load(ReactionTimeline([_b(10, [('🔥', 1)])]));
    s.at(_s(10));
    s.at(const Duration(seconds: 11, milliseconds: 500));
    expect(s.at(_s(13)).single.value, '🔥');
  });

  test('clear forgets the timeline and the playhead', () {
    final s = ReactionScheduler()
      ..load(ReactionTimeline([_b(1, [('🔥', 1)])]));
    s.clear();
    expect(s.at(_s(1)), isEmpty);
  });

  test('the viewer\'s own reaction is added at its second', () {
    final t = ReactionTimeline([_b(10, [('🔥', 2)])])
        .withReaction(10, 'emoji', '🔥')
        .withReaction(4, 'text', 'no way');
    expect(t.buckets.map((b) => b.t), [4, 10]);
    expect(t.buckets[1].items.single.count, 3);
    expect(t.buckets[1].total, 3);
    expect(t.buckets[0].items.single.kind, 'text');
  });

  test('the heatmap scales the busiest slice to one', () {
    final t = ReactionTimeline([
      _b(0, [('🔥', 2)]),
      _b(50, [('🔥', 8)]),
      _b(99, [('🔥', 4)]),
    ]);
    final bins = t.heatmap(100, bins: 10);
    expect(bins, hasLength(10));
    expect(bins[5], 1.0);
    expect(bins[0], 0.25);
    expect(bins[9], 0.5);
    expect(bins[3], 0);
    expect(ReactionTimeline.empty.heatmap(0), everyElement(0));
  });

  test('parses the server shape', () {
    final t = ReactionTimeline.fromJson({
      'total': 3,
      'buckets': [
        {
          't': 7,
          'total': 3,
          'items': [
            {'kind': 'emoji', 'value': '🔥', 'count': 2},
            {'kind': 'text', 'value': 'wow', 'count': 1},
          ],
        },
      ],
    });
    expect(t.buckets.single.t, 7);
    expect(t.buckets.single.items.last.value, 'wow');
  });
}
