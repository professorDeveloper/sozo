import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/detail/domain/services/auto_resolve_walk.dart';

class _C {
  const _C(this.id, {this.trusted = true});
  final String id;
  final bool trusted;
}

AutoResolveWalk<_C, String> _walk(
  List<_C> list,
  Future<AutoAttempt<String>> Function(_C) attempt, {
  bool Function()? searching,
  int cap = AutoResolveWalk.maxCandidates,
  void Function()? onChange,
}) => AutoResolveWalk<_C, String>(
  candidates: () => list,
  searching: searching ?? () => false,
  idOf: (c) => c.id,
  isEligible: (c) => c.trusted,
  attempt: attempt,
  cap: cap,
  poll: const Duration(milliseconds: 1),
  onChange: onChange,
);

void main() {
  test('returns the first candidate that plays, in list order', () async {
    final tried = <String>[];
    final walk = _walk([const _C('a'), const _C('b'), const _C('c')], (c) async {
      tried.add(c.id);
      return c.id == 'b'
          ? AutoAttempt.found('args-b')
          : AutoAttempt.skipped(AutoSkipReason.noEpisode);
    });
    final result = await walk.run();
    expect(result.end, AutoWalkEnd.found);
    expect(result.value, 'args-b');
    expect(tried, ['a', 'b']);
    expect(walk.skipped.single.candidate.id, 'a');
    expect(walk.skipped.single.reason, AutoSkipReason.noEpisode);
  });

  test('records why each source was skipped', () async {
    final walk = _walk(
      [const _C('a'), const _C('b'), const _C('weak', trusted: false)],
      (c) async {
        if (c.id == 'a') return AutoAttempt.skipped(AutoSkipReason.noEpisode);
        throw StateError('network');
      },
    );
    final result = await walk.run();
    expect(result.end, AutoWalkEnd.exhausted);
    expect([for (final s in walk.skipped) (s.candidate.id, s.reason)], [
      ('a', AutoSkipReason.noEpisode),
      ('b', AutoSkipReason.error),
      ('weak', AutoSkipReason.noMatch),
    ]);
  });

  test('never tries a candidate that is not trustworthy', () async {
    final tried = <String>[];
    final walk = _walk([const _C('weak', trusted: false)], (c) async {
      tried.add(c.id);
      return AutoAttempt.found(c.id);
    });
    expect((await walk.run()).end, AutoWalkEnd.exhausted);
    expect(tried, isEmpty);
  });

  test('stops after the cap', () async {
    final list = [for (var i = 0; i < 30; i++) _C('$i')];
    var calls = 0;
    final walk = _walk(list, (c) async {
      calls++;
      return AutoAttempt.skipped(AutoSkipReason.error);
    });
    final result = await walk.run();
    expect(result.end, AutoWalkEnd.capped);
    expect(calls, AutoResolveWalk.maxCandidates);
    expect(walk.index, 20);
    expect(walk.total, 20);
  });

  test('counts i of total, and the total grows as results arrive', () async {
    final list = <_C>[const _C('a')];
    var searching = true;
    final seen = <(int, int)>[];
    late final AutoResolveWalk<_C, String> walk;
    walk = _walk(
      list,
      (c) async {
        seen.add((walk.index, walk.total));
        if (c.id == 'a') {
          list.addAll([const _C('b'), const _C('c')]);
        }
        if (c.id == 'c') searching = false;
        return AutoAttempt.skipped(AutoSkipReason.noEpisode);
      },
      searching: () => searching,
    );
    final result = await walk.run();
    expect(result.end, AutoWalkEnd.exhausted);
    expect(seen, [(1, 1), (2, 3), (3, 3)]);
  });

  test('waits for more results while search is still running', () async {
    final list = <_C>[];
    var searching = true;
    final walk = _walk(
      list,
      (c) async => AutoAttempt.found(c.id),
      searching: () => searching,
    );
    final running = walk.run();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(walk.current, isNull);
    list.add(const _C('late'));
    searching = false;
    final result = await running;
    expect(result.end, AutoWalkEnd.found);
    expect(result.value, 'late');
  });

  test('stop ends the walk at once and ignores the result in flight', () async {
    final pending = Completer<AutoAttempt<String>>();
    final walk = _walk([const _C('a'), const _C('b')], (_) => pending.future);
    final running = walk.run();
    await Future<void>.delayed(Duration.zero);
    expect(walk.current?.id, 'a');

    walk.stop();
    final result = await running;
    expect(result.end, AutoWalkEnd.stopped);
    expect(result.value, isNull);
    expect(walk.current, isNull);

    // The answer that lands afterwards changes nothing.
    pending.complete(AutoAttempt.found('too late'));
    await Future<void>.delayed(Duration.zero);
    expect(walk.skipped, isEmpty);
    expect(walk.index, 1);
  });

  test('stop while waiting for search ends the walk too', () async {
    final walk = _walk(
      [],
      (c) async => AutoAttempt.found(c.id),
      searching: () => true,
    );
    final running = walk.run();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    walk.stop();
    expect((await running).end, AutoWalkEnd.stopped);
  });

  test('an error after stop is swallowed', () async {
    final pending = Completer<AutoAttempt<String>>();
    final walk = _walk([const _C('a')], (_) => pending.future);
    final running = walk.run();
    await Future<void>.delayed(Duration.zero);
    walk.stop();
    expect((await running).end, AutoWalkEnd.stopped);
    pending.completeError(StateError('late failure'));
    await Future<void>.delayed(Duration.zero);
  });

  test('tells the caller when its state changes', () async {
    var changes = 0;
    final walk = _walk(
      [const _C('a')],
      (c) async => AutoAttempt.skipped(AutoSkipReason.error),
      onChange: () => changes++,
    );
    await walk.run();
    expect(changes, greaterThanOrEqualTo(3));
  });
}
