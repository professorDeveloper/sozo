// A tracker write that fails must not be lost.
//
// Playback and reading report to AniList and MyAnimeList fire-and-forget, and
// a write that failed — offline, a 502, a lookup that never answered — used
// to be forgotten with the rest. The outbox keeps it and sends it again, and
// these are the rules it has to keep while doing so.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/features/tracker/data/tracker_outbox.dart';

void main() {
  late Box box;
  var now = 1000000;

  setUpAll(() async {
    Hive.init('${Directory.systemTemp.path}/sozo_tracker_outbox');
    box = await Hive.openBox('sozo_tracker_outbox');
  });

  tearDownAll(() async => Hive.close());

  setUp(() async {
    await box.clear();
    now = 1000000;
  });

  PendingTrackerWrite write(
    int number, {
    String account = '7',
    String url = 'https://example.test/frieren',
  }) => PendingTrackerWrite(
    tracker: 'anilist',
    provider: 'someext',
    contentUrl: url,
    title: 'Frieren',
    number: number,
    account: account,
    queuedAt: now,
  );

  TrackerOutbox outbox({
    required List<TrackerWriteResult> answers,
    List<int>? sent,
    String? Function()? account,
  }) {
    final o = TrackerOutbox(box: box, now: () => now);
    var i = 0;
    o.register(
      'anilist',
      send: (w) async {
        sent?.add(w.number);
        return answers[i++];
      },
      account: account ?? () => '7',
    );
    return o;
  }

  test('a queued write is sent, and gone once it lands', () async {
    final sent = <int>[];
    final o = outbox(answers: [TrackerWriteResult.written], sent: sent);
    await o.queue(write(3));

    expect(await o.flush(), 1);
    expect(sent, [3]);
    expect(o.pending(), isEmpty);
  });

  test('only the furthest number is kept per title', () async {
    final sent = <int>[];
    final o = outbox(answers: [TrackerWriteResult.written], sent: sent);
    await o.queue(write(3));
    await o.queue(write(5));
    await o.queue(write(4));

    expect(o.pending(), hasLength(1));
    await o.flush();
    expect(sent, [5], reason: 'a list holds one number; 3 and 4 are moot');
  });

  test('a write that fails again waits, and is not hammered', () async {
    final sent = <int>[];
    final o = outbox(
      answers: [TrackerWriteResult.failed, TrackerWriteResult.written],
      sent: sent,
    );
    await o.queue(write(2));

    await o.flush();
    expect(o.pending().single.attempts, 1);

    // Straight away again: still backing off, so nothing is sent.
    await o.flush();
    expect(sent, [2]);

    // After the backoff it goes.
    now += const Duration(minutes: 2).inMilliseconds;
    await o.flush();
    expect(sent, [2, 2]);
    expect(o.pending(), isEmpty);
  });

  test('sending on demand ignores the backoff', () async {
    final sent = <int>[];
    final o = outbox(
      answers: [TrackerWriteResult.failed, TrackerWriteResult.written],
      sent: sent,
    );
    await o.queue(write(2));
    await o.flush();
    await o.flush(force: true);
    expect(sent, [2, 2]);
  });

  test('nothing to write is not a failure: it is dropped', () async {
    final o = outbox(answers: [TrackerWriteResult.skipped]);
    await o.queue(write(2));
    expect(await o.flush(), 0);
    expect(o.pending(), isEmpty);
  });

  test('a write is never sent to a different account', () async {
    final sent = <int>[];
    final o = outbox(answers: [], sent: sent, account: () => '99');
    await o.queue(write(2, account: '7'));
    await o.flush();
    expect(sent, isEmpty);
    expect(o.pending(), isEmpty, reason: 'it was never this account\'s');
  });

  test('while nobody is connected it is kept, not dropped', () async {
    final o = outbox(answers: [], account: () => null);
    await o.queue(write(2));
    await o.flush();
    expect(o.pending(), hasLength(1));
  });

  test('a month-old write is given up', () async {
    final sent = <int>[];
    final o = outbox(answers: [], sent: sent);
    await o.queue(write(2));
    now += const Duration(days: 31).inMilliseconds;
    await o.flush();
    expect(sent, isEmpty);
    expect(o.pending(), isEmpty);
  });

  test('disconnecting a tracker drops only its own writes', () async {
    final o = outbox(answers: []);
    await o.queue(write(2));
    await o.queue(
      const PendingTrackerWrite(
        tracker: 'mal',
        provider: 'someext',
        contentUrl: 'https://example.test/frieren',
        title: 'Frieren',
        number: 2,
        account: '1',
        queuedAt: 1000000,
      ),
    );
    await o.discard('anilist');
    expect(o.pending().map((w) => w.tracker), ['mal']);
  });

  test('it survives a restart', () async {
    final first = outbox(answers: []);
    await first.queue(write(6));
    final second = outbox(answers: [TrackerWriteResult.written]);
    expect(second.pending().single.number, 6);
  });
}
