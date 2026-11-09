import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/detail/domain/playback/tap_seek.dart';

Duration ms(int v) => Duration(milliseconds: v);

void main() {
  late TapSeekTracker t;
  setUp(() => t = TapSeekTracker());

  test('zones split the width 30 / 40 / 30', () {
    expect(TapSeekTracker.zoneOf(10, 100), TapZone.left);
    expect(TapSeekTracker.zoneOf(50, 100), TapZone.centre);
    expect(TapSeekTracker.zoneOf(90, 100), TapZone.right);
  });

  test('a single tap toggles the controls once the double-tap window ends', () {
    expect(t.onTap(TapZone.right, ms(0), canSeek: true), TapAction.pending);
    expect(t.flush(ms(100)), isNull);
    expect(t.flush(ms(300)), TapAction.toggleControls);
    expect(t.flush(ms(400)), isNull);
  });

  test('a double tap on a side seeks', () {
    t.onTap(TapZone.left, ms(0), canSeek: true);
    expect(t.onTap(TapZone.left, ms(150), canSeek: true), TapAction.seekBack);
    expect(t.steps, 1);
    expect(t.flush(ms(1000)), isNull);
  });

  test('while the ripple is up, each single tap on that side adds a step', () {
    t.onTap(TapZone.right, ms(0), canSeek: true);
    t.onTap(TapZone.right, ms(150), canSeek: true);
    expect(
      t.onTap(TapZone.right, ms(500), canSeek: true),
      TapAction.seekForward,
    );
    expect(
      t.onTap(TapZone.right, ms(900), canSeek: true),
      TapAction.seekForward,
    );
    expect(t.steps, 3);
    // The ripple has gone: back to a single tap.
    expect(t.onTap(TapZone.right, ms(2000), canSeek: true), TapAction.pending);
  });

  test('the other side during a ripple starts afresh', () {
    t.onTap(TapZone.right, ms(0), canSeek: true);
    t.onTap(TapZone.right, ms(150), canSeek: true);
    expect(t.onTap(TapZone.left, ms(400), canSeek: true), TapAction.pending);
    expect(t.onTap(TapZone.left, ms(500), canSeek: true), TapAction.seekBack);
    expect(t.steps, 1);
  });

  test('a double tap in the centre toggles play', () {
    t.onTap(TapZone.centre, ms(0), canSeek: true);
    expect(
      t.onTap(TapZone.centre, ms(120), canSeek: true),
      TapAction.togglePlay,
    );
  });

  test('no wait when a double tap could not do anything', () {
    expect(
      t.onTap(TapZone.left, ms(0), canSeek: false, centreTogglesPlay: false),
      TapAction.toggleControls,
    );
    expect(
      t.onTap(
        TapZone.centre,
        ms(1000),
        canSeek: true,
        centreTogglesPlay: false,
      ),
      TapAction.toggleControls,
    );
    expect(t.hasPending, isFalse);
  });

  test('two slow taps are two single taps', () {
    t.onTap(TapZone.left, ms(0), canSeek: true);
    expect(t.flush(ms(400)), TapAction.toggleControls);
    expect(t.onTap(TapZone.left, ms(400), canSeek: true), TapAction.pending);
  });
}
