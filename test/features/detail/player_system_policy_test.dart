import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/detail/domain/playback/player_system_policy.dart';

void main() {
  group('pausesOnLifecycle', () {
    test('a phone pauses only when the app is really gone', () {
      bool pauses(AppLifecycleState s) =>
          pausesOnLifecycle(s, desktop: false, inPip: false);
      expect(pauses(AppLifecycleState.paused), isTrue);
      expect(pauses(AppLifecycleState.hidden), isTrue);
      expect(pauses(AppLifecycleState.inactive), isFalse);
      expect(pauses(AppLifecycleState.resumed), isFalse);
      expect(pauses(AppLifecycleState.detached), isFalse);
    });

    test('picture-in-picture keeps playing', () {
      for (final s in AppLifecycleState.values) {
        expect(pausesOnLifecycle(s, desktop: false, inPip: true), isFalse);
      }
    });

    test('the desktop never pauses on lifecycle', () {
      for (final s in AppLifecycleState.values) {
        expect(pausesOnLifecycle(s, desktop: true, inPip: false), isFalse);
      }
    });
  });

  group('AndroidPipTracker', () {
    test('is active from the moment entry is asked for', () {
      final t = AndroidPipTracker()..beginEnter();
      expect(t.active, isTrue);
      expect(t.onModeChanged(inPip: true, dismissed: false), PipChange.entered);
      expect(t.active, isTrue);
    });

    test('a refused entry rolls back', () {
      final t = AndroidPipTracker()
        ..beginEnter()
        ..enterFailed();
      expect(t.active, isFalse);
    });

    test('auto-enter from Home is picked up from the mode change', () {
      final t = AndroidPipTracker();
      expect(t.onModeChanged(inPip: true, dismissed: false), PipChange.entered);
      expect(t.active, isTrue);
    });

    test('expanding back restores, closing dismisses', () {
      final t = AndroidPipTracker()
        ..onModeChanged(inPip: true, dismissed: false);
      expect(
        t.onModeChanged(inPip: false, dismissed: false),
        PipChange.restored,
      );
      t.onModeChanged(inPip: true, dismissed: false);
      expect(
        t.onModeChanged(inPip: false, dismissed: true),
        PipChange.dismissed,
      );
      expect(t.active, isFalse);
    });

    test('a dismissal reported after the restore still dismisses', () {
      final t = AndroidPipTracker()
        ..onModeChanged(inPip: true, dismissed: false);
      t.onModeChanged(inPip: false, dismissed: false);
      expect(
        t.onModeChanged(inPip: false, dismissed: true),
        PipChange.dismissed,
      );
    });

    test('resuming clears it once', () {
      final t = AndroidPipTracker()..beginEnter();
      expect(t.onResumed(), PipChange.restored);
      expect(t.onResumed(), PipChange.none);
      expect(t.onModeChanged(inPip: false, dismissed: false), PipChange.none);
    });
  });

  group('AudioFocusPolicy', () {
    test('wire names map to events', () {
      expect(audioFocusEventFromWire('gain'), AudioFocusEvent.gain);
      expect(audioFocusEventFromWire('loss'), AudioFocusEvent.loss);
      expect(
        audioFocusEventFromWire('loss_transient'),
        AudioFocusEvent.lossTransient,
      );
      expect(audioFocusEventFromWire('duck'), AudioFocusEvent.duck);
      expect(audioFocusEventFromWire('noisy'), AudioFocusEvent.noisy);
      expect(audioFocusEventFromWire('other'), isNull);
      expect(audioFocusEventFromWire(null), isNull);
    });

    test('a call pauses and the end of it plays on', () {
      final p = AudioFocusPolicy();
      expect(
        p.on(AudioFocusEvent.lossTransient, playing: true),
        const AudioFocusResponse(pause: true),
      );
      expect(
        p.on(AudioFocusEvent.gain, playing: false),
        const AudioFocusResponse(resume: true),
      );
    });

    test('a transient loss while paused does not resume afterwards', () {
      final p = AudioFocusPolicy();
      expect(
        p.on(AudioFocusEvent.lossTransient, playing: false),
        AudioFocusResponse.none,
      );
      expect(
        p.on(AudioFocusEvent.gain, playing: false),
        AudioFocusResponse.none,
      );
    });

    test('playing by hand during the call cancels the resume', () {
      final p = AudioFocusPolicy()
        ..on(AudioFocusEvent.lossTransient, playing: true)
        ..onPlayingChanged(true);
      expect(
        p.on(AudioFocusEvent.gain, playing: true),
        AudioFocusResponse.none,
      );
    });

    test('a permanent loss pauses for good', () {
      final p = AudioFocusPolicy();
      expect(
        p.on(AudioFocusEvent.loss, playing: true),
        const AudioFocusResponse(pause: true),
      );
      expect(
        p.on(AudioFocusEvent.gain, playing: false),
        AudioFocusResponse.none,
      );
    });

    test('a permanent loss after a transient one forgets the resume', () {
      final p = AudioFocusPolicy()
        ..on(AudioFocusEvent.lossTransient, playing: true);
      p.on(AudioFocusEvent.loss, playing: false);
      expect(
        p.on(AudioFocusEvent.gain, playing: false),
        AudioFocusResponse.none,
      );
    });

    test('ducking lowers and gain restores the volume', () {
      final p = AudioFocusPolicy();
      expect(
        p.on(AudioFocusEvent.duck, playing: true),
        const AudioFocusResponse(volume: AudioFocusPolicy.duckVolume),
      );
      expect(
        p.on(AudioFocusEvent.duck, playing: true),
        AudioFocusResponse.none,
      );
      expect(
        p.on(AudioFocusEvent.gain, playing: true),
        const AudioFocusResponse(volume: 1.0),
      );
    });

    test('headphones out pause, and only when playing', () {
      final p = AudioFocusPolicy();
      expect(
        p.on(AudioFocusEvent.noisy, playing: true),
        const AudioFocusResponse(pause: true),
      );
      expect(
        p.on(AudioFocusEvent.noisy, playing: false),
        AudioFocusResponse.none,
      );
    });
  });

  group('BrightnessKeeper', () {
    test('nothing to hand back until the viewer swipes', () {
      final k = BrightnessKeeper();
      expect(k.onBackground(), isFalse);
      expect(k.onResume(), isNull);
    });

    test('the viewer level is handed back and applied again', () {
      final k = BrightnessKeeper()..userSet(0.8);
      expect(k.onBackground(), isTrue);
      expect(k.onResume(), 0.8);
    });

    test('levels are clamped', () {
      expect((BrightnessKeeper()..userSet(1.4)).level, 1.0);
      expect((BrightnessKeeper()..userSet(-1)).level, 0.0);
    });

    test('leaving the player forgets it', () {
      final k = BrightnessKeeper()
        ..userSet(0.3)
        ..onExit();
      expect(k.onBackground(), isFalse);
      expect(k.onResume(), isNull);
    });
  });

  group('pip geometry', () {
    test('the source rect letterboxes the picture', () {
      expect(
        pipSourceRect(const Size(2400, 1080), const Size(1920, 1080)),
        const Rect.fromLTWH(240, 0, 1920, 1080),
      );
      expect(
        pipSourceRect(const Size(1080, 2400), const Size(1920, 1080)),
        const Rect.fromLTWH(0, 896.25, 1080, 607.5),
      );
      expect(pipSourceRect(Size.zero, const Size(16, 9)), isNull);
      expect(pipSourceRect(const Size(16, 9), Size.zero), isNull);
    });

    test('the aspect stays inside what Android accepts', () {
      expect(pipAspect(const Size(1920, 1080)), (1920, 1080));
      expect(pipAspect(const Size(1080, 1920)), (1080, 1920));
      expect(pipAspect(const Size(3000, 1000)), (16, 9));
      expect(pipAspect(Size.zero), (16, 9));
    });
  });

  group('MediaSessionGate', () {
    test('sends changes of state and speed, not ticks', () {
      final g = MediaSessionGate();
      expect(
        g.shouldSend(playing: true, positionMs: 0, speed: 1, nowMs: 0),
        isTrue,
      );
      expect(
        g.shouldSend(playing: true, positionMs: 1000, speed: 1, nowMs: 1000),
        isFalse,
      );
      expect(
        g.shouldSend(playing: false, positionMs: 1200, speed: 1, nowMs: 1200),
        isTrue,
      );
      expect(
        g.shouldSend(playing: false, positionMs: 1200, speed: 1.5, nowMs: 1300),
        isTrue,
      );
    });

    test('sends a seek', () {
      final g = MediaSessionGate()
        ..shouldSend(playing: true, positionMs: 0, speed: 1, nowMs: 0);
      expect(
        g.shouldSend(playing: true, positionMs: 60000, speed: 1, nowMs: 1000),
        isTrue,
      );
    });

    test('reset sends again', () {
      final g = MediaSessionGate()
        ..shouldSend(playing: true, positionMs: 0, speed: 1, nowMs: 0)
        ..reset();
      expect(
        g.shouldSend(playing: true, positionMs: 10, speed: 1, nowMs: 10),
        isTrue,
      );
    });
  });
}
