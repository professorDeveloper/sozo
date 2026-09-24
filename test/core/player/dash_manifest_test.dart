// A DASH manifest's video renditions, and the manifest narrowed to one.
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/player/dash_manifest.dart';

const _mpd = '''<?xml version="1.0"?>
<MPD xmlns="urn:mpeg:dash:schema:mpd:2011" type="static">
  <Period>
    <AdaptationSet contentType="video" height="720">
      <Representation id="a" height="1080" bandwidth="5000000" codecs="avc1"/>
      <Representation id="b" bandwidth="2500000"/>
      <Representation id="c" height="1080" bandwidth="7000000"/>
      <Representation id="d" height="480" bandwidth="900000"/>
    </AdaptationSet>
    <AdaptationSet contentType="audio">
      <Representation id="snd" bandwidth="128000"/>
    </AdaptationSet>
  </Period>
</MPD>''';

void main() {
  test('one rendition per height, the richest, tallest first', () {
    final reps = DashManifest.videoRepresentations(_mpd);
    expect(reps.map((r) => r.height), [1080, 720, 480]);
    // Two 1080p renditions: the higher bitrate is offered.
    expect(reps.first.id, 'c');
    // A height given on the set counts for its Representations.
    expect(reps[1].id, 'b');
  });

  test('narrowing keeps one video rendition and all the audio', () {
    final out = DashManifest.narrow(_mpd, keepId: 'd');
    expect(out, contains('id="d"'));
    for (final gone in ['"a"', '"b"', '"c"']) {
      expect(out, isNot(contains('id=$gone')));
    }
    expect(out, contains('id="snd"'));
  });

  test('a manifest that does not parse comes back unchanged', () {
    expect(DashManifest.narrow('<nope', keepId: 'x'), '<nope');
    expect(DashManifest.videoRepresentations('<nope'), isEmpty);
  });
}
