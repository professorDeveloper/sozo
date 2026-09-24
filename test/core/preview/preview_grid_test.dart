// The seek-bar grid: dense enough for any length, filled around the playhead
// early, and kept on disk per episode so an episode opened again has its
// frames from the first touch.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/preview/frame_preview_service.dart';

void main() {
  group('how many frames', () {
    test('about one every 20 seconds on Wi-Fi, within bounds', () {
      const min = 60 * 1000;
      expect(FramePreviewService.gridCount(24 * min, metered: false), 72);
      expect(FramePreviewService.gridCount(10 * min, metered: false), 40);
      expect(
        FramePreviewService.gridCount(150 * min, metered: false),
        FramePreviewSession.maxGridFrames,
      );
    });

    test('few on mobile data, where each costs a segment', () {
      expect(FramePreviewService.gridCount(24 * 60000, metered: true), 16);
    });
  });

  group('in what order', () {
    test('the coarse pass, then the playhead, then the rest', () {
      final order = FramePreviewService.gridOrder(40, near: 21);
      expect(order.take(5), [0, 8, 16, 24, 32]);
      // Around the playhead next — 21 and its neighbours.
      expect(order.skip(5).take(3), [21, 22, 20]);
      // Every point exactly once.
      expect(order.toSet(), hasLength(40));
      expect(order, hasLength(40));
    });

    test('without a playhead it is coarse to fine', () {
      final order = FramePreviewService.gridOrder(16);
      expect(order.take(4), [0, 8, 4, 12]);
      expect(order.toSet(), hasLength(16));
    });
  });

  group('on disk', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('sozo_preview_grid_');
      PreviewDiskCache.debugRoot = root;
    });

    tearDown(() async {
      PreviewDiskCache.debugRoot = null;
      await root.delete(recursive: true);
    });

    FramePreviewSession session(List<int> decoded) => FramePreviewSession(
      supported: true,
      invoke: (method, args) async {
        if (method != 'frame') return true;
        final pos = args!['posMs'] as int;
        decoded.add(pos);
        return Uint8List.fromList([pos ~/ 1000 % 256]);
      },
    );

    Future<void> flush() =>
        Future<void>.delayed(const Duration(milliseconds: 50));

    // The frame is written in the background; under a loaded test run 50 ms
    // is not always long enough, so wait for it rather than for a guess.
    Future<void> saved(String key) async {
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while ((await PreviewDiskCache.load(key)).isEmpty &&
          DateTime.now().isBefore(deadline)) {
        await flush();
      }
    }

    test('an episode opened again has its frames without decoding', () async {
      final first = <int>[];
      final a = session(first);
      await a.open('https://cdn.example/signed?t=1', {});
      await a.attachDisk('prov|show|3');
      expect(await a.gridFrame(60000), isTrue);
      expect(first, [60000]);
      await saved('prov|show|3');
      await a.close();

      // Another session, another signed address, the same episode.
      final second = <int>[];
      final b = session(second);
      await b.open('https://cdn.example/signed?t=2', {});
      await b.attachDisk('prov|show|3');
      expect(b.hasGridFrame(60000), isTrue);
      expect(await b.frame(61000), [60]);
      expect(second, isEmpty);
      await b.close();
    });

    test('another episode does not see them', () async {
      final a = session([]);
      await a.open('https://cdn.example/a', {});
      await a.attachDisk('prov|show|3');
      await a.gridFrame(60000);
      await flush();
      final b = session([]);
      await b.open('https://cdn.example/b', {});
      await b.attachDisk('prov|show|4');
      expect(b.hasGridFrame(60000), isFalse);
      await a.close();
      await b.close();
    });

    test('only the most recent episodes are kept', () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      for (var i = 0; i < PreviewDiskCache.maxEpisodes + 4; i++) {
        await PreviewDiskCache.save('ep$i', 5000, bytes);
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await flush();
      final dirs = await Directory(
        '${root.path}/preview_grid',
      ).list().where((e) => e is Directory).length;
      expect(dirs, lessThanOrEqualTo(PreviewDiskCache.maxEpisodes));
      // The newest survives.
      expect(
        await PreviewDiskCache.load('ep${PreviewDiskCache.maxEpisodes + 3}'),
        isNotEmpty,
      );
    });
  });
}
