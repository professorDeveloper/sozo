// What a subtitle file carries that is not text to read: SubRip's inline
// tags and position codes, and ASS vector drawings.
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/subtitles/subtitle_parser.dart';

void main() {
  test('SubRip markup is not shown as text', () {
    const srt =
        '1\n00:00:01,000 --> 00:00:02,000\n'
        '{\\an8}<i>Hello</i> <font color="#ffff00">there</font>\n'
        '<b>a &amp; b</b>\n';
    final r = parseSubtitleText(srt);
    expect(r.captions.single.text, 'Hello there\na & b');
  });

  test('an ASS vector drawing is dropped, the dialogue kept', () {
    const ass =
        '[Script Info]\nScriptType: v4.00+\n\n[Events]\n'
        'Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n'
        'Dialogue: 0,0:00:01.00,0:00:03.00,Sign,,0,0,0,,{\\p1}m 0 0 l 100 0 100 100 0 100{\\p0}\n'
        'Dialogue: 0,0:00:01.00,0:00:03.00,Default,,0,0,0,,{\\i1}Hello{\\i0}, world\n';
    final r = parseSubtitleText(ass);
    expect(r.captions.map((c) => c.text).toList(), ['Hello, world']);
  });
}
