import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/download/domain/download_layout.dart';
import 'package:soplay/features/download/domain/entities/download_kind.dart';

/// Paths, without a device.
///
/// This is the file the "File not found" bug reduces to: every download used to
/// store where it was on the phone that made it, and that string stops being
/// true the moment anything about the phone changes. Nothing here may touch
/// `dart:io`, a plugin or a clock — if it ever needs to, the layout has stopped
/// being a property of the download.
void main() {
  group('artefact layout', () {
    test('a single file lands under its own id', () {
      expect(
        DownloadLayout.artefactFor('abc', kind: DownloadKind.video),
        'downloads/abc/video.mp4',
      );
    });

    test('the extension follows what was actually served', () {
      expect(
        DownloadLayout.artefactFor(
          'abc',
          kind: DownloadKind.video,
          extension: '.mkv',
        ),
        'downloads/abc/video.mkv',
      );
    });

    test('a playlist is the index, not the folder', () {
      expect(
        DownloadLayout.artefactFor('abc', kind: DownloadKind.hls),
        'downloads/abc/index.m3u8',
      );
    });

    test('a chapter is the folder, because its pages are the artefact', () {
      expect(
        DownloadLayout.artefactFor('abc', kind: DownloadKind.manga),
        'downloads/abc',
      );
    });

    test('nothing it produces is absolute', () {
      for (final kind in DownloadKind.values) {
        expect(
          DownloadLayout.artefactFor('abc', kind: kind),
          isNot(startsWith('/')),
        );
      }
    });
  });

  group('recovering a relative path from an old row', () {
    test('an already-relative path is returned unchanged', () {
      expect(
        DownloadLayout.relativeFromLegacy('downloads/abc/video.mp4'),
        'downloads/abc/video.mp4',
      );
    });

    test('the device prefix is dropped', () {
      expect(
        DownloadLayout.relativeFromLegacy(
          '/data/user/0/com.soplay.sozo/app_flutter/downloads/abc/index.m3u8',
        ),
        'downloads/abc/index.m3u8',
      );
    });

    test('two Android users produce the same answer', () {
      final zero = DownloadLayout.relativeFromLegacy(
        '/data/user/0/com.soplay.sozo/app_flutter/downloads/abc/video.mp4',
      );
      final ten = DownloadLayout.relativeFromLegacy(
        '/data/user/10/com.soplay.sozo/app_flutter/downloads/abc/video.mp4',
      );
      final alias = DownloadLayout.relativeFromLegacy(
        '/data/data/com.soplay.sozo/app_flutter/downloads/abc/video.mp4',
      );
      expect(zero, ten);
      expect(zero, alias);
    });

    test('an iOS container path lifts the same way', () {
      expect(
        DownloadLayout.relativeFromLegacy(
          '/var/mobile/Containers/Data/Application/1234-ABCD/Documents/downloads/abc/video.mp4',
        ),
        'downloads/abc/video.mp4',
      );
    });

    test('a path with nothing recognisable in it returns null', () {
      expect(DownloadLayout.relativeFromLegacy('/tmp/whatever.mp4'), isNull);
      expect(DownloadLayout.relativeFromLegacy(''), isNull);
      expect(DownloadLayout.relativeFromLegacy(null), isNull);
    });
  });

  group('extensions', () {
    test('the path decides, not the query string', () {
      expect(
        DownloadLayout.videoExtensionFor(
          'https://host.test/opaque/token?file=movie.mkv',
        ),
        '.mp4',
      );
      expect(
        DownloadLayout.videoExtensionFor('https://host.test/movie.mkv?t=1'),
        '.mkv',
      );
    });

    test('an unknown extension falls back to mp4', () {
      expect(DownloadLayout.videoExtensionFor('https://host.test/x'), '.mp4');
    });
  });

  group('HLS detection', () {
    test('a query parameter mentioning m3u8 is not a playlist', () {
      expect(
        DownloadKind.looksLikeHls('https://host.test/video.mp4?next=x.m3u8'),
        isFalse,
      );
    });

    test('a real playlist is one', () {
      expect(
        DownloadKind.looksLikeHls('https://host.test/pl/token/master.m3u8'),
        isTrue,
      );
    });
  });
}
