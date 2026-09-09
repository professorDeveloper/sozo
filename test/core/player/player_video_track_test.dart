import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/player/player_video_track.dart';

PlayerVideoTrack t({
  String id = '1',
  int? width,
  int? height,
  int? bitrate,
  String? codec,
  int ordinal = 1,
}) =>
    PlayerVideoTrack(
      id: id,
      width: width,
      height: height,
      bitrate: bitrate,
      codec: codec,
      ordinal: ordinal,
    );

void main() {
  group('what a row says', () {
    test('height becomes the name people use for it', () {
      expect(t(height: 2160).label, '4K');
      expect(t(height: 1080).label, '1080p');
      expect(t(height: 720).label, '720p');
      expect(t(height: 480).label, '480p');
      expect(t(height: 360).label, '360p');
    });

    test('an odd height still names itself rather than falling back', () {
      expect(t(height: 244).label, '244p');
    });

    test('no height falls back to the bitrate, which is still real', () {
      expect(t(bitrate: 4200000).label, '4.2 Mbps');
      expect(t(bitrate: 800000).label, '800 kbps');
    });

    test('a rendition the manifest described with nothing gets a position', () {
      // Never the bare id: a list reading "1" and "2" looks like a bug.
      expect(t(id: '3', ordinal: 2).label, 'Auto 2');
    });

    test('the detail line carries what the label could not', () {
      final track =
          t(width: 1920, height: 1080, bitrate: 4200000, codec: 'h264');
      expect(track.label, '1080p');
      expect(track.detail, '1920×1080 · 4.2 Mbps · h264');
    });

    test('a bare track has no detail line at all', () {
      expect(t().detail, isNull);
    });
  });

  group('auto', () {
    test('is recognised by mpv\'s own id', () {
      expect(t(id: 'auto').isAuto, isTrue);
      expect(t(id: '1').isAuto, isFalse);
    });

    test('leads the list — it is the default and the way back to adaptive', () {
      final sorted = sortVideoTracks([
        t(id: '1', height: 720),
        t(id: 'auto'),
        t(id: '2', height: 1080),
      ]);
      expect(sorted.first.isAuto, isTrue);
    });
  });

  group('ordering', () {
    test('best first, so the top of the list is the best picture', () {
      final sorted = sortVideoTracks([
        t(id: '1', height: 480),
        t(id: '2', height: 1080),
        t(id: '3', height: 720),
      ]);
      expect(sorted.map((x) => x.height).toList(), [1080, 720, 480]);
    });

    test('equal heights are broken by the stream carrying more data', () {
      final sorted = sortVideoTracks([
        t(id: '1', height: 1080, bitrate: 2000000),
        t(id: '2', height: 1080, bitrate: 6000000),
      ]);
      expect(sorted.first.id, '2');
    });

    test('renditions with no height sink below the ones that have it', () {
      final sorted = sortVideoTracks([t(id: '1'), t(id: '2', height: 480)]);
      expect(sorted.first.id, '2');
    });

    test('sorting does not mutate the caller\'s list', () {
      final input = [t(id: '1', height: 480), t(id: '2', height: 1080)];
      sortVideoTracks(input);
      expect(input.map((x) => x.id).toList(), ['1', '2']);
    });

    test('an empty list sorts to an empty list', () {
      expect(sortVideoTracks(const []), isEmpty);
    });
  });

  group('metadata', () {
    test('a height or a bitrate counts as described', () {
      expect(t(height: 720).hasMetadata, isTrue);
      expect(t(bitrate: 1000).hasMetadata, isTrue);
    });

    test('neither does not', () {
      // This is what tells the UI to show a positional label instead of
      // pretending it knows the resolution.
      expect(t().hasMetadata, isFalse);
      expect(t(height: 0).hasMetadata, isFalse);
    });
  });

  test('equality is by value, so a re-probe with the same data is not a change',
      () {
    // mpv probes a stream in stages and reports the same renditions twice —
    // first bare, then described. Identity comparison would rebuild the sheet
    // on every one of those.
    expect(t(id: '1', height: 1080), equals(t(id: '1', height: 1080)));
    expect(t(id: '1', height: 1080), isNot(equals(t(id: '1', height: 720))));
  });
}
