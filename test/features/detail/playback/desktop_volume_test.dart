import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/detail/domain/playback/desktop_volume.dart';

void main() {
  test('every new controller gets the level back', () async {
    const volume = DesktopVolume(level: 0.4);
    final seen = <double>[];
    for (var i = 0; i < 3; i++) {
      await volume.applyTo((v) async => seen.add(v));
    }
    expect(seen, [0.4, 0.4, 0.4]);
  });

  test(
    'mute survives a new controller, and unmute restores the level',
    () async {
      final muted = const DesktopVolume(level: 0.7).toggleMute();
      final seen = <double>[];
      await muted.applyTo((v) async => seen.add(v));
      expect(seen.single, 0);
      final back = muted.toggleMute();
      expect(back.applied, 0.7);
    },
  );

  test('up to 150% on mpv, clamped to 100% elsewhere', () async {
    final loud = const DesktopVolume().withLevel(
      1.4,
      max: DesktopVolume.boostMax,
    );
    expect(loud.level, 1.4);
    final seen = <double>[];
    await loud.applyTo((v) async => seen.add(v), max: 1.0);
    await loud.applyTo((v) async => seen.add(v), max: 1.5);
    expect(seen, [1.0, 1.4]);
    expect(const DesktopVolume().withLevel(9, max: 1.5).level, 1.5);
  });

  test('dragging to zero mutes without losing the level', () {
    final v = const DesktopVolume(level: 0.6).withLevel(0);
    expect(v.muted, isTrue);
    expect(v.toggleMute().applied, 0.6);
  });

  test('restores what was stored, with sane fallbacks', () {
    final r = DesktopVolume.restore(0.3, true);
    expect(r.level, 0.3);
    expect(r.muted, isTrue);
    expect(DesktopVolume.restore(null, null).applied, 1.0);
    expect(DesktopVolume.restore(7, false).level, DesktopVolume.boostMax);
    expect(DesktopVolume.restore(0, false).level, 1.0);
  });
}
