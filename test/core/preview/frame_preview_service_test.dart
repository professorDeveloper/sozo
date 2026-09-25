import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/preview/frame_preview_service.dart';

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  test(
    'configure stays idle, first frame has no warm decode or neighbor prefetch',
    () async {
      final calls = <(String, Map<String, dynamic>?)>[];
      final session = FramePreviewSession(
        supported: true,
        invoke: (method, args) async {
          calls.add((method, args));
          return method == 'frame' ? Uint8List.fromList([1]) : true;
        },
      );
      await session.open('https://media.example/4k.mp4', {});
      expect(calls, isEmpty);
      expect(await session.frame(12000), [1]);
      await settle();
      expect(calls.map((e) => e.$1).toList(), ['open', 'frame']);
      expect(calls.first.$2!['warmMs'], -1);
      expect(calls.last.$2!['posMs'], 10000);
      await session.endScrub();
      final count = calls.length;
      expect(await session.frame(12000), [1]);
      expect(
        calls.length,
        count,
        reason: 'Repeated cached scrubs need no decoder',
      );
      await session.close();
    },
  );

  test(
    'deduplicates requested bucket and keeps only latest queued position',
    () async {
      final frames = <int>[];
      final first = Completer<Uint8List>();
      final session = FramePreviewSession(
        supported: true,
        invoke: (method, args) async {
          if (method != 'frame') return true;
          final bucket = args!['posMs'] as int;
          frames.add(bucket);
          return frames.length == 1 ? first.future : Uint8List.fromList([2]);
        },
      );
      await session.open('https://media.example/video.mp4', {});
      final a = session.frame(1000);
      final same = session.frame(4000);
      final superseded = session.frame(6000);
      final latest = session.frame(11000);
      await settle();
      expect(await superseded, isNull);
      expect(frames, [0]);
      first.complete(Uint8List.fromList([1]));
      expect(await a, [1]);
      expect(await same, [1]);
      expect(await latest, [2]);
      expect(frames, [0, 10000]);
      await session.close();
    },
  );

  test(
    'source change discards late old frames and uses newer close/open tokens',
    () async {
      final calls = <(String, Map<String, dynamic>?)>[];
      final old = Completer<Uint8List>();
      var frameCalls = 0;
      final session = FramePreviewSession(
        supported: true,
        invoke: (method, args) async {
          calls.add((method, args));
          if (method != 'frame') return true;
          return ++frameCalls == 1 ? old.future : Uint8List.fromList([9]);
        },
      );
      await session.open('https://media.example/a.mp4', {});
      final a = session.frame(0);
      await settle();
      final b = session.previewFrame('https://media.example/b.mp4', {}, 0);
      await settle();
      expect(await a, isNull);
      old.complete(Uint8List.fromList([1]));
      expect(await b, [9]);
      expect(await session.frame(0), [9]);
      final close =
          calls.firstWhere((e) => e.$1 == 'close').$2!['generation'] as int;
      final newest =
          calls.lastWhere((e) => e.$1 == 'open').$2!['generation'] as int;
      expect(newest, greaterThan(close));
      await session.close();
    },
  );

  test(
    'same URL with changed headers reopens and invalidates image cache',
    () async {
      final opened = <Map<String, dynamic>>[];
      final session = FramePreviewSession(
        supported: true,
        invoke: (method, args) async {
          if (method == 'open') opened.add(args!);
          return method == 'frame' ? Uint8List.fromList([opened.length]) : true;
        },
      );
      expect(
        await session.previewFrame('https://media.example/video', {
          'Authorization': 'a',
        }, 0),
        [1],
      );
      expect(
        await session.previewFrame('https://media.example/video', {
          'Authorization': 'b',
        }, 0),
        [2],
      );
      expect(opened.length, 2);
      await session.close();
    },
  );

  test('cache is bounded by frame count and by JPEG bytes', () async {
    for (final byteLimit in [100, 3]) {
      final positions = <int>[];
      final session = FramePreviewSession(
        supported: true,
        maxFrames: 2,
        maxCacheBytes: byteLimit,
        invoke: (method, args) async {
          if (method != 'frame') return true;
          positions.add(args!['posMs'] as int);
          return Uint8List.fromList([1, 2]);
        },
      );
      await session.open('https://media.example/video', {});
      await session.frame(0);
      await session.frame(5000);
      if (byteLimit == 100) await session.frame(10000);
      await session.frame(0);
      expect(positions.where((p) => p == 0).length, 2);
      await session.close();
    }
  });

  testWidgets(
    'idle decoder is released without a caller needing explicit close',
    (tester) async {
      final calls = <String>[];
      final session = FramePreviewSession(
        supported: true,
        idleTimeout: const Duration(milliseconds: 100),
        invoke: (method, args) async {
          calls.add(method);
          return method == 'frame' ? Uint8List(1) : true;
        },
      );
      await session.open('https://media.example/video', {});
      final frame = session.frame(0);
      await tester.pump();
      await frame;
      await tester.pump(const Duration(milliseconds: 101));
      expect(calls, ['open', 'frame', 'close']);
      await session.close();
    },
  );

  testWidgets('timeout invalidates late work and releases native resources', (
    tester,
  ) async {
    final calls = <String>[];
    final blocked = Completer<dynamic>();
    final session = FramePreviewSession(
      supported: true,
      openTimeout: const Duration(milliseconds: 10),
      invoke: (method, args) {
        calls.add(method);
        return method == 'open' ? blocked.future : Future.value(true);
      },
    );
    await session.open('https://media.example/video', {});
    final frame = session.frame(0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 11));
    expect(await frame, isNull);
    expect(calls, ['open', 'close']);
    blocked.complete(true);
    await tester.pump();
    expect(calls.where((call) => call == 'frame'), isEmpty);
    await session.close();
  });

  group('the background grid', () {
    FramePreviewSession session({List<int>? frames, Completer<void>? hold}) =>
        FramePreviewSession(
          supported: true,
          invoke: (method, args) async {
            if (method != 'frame') return true;
            final pos = args!['posMs'] as int;
            frames?.add(pos);
            if (hold != null) await hold.future;
            return Uint8List.fromList([pos ~/ 1000 % 256]);
          },
        );

    test(
      'a grid frame is served at once, and nearest finds the closest',
      () async {
        final s = session();
        await s.open('https://media.example/ep.m3u8', {});
        expect(await s.gridFrame(60000), isTrue);
        expect(await s.gridFrame(120000), isTrue);
        // Exact bucket: straight from the grid, no decoder.
        expect(await s.frame(61000), [60]);
        // Between the two, nearer 120s.
        expect(s.nearest(100000), [120]);
        // Too far from anything.
        expect(s.nearest(400000), isNull);
        await s.close();
      },
    );

    test('it steps aside while the viewer has a request out', () async {
      final hold = Completer<void>();
      final s = session(hold: hold);
      await s.open('https://media.example/ep.m3u8', {});
      final mine = s.frame(30000);
      await settle();
      expect(s.busy, isTrue);
      expect(await s.gridFrame(90000), isFalse, reason: 'retry later');
      hold.complete();
      await mine;
      await settle();
      expect(await s.gridFrame(90000), isTrue);
      await s.close();
    });

    test('scrubbing cannot evict it', () async {
      final s = FramePreviewSession(
        supported: true,
        maxFrames: 2,
        invoke: (method, args) async => method == 'frame'
            ? Uint8List.fromList([(args!['posMs'] as int) ~/ 5000])
            : true,
      );
      await s.open('https://media.example/ep.mp4', {});
      await s.gridFrame(500000);
      for (var t = 0; t < 60000; t += 5000) {
        await s.frame(t);
      }
      expect(s.nearest(500000, withinMs: 0), [100]);
      await s.close();
    });

    test('a new source starts an empty grid', () async {
      final s = session();
      await s.open('https://media.example/ep1.m3u8', {});
      await s.gridFrame(60000);
      await s.open('https://media.example/ep2.m3u8', {});
      expect(s.nearest(60000), isNull);
      expect(s.serves('https://media.example/ep2.m3u8'), isTrue);
      await s.close();
    });
  });
}
