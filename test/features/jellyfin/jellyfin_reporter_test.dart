import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/jellyfin/data/jellyfin_bridge.dart';
import 'package:soplay/features/jellyfin/data/jellyfin_reporter.dart';
import 'package:soplay/features/jellyfin/data/jellyfin_server_store.dart';

import 'jellyfin_fakes.dart';

void main() {
  const url =
      'http://nas:8096/Videos/item1/stream.mkv?static=true&ApiKey=tok123';
  late FakeJellyfinAdapter adapter;
  late JellyfinReporter reporter;
  late DateTime now;
  var incognito = false;

  Future<void> settle() => pumpEventQueue();

  List<String> paths() => [for (final r in adapter.requests) r.uri.path];

  setUp(() async {
    adapter = FakeJellyfinAdapter({
      '/Sessions/Playing': (_) => 204,
      '/Sessions/Playing/Progress': (_) => 204,
      '/Sessions/Playing/Stopped': (_) => 204,
    });
    final JellyfinServerStore store = await storeWith([testServer]);
    final api = fakeApi(adapter);
    final bridge = JellyfinBridge(api: api, store: store, label: (k) => k)
      ..remember(
        const JellyfinPlaySession(
          serverId: 'srv1',
          itemId: 'item1',
          mediaSourceId: 'item1',
          playSessionId: 'ps1',
          resumeAt: Duration(minutes: 3),
        ),
      );
    now = DateTime(2026, 9, 24, 20);
    incognito = false;
    reporter = JellyfinReporter(
      bridge: bridge,
      api: api,
      store: store,
      suppressed: () => incognito,
      clock: () => now,
    );
  });

  test('starts once, then throttles progress to every ten seconds', () async {
    reporter.progress(url: url, position: const Duration(seconds: 5));
    now = now.add(const Duration(seconds: 5));
    reporter.progress(url: url, position: const Duration(seconds: 10));
    now = now.add(const Duration(seconds: 5));
    reporter.progress(url: url, position: const Duration(seconds: 15));
    await settle();

    expect(paths(), ['/Sessions/Playing', '/Sessions/Playing/Progress']);
    final start = adapter.requests.first.data as Map;
    expect(start['ItemId'], 'item1');
    expect(start['PlaySessionId'], 'ps1');
    expect(start['PositionTicks'], 50000000);
    expect(start['PlayMethod'], 'DirectPlay');
    final progress = adapter.requests.last.data as Map;
    expect(progress['PositionTicks'], 150000000);
    expect(progress['EventName'], 'TimeUpdate');
  });

  test('a pause is reported at once', () async {
    reporter.progress(url: url, position: const Duration(seconds: 5));
    reporter.progress(
      url: url,
      position: const Duration(seconds: 6),
      paused: true,
    );
    await settle();
    final pause = adapter.requests.last.data as Map;
    expect(pause['IsPaused'], isTrue);
    expect(pause['EventName'], 'Pause');
  });

  test('stop closes the session and flags a failure', () async {
    reporter.progress(url: url, position: const Duration(seconds: 5));
    reporter.stop(url: url, position: const Duration(seconds: 7), failed: true);
    reporter.stop(url: url, position: const Duration(seconds: 7));
    await settle();
    expect(paths(), ['/Sessions/Playing', '/Sessions/Playing/Stopped']);
    final stop = adapter.requests.last.data as Map;
    expect(stop['Failed'], isTrue);
    expect(stop['PositionTicks'], 70000000);
    expect(reporter.isLive('ps1'), isFalse);
  });

  test('a stream that never started is not stopped', () async {
    reporter.stop(url: url, position: Duration.zero);
    await settle();
    expect(adapter.requests, isEmpty);
  });

  test('incognito sends nothing', () async {
    incognito = true;
    reporter.progress(url: url, position: const Duration(seconds: 5));
    reporter.stop(url: url, position: const Duration(seconds: 6));
    await settle();
    expect(adapter.requests, isEmpty);
  });

  test('other sources and unknown streams are ignored', () async {
    reporter.progress(
      url: 'https://cdn.example.com/video.m3u8',
      position: const Duration(seconds: 5),
    );
    await settle();
    expect(adapter.requests, isEmpty);
    expect(reporter.resumeFor(url), const Duration(minutes: 3));
    expect(reporter.resumeFor('https://cdn.example.com/x.mp4'), Duration.zero);
  });

  test('a failed report never throws into playback', () async {
    adapter.routes['/Sessions/Playing'] = (_) => 500;
    reporter.progress(url: url, position: const Duration(seconds: 5));
    await settle();
    expect(paths(), ['/Sessions/Playing']);
  });
}
