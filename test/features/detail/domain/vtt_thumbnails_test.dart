import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/detail/domain/vtt_thumbnails.dart';

void main() {
  const base = 'https://cdn.test/v/thumbs.vtt';

  test('a sprite cell, with hours, relative to the track', () {
    final cues = parseVttThumbnails('''
WEBVTT

00:00:10.000 --> 00:00:20.000
sheet0.jpg#xywh=160,90,160,90
''', base);
    expect(cues, hasLength(1));
    expect(cues.single.start, const Duration(seconds: 10));
    expect(cues.single.end, const Duration(seconds: 20));
    expect(cues.single.imageUrl, 'https://cdn.test/v/sheet0.jpg');
    expect(cues.single.hasSprite, isTrue);
    expect(cues.single.x, 160);
  });

  test('a cue under an hour may leave the hours out', () {
    final cues = parseVttThumbnails(
      'WEBVTT\n\n01:30.500 --> 01:40.000\nhttps://img.test/a.jpg\n',
      base,
    );
    expect(cues, hasLength(1));
    expect(
      cues.single.start,
      const Duration(minutes: 1, seconds: 30, milliseconds: 500),
    );
    expect(cues.single.imageUrl, 'https://img.test/a.jpg');
    expect(cues.single.hasSprite, isFalse);
  });

  test('both shapes in one track, and past the hundredth hour', () {
    final cues = parseVttThumbnails(
      'WEBVTT\n\n59:50.000 --> 01:00:00.000\na.jpg\n\n'
      '100:00:00.000 --> 100:00:10.000\nb.jpg\n',
      base,
    );
    expect(cues.map((c) => c.end), [
      const Duration(hours: 1),
      const Duration(hours: 100, seconds: 10),
    ]);
  });
}
