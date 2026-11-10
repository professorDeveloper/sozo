import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/detail/domain/playback/end_of_stream.dart';

Duration s(num v) => Duration(milliseconds: (v * 1000).round());

void main() {
  late EndOfStreamDetector d;
  setUp(() => d = EndOfStreamDetector());

  bool tick(
    num pos, {
    num dur = 1400,
    bool completed = false,
    bool playing = true,
    bool buffering = false,
    required num at,
  }) => d.observe(
    position: s(pos),
    duration: s(dur),
    isCompleted: completed,
    isPlaying: playing,
    isBuffering: buffering,
    now: s(at),
  );

  test('the last two seconds end the episode, once', () {
    expect(tick(1390, at: 0), isFalse);
    expect(tick(1398.5, at: 8), isTrue);
    expect(tick(1399, at: 9), isFalse);
    expect(tick(1400, at: 10), isFalse);
  });

  test('completion from the engine ends it even short of the duration', () {
    expect(tick(1380, completed: true, playing: false, at: 0), isTrue);
    expect(tick(1380, completed: true, playing: false, at: 1), isFalse);
  });

  test('a playhead stuck within 5 s of the end ends it after 3 s', () {
    expect(tick(1396, at: 0), isFalse);
    expect(tick(1396, buffering: true, at: 1), isFalse);
    expect(tick(1396, buffering: true, at: 2.9), isFalse);
    expect(tick(1396, buffering: true, at: 3.1), isTrue);
    expect(tick(1396, buffering: true, at: 5), isFalse);
  });

  test('paused near the end is not a stall', () {
    expect(tick(1396, playing: false, at: 0), isFalse);
    expect(tick(1396, playing: false, at: 10), isFalse);
  });

  test('a stall further from the end is just buffering', () {
    expect(tick(1300, buffering: true, at: 0), isFalse);
    expect(tick(1300, buffering: true, at: 30), isFalse);
  });

  test('seeking back re-arms it', () {
    expect(tick(1399, at: 0), isTrue);
    expect(tick(600, at: 1), isFalse);
    expect(tick(1399, at: 2), isTrue);
  });

  test('a stream without a duration never ends here', () {
    expect(tick(10, dur: 0, completed: true, at: 0), isFalse);
  });
}
