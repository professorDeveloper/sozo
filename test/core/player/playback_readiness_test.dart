import 'dart:async';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/player/playback_readiness.dart';

PlaybackReadiness sample({
  int width = 0,
  int height = 0,
  bool video = true,
  bool audio = true,
  String? error,
}) => PlaybackReadiness(
  width: width,
  height: height,
  hasVideo: video,
  hasAudio: audio,
  duration: const Duration(minutes: 90),
  error: error,
);

void main() {
  test(
    'mpv codec failure falls back once for remote and downloaded video',
    () async {
      for (final path in ['https://cdn/video.mp4', '/downloads/video.mp4']) {
        var replacements = 0;
        final recovered = await initializeWithDecoderFallback(
          initialize: () => awaitPlaybackReadiness(
            read: () => sample(error: 'Could not open codec.'),
            signals: [],
            canceled: Completer<void>().future,
          ),
          canFallback: () => true,
          fallback: () async {
            replacements++;
          },
        );
        expect(recovered, isTrue, reason: path);
        expect(replacements, 1);
      }
    },
  );

  test('a platform failure propagates without another fallback loop', () async {
    var replacements = 0;
    await expectLater(
      initializeWithDecoderFallback(
        initialize: () async => throw StateError('Could not open codec.'),
        canFallback: () => true,
        fallback: () async {
          replacements++;
          throw StateError('platform decoder failed');
        },
      ),
      throwsStateError,
    );
    expect(replacements, 1);
  });

  test(
    'network, HTML and disposal failures do not retry with another engine',
    () async {
      for (final message in [
        'Failed to open https://cdn/x',
        'Failed to recognize file format.',
        'Player disposed',
      ]) {
        var replacements = 0;
        await expectLater(
          initializeWithDecoderFallback(
            initialize: () async => throw StateError(message),
            canFallback: () => true,
            fallback: () async {
              replacements++;
            },
          ),
          throwsStateError,
        );
        expect(replacements, 0);
      }
    },
  );

  test(
    'duration cannot initialize video before decoder dimensions arrive',
    () async {
      final signals = StreamController<void>.broadcast(sync: true);
      final canceled = Completer<void>();
      var state = sample();
      var finished = false;
      final waiting = awaitPlaybackReadiness(
        read: () => state,
        signals: [signals.stream],
        canceled: canceled.future,
      ).then((_) => finished = true);
      signals.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(finished, false);
      state = sample(width: 3840, height: 0);
      signals.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(finished, false);
      state = sample(width: 3840, height: 2160);
      signals.add(null);
      await waiting;
      expect(finished, true);
      await signals.close();
    },
  );

  test('audio-only media is ready without invented video dimensions', () async {
    await awaitPlaybackReadiness(
      read: () => sample(video: false),
      signals: [],
      canceled: Completer<void>().future,
    );
  });

  test(
    'stalled video times out instead of becoming initialized black output',
    () async {
      await expectLater(
        awaitPlaybackReadiness(
          read: sample,
          signals: [],
          canceled: Completer<void>().future,
          timeout: Duration.zero,
        ),
        throwsA(isA<TimeoutException>()),
      );
    },
  );

  test('closing a pending player cancels its readiness wait', () async {
    final canceled = Completer<void>();
    final waiting = awaitPlaybackReadiness(
      read: sample,
      signals: [],
      canceled: canceled.future,
    );
    final assertion = expectLater(waiting, throwsStateError);
    canceled.complete();
    await assertion;
  });

  test('decoder errors are not reported as successful readiness', () async {
    await expectLater(
      awaitPlaybackReadiness(
        read: () => sample(error: 'codec failed'),
        signals: [],
        canceled: Completer<void>().future,
      ),
      throwsStateError,
    );
  });

  group('picture timeout', () {
    test('a known video track with no picture is a stalled decoder', () {
      fakeAsync((async) {
        Object? failure;
        awaitPlaybackReadiness(
          read: sample,
          signals: [],
          canceled: Completer<void>().future,
          pictureTimeout: const Duration(seconds: 12),
        ).catchError((Object e) => failure = e);
        async.elapse(const Duration(seconds: 11));
        expect(failure, isNull);
        async.elapse(const Duration(seconds: 2));
        expect(failure, isA<TimeoutException>());
      });
    });

    test('is not counted before the track list exists', () async {
      // A slow host's long open is the network's time, not the decoder's.
      // Real time, scaled down: the readiness wait awaits its signal
      // subscriptions' cancel, which fake time cannot see through.
      var state = sample(video: false, audio: false);
      final signals = StreamController<void>.broadcast(sync: true);
      final waiting = awaitPlaybackReadiness(
        read: () => state,
        signals: [signals.stream],
        canceled: Completer<void>().future,
        pictureTimeout: const Duration(milliseconds: 150),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
      state = sample();
      signals.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      state = sample(width: 1920, height: 1080);
      signals.add(null);
      await waiting;
      await signals.close();
    });

    test(
      'a stall the network caused can still be told apart by the caller',
      () {
        // The controller turns this timeout into the held network error; the
        // fallback only sees decoder-shaped failures and timeouts.
        expect(
          initializeWithDecoderFallback(
            initialize: () async =>
                throw StateError('tcp: ffurl_read returned'),
            canFallback: () => true,
            fallback: () async => fail('no engine swap for a network failure'),
          ),
          throwsStateError,
        );
      },
    );
  });

  group('startup budget', () {
    test('every kind of remote start is bounded; a file on disk is not', () {
      expect(startupBudget(local: true), isNull);
      expect(startupBudget(local: false), const Duration(seconds: 25));
      expect(
        startupBudget(local: false, sniffed: true),
        const Duration(seconds: 35),
      );
      expect(
        startupBudget(local: false, torrent: true),
        const Duration(seconds: 90),
      );
      expect(
        startupBudget(local: false, live: true),
        const Duration(seconds: 30),
      );
    });

    test('the plain budget leaves room for the slowest healthy start', () {
      // log_2e4886: vidapi HLS on mobile data took 17-19 s to its first frame.
      expect(
        startupBudget(local: false)! > const Duration(seconds: 19),
        isTrue,
      );
    });

    test('a start that never finishes times out', () {
      fakeAsync((async) {
        Object? failure;
        withinStartupBudget(
          Completer<void>().future,
          budget: const Duration(seconds: 25),
        ).catchError((Object e) => failure = e);
        async.elapse(const Duration(seconds: 24));
        expect(failure, isNull);
        async.elapse(const Duration(seconds: 2));
        expect(failure, isA<TimeoutException>());
      });
    });

    test('a start that finishes in time passes, and its error passes', () {
      fakeAsync((async) {
        var done = false;
        Object? failure;
        withinStartupBudget(
          Future<void>.delayed(const Duration(seconds: 3)),
          budget: const Duration(seconds: 25),
        ).then((_) => done = true);
        withinStartupBudget(
          Future<void>.delayed(
            const Duration(seconds: 3),
            () => throw StateError('Failed to open'),
          ),
          budget: const Duration(seconds: 25),
        ).catchError((Object e) => failure = e);
        async.elapse(const Duration(seconds: 4));
        expect(done, isTrue);
        expect(failure, isStateError);
      });
    });

    test('an engine swap gets its own allowance, once', () {
      fakeAsync((async) {
        final swaps = StreamController<void>.broadcast(sync: true);
        Object? failure;
        withinStartupBudget(
          Completer<void>().future,
          budget: const Duration(seconds: 25),
          restarts: swaps.stream,
        ).catchError((Object e) => failure = e);
        async.elapse(const Duration(seconds: 20));
        swaps.add(null); // libmpv gave way to the platform player
        async.elapse(const Duration(seconds: 20));
        expect(failure, isNull, reason: '40 s in, 20 s into the new engine');
        swaps.add(null); // a second swap does not extend it again
        async.elapse(const Duration(seconds: 6));
        expect(failure, isA<TimeoutException>());
      });
    });

    test('a start that fails after its deadline does not surface', () {
      fakeAsync((async) {
        final late = Completer<void>();
        Object? failure;
        withinStartupBudget(
          late.future,
          budget: const Duration(seconds: 1),
        ).catchError((Object e) => failure = e);
        async.elapse(const Duration(seconds: 2));
        expect(failure, isA<TimeoutException>());
        late.completeError(StateError('Player disposed'));
        async.flushMicrotasks();
        expect(failure, isA<TimeoutException>());
      });
    });
  });

  group('a network error held while playing', () {
    NetworkStall judge({
      Duration position = const Duration(minutes: 10),
      bool playing = true,
      bool completed = false,
    }) => judgeNetworkStall(
      stalledAt: const Duration(minutes: 10),
      position: position,
      playing: playing,
      completed: completed,
      duration: const Duration(minutes: 23),
    );

    test('is forgotten once the playhead moves on', () {
      expect(
        judge(position: const Duration(minutes: 10, seconds: 20)),
        NetworkStall.recovered,
      );
      // Seeked back past the stall and watching again.
      expect(
        judge(position: const Duration(minutes: 2)),
        NetworkStall.recovered,
      );
    });

    test('is fatal when playback is stuck on it', () {
      expect(judge(), NetworkStall.fatal);
    });

    test('is fatal when the file ended early on it', () {
      expect(judge(playing: false, completed: true), NetworkStall.fatal);
    });

    test('is fatal when the cache carried the playhead past it first', () {
      // Read-ahead kept playing for a minute after the drop, then ran dry.
      expect(
        judge(
          position: const Duration(minutes: 11, seconds: 30),
          playing: false,
          completed: true,
        ),
        NetworkStall.fatal,
      );
    });

    test('is fatal when a stream without a length ends on it', () {
      expect(
        judgeNetworkStall(
          stalledAt: const Duration(minutes: 10),
          position: const Duration(minutes: 12),
          playing: false,
          completed: true,
          duration: Duration.zero,
        ),
        NetworkStall.fatal,
      );
    });

    test('is nothing at the real end of the file', () {
      expect(
        judge(
          position: const Duration(minutes: 23),
          playing: false,
          completed: true,
        ),
        NetworkStall.recovered,
      );
    });

    test('waits while the viewer has paused', () {
      expect(judge(playing: false), NetworkStall.undecided);
    });
  });

  test('a decoder line about one packet is a glitch, a codec that will not open is not', () {
    expect(isDecodeGlitch('Error decoding audio.'), isTrue);
    expect(isDecodeGlitch('[ffmpeg/video] h264: Error while decoding frame!'), isTrue);
    expect(isDecodeGlitch('Could not open codec.'), isFalse);
    expect(isDecodeGlitch('tcp: ffurl_read returned 0xffffff92'), isFalse);
  });
}
