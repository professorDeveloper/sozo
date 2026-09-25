// The background check: counts from the snapshot and from its own earlier
// finds, a seed for a title never counted, a notification only for what is
// new and wanted.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/detail/domain/entities/episode_entity.dart';
import 'package:soplay/features/notifications/data/notification_prefs.dart';
import 'package:soplay/features/notifications/data/release_notifier.dart';
import 'package:soplay/features/tracker/data/release_inbox.dart';
import 'package:soplay/features/tracker/data/release_worker.dart';

class _Probe implements EpisodeProbe {
  _Probe(this.newest_);
  final Map<String, int> newest_;

  @override
  Future<EpisodeEntity?> newest(String provider, String contentUrl) async {
    final n = newest_[contentUrl];
    return n == null ? null : EpisodeEntity(episode: n, label: '$n', mediaRef: '');
  }

  @override
  Future<void> close() async {}
}

class _Notifier implements ReleaseNotifier {
  final shown = <ReleaseAlert>[];

  @override
  Future<void> showRelease(
    ReleaseAlert alert,
    NotificationLabels labels, {
    bool quiet = false,
  }) async => shown.add(alert);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory dir;
  late ReleaseInbox inbox;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('sozo_release_inbox');
    inbox = ReleaseInbox(dir);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> snapshot(List<WatchedTitle> titles, {NotificationPrefs? prefs}) =>
      inbox.writeSnapshot(
        ReleaseWatchSnapshot(
          titles: titles,
          prefs: prefs ?? const NotificationPrefs(),
          scope: 'kid',
        ),
      );

  test('grown titles are posted and announced; muted ones only posted', () async {
    await snapshot([
      const WatchedTitle(provider: 'cs:a', contentUrl: 'a', title: 'A', count: 10),
      const WatchedTitle(
        provider: 'cs:a',
        contentUrl: 'b',
        title: 'B',
        count: 3,
        notify: false,
      ),
      const WatchedTitle(provider: 'cs:a', contentUrl: 'c', title: 'C', count: 7),
    ]);
    final notifier = _Notifier();
    final found = await ReleaseWorker(
      inbox: inbox,
      probe: _Probe({'a': 12, 'b': 4, 'c': 7}),
      now: () => DateTime(2026, 9, 24, 12),
    ).run(notifier: notifier);

    expect(found.map((e) => e.contentUrl), unorderedEquals(['a', 'b']));
    expect(notifier.shown.single.contentUrl, 'a');
    expect(notifier.shown.single.count, 2);
    final posted = inbox.drain();
    expect(posted.firstWhere((e) => e.contentUrl == 'a').fromEpisode, 11);
    expect(posted.every((e) => e.scope == 'kid'), isTrue);
  });

  test('a title never counted is seeded, not announced', () async {
    await snapshot([
      const WatchedTitle(provider: 'cs:a', contentUrl: 'a', title: 'A'),
    ]);
    final notifier = _Notifier();
    await ReleaseWorker(inbox: inbox, probe: _Probe({'a': 40})).run(notifier: notifier);
    expect(notifier.shown, isEmpty);
    expect(inbox.drain().single.seedOnly, isTrue);
  });

  test('a find the app has not taken yet is not announced twice', () async {
    await snapshot([
      const WatchedTitle(provider: 'cs:a', contentUrl: 'a', title: 'A', count: 10),
    ]);
    final probe = _Probe({'a': 11});
    final first = _Notifier();
    await ReleaseWorker(inbox: inbox, probe: probe).run(notifier: first);
    final second = _Notifier();
    await ReleaseWorker(inbox: inbox, probe: probe).run(notifier: second);
    expect(first.shown, hasLength(1));
    expect(second.shown, isEmpty);
  });

  test('quiet hours and a switched-off type hold notifications back', () async {
    const titles = [
      WatchedTitle(provider: 'cs:a', contentUrl: 'a', title: 'A', count: 1),
    ];
    await snapshot(
      titles,
      prefs: const NotificationPrefs(
        quiet: QuietHours(enabled: true, from: 22 * 60, to: 8 * 60),
      ),
    );
    final quiet = _Notifier();
    final found = await ReleaseWorker(
      inbox: inbox,
      probe: _Probe({'a': 2}),
      now: () => DateTime(2026, 9, 24, 3),
    ).run(notifier: quiet);
    expect(found, hasLength(1));
    expect(quiet.shown, isEmpty);

    inbox.drain();
    await snapshot(
      titles,
      prefs: const NotificationPrefs().withCategory(
        NotificationCategory.releases,
        false,
      ),
    );
    final off = _Notifier();
    await ReleaseWorker(inbox: inbox, probe: _Probe({'a': 2})).run(notifier: off);
    expect(off.shown, isEmpty);
  });

  test('no snapshot, no work', () async {
    expect(await ReleaseWorker(inbox: inbox, probe: _Probe({})).run(), isEmpty);
  });
}
