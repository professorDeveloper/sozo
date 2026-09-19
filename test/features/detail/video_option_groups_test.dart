import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/detail/domain/video_option_groups.dart';

void main() {
  group('server and quality are told apart by shape, not by order', () {
    test('host first', () {
      expect(VideoOptionGroups.serverOf('SubsPlease · 1080p'), 'SubsPlease');
      expect(VideoOptionGroups.qualityOf('SubsPlease · 1080p'), '1080p');
    });

    test('quality first — the case that shipped backwards', () {
      // The settings sheet showed Server "480p" and Quality "1-server".
      expect(VideoOptionGroups.serverOf('480p · 1-server'), '1-server');
      expect(VideoOptionGroups.qualityOf('480p · 1-server'), '480p');
    });

    test('space separated, either order', () {
      expect(VideoOptionGroups.serverOf('Vidstream 720p'), 'Vidstream');
      expect(VideoOptionGroups.qualityOf('Vidstream 720p'), '720p');
      expect(VideoOptionGroups.serverOf('1080p Doodstream'), 'Doodstream');
      expect(VideoOptionGroups.qualityOf('1080p Doodstream'), '1080p');
    });

    test('no resolution at all means the whole label is a host', () {
      expect(VideoOptionGroups.serverOf('Server 1'), 'Server 1');
      expect(VideoOptionGroups.qualityOf('Server 1'), '');
      expect(VideoOptionGroups.serverOf('SUB · Mp4Upload'), 'SUB · Mp4Upload');
    });

    test('an empty label still groups somewhere', () {
      expect(VideoOptionGroups.serverOf(''), 'Default');
      expect(VideoOptionGroups.serverOf('   '), 'Default');
    });
  });

  group('grouping', () {
    final labels = [
      'Vidstream · 1080p',
      'Vidstream · 720p',
      '480p · Doodstream',
      'Doodstream · 1080p',
    ];

    test('servers are listed once, in the order they appear', () {
      expect(VideoOptionGroups.servers(labels), ['Vidstream', 'Doodstream']);
    });

    test(
      'a host collects its entries whichever way its labels are written',
      () {
        // Doodstream appears once with the quality first and once with it last.
        expect(VideoOptionGroups.indicesFor(labels, 'Doodstream'), [2, 3]);
        expect(VideoOptionGroups.qualitiesFor(labels, 'Doodstream'), [
          '480p',
          '1080p',
        ]);
      },
    );
  });

  group('switching host', () {
    final labels = [
      'A · 720p',
      'A · 1080p',
      'B · 360p',
      'B · 720p',
      'B · 1080p',
    ];

    test('keeps the resolution you were on', () {
      expect(VideoOptionGroups.switchTo(labels, 0, 'B'), 3);
    });

    test('falls back to the host\'s best, not its first', () {
      // Arbitrary provider ordering must not drop someone from 1080p to 360p.
      expect(VideoOptionGroups.switchTo(labels, 1, 'B'), 4);
    });

    test('an unknown host leaves the selection alone', () {
      expect(VideoOptionGroups.switchTo(labels, 1, 'C'), 1);
    });
  });
}
