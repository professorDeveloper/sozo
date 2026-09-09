import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/download/data/models/download_item_model.dart';
import 'package:soplay/features/download/domain/download_layout.dart';
import 'package:soplay/features/download/domain/entities/download_item.dart';
import 'package:soplay/features/download/domain/entities/download_kind.dart';
import 'package:soplay/features/download/domain/entities/download_status.dart';

/// The row on disk, and the shape it used to have.
///
/// Two regressions live here. The first is the status ceiling: `fromJson` had a
/// literal `3` against a five-value enum, so a persisted `failed` came back as
/// `completed` — the row rendered as a finished download and the tap answered
/// "File not found", a failure the app had already recorded and then forgotten
/// on the next read of its own store.
///
/// The second is bigger. Rows stored an ABSOLUTE path
/// (`/data/user/0/…/downloads/<id>/index.m3u8`), which stops resolving the
/// moment the app is restored, reinstalled or opened under a second Android
/// user — and every such row still claimed to be downloaded. Nothing persisted
/// is absolute any more, and the migration has to lift the old ones without
/// losing a single install's library.
void main() {
  DownloadItem itemWith(DownloadStatus status) => DownloadItem(
        id: 'd1',
        contentUrl: 'https://example.test/show',
        provider: 'anilist',
        title: 'Show',
        sourceUrl: 'https://example.test/ep1.mp4',
        relativePath: 'downloads/d1/video.mp4',
        createdAt: 1,
        status: status,
      );

  group('status survives a save/load round trip', () {
    for (final status in DownloadStatus.values) {
      test('$status', () {
        final restored =
            DownloadItemModel.fromJson(DownloadItemModel.toJson(itemWith(status)));
        expect(restored.status, status);
      });
    }
  });

  test('failed does not come back as completed', () {
    final restored = DownloadItemModel.fromJson(
      DownloadItemModel.toJson(itemWith(DownloadStatus.failed)),
    );
    expect(restored.status, isNot(DownloadStatus.completed));
    expect(restored.status, DownloadStatus.failed);
  });

  test('an unknown status name reads as pending rather than throwing', () {
    final json = DownloadItemModel.toJson(itemWith(DownloadStatus.completed))
      ..['status'] = 'something_from_a_newer_build';
    expect(DownloadItemModel.fromJson(json).status, DownloadStatus.pending);
  });

  group('migration from the pre-relative-path row', () {
    Map<String, dynamic> legacy({
      required String localPath,
      required int status,
      String kind = 'video',
      String videoUrl = 'https://example.test/ep1.mp4',
    }) =>
        <String, dynamic>{
          'id': 'g8vhps',
          'contentUrl': 'https://www.themoviedb.org/tv/108978',
          'provider': 'vidapi',
          'title': 'Reacher',
          'thumbnail': 'https://image.tmdb.org/t/p/w500/x.jpg',
          'videoUrl': videoUrl,
          'localPath': localPath,
          'headers': {'Referer': 'https://example.test/'},
          'totalBytes': 648,
          'downloadedBytes': 600,
          'status': status,
          'createdAt': 1788370602109,
          'isSerial': true,
          'episodeNumber': 1,
          'kind': kind,
        };

    test('an absolute path becomes relative', () {
      final item = DownloadItemModel.fromJson(legacy(
        localPath:
            '/data/user/0/com.soplay.sozo/app_flutter/downloads/g8vhps/index.m3u8',
        status: 3,
        videoUrl: 'https://example.test/master.m3u8',
      ));
      expect(item.relativePath, 'downloads/g8vhps/index.m3u8');
      expect(item.relativePath, isNot(startsWith('/')));
    });

    test('the user id in the old path does not survive', () {
      // The whole bug: `/data/user/0/…` and `/data/user/10/…` are the same
      // install seen from two Android users, and a row that remembered one
      // could not be opened from the other.
      final zero = DownloadItemModel.fromJson(legacy(
        localPath: '/data/user/0/com.soplay.sozo/app_flutter/downloads/g8vhps/video.mp4',
        status: 3,
      ));
      final ten = DownloadItemModel.fromJson(legacy(
        localPath: '/data/user/10/com.soplay.sozo/app_flutter/downloads/g8vhps/video.mp4',
        status: 3,
      ));
      expect(zero.relativePath, ten.relativePath);
    });

    test('an unrecognisable path falls back to the deterministic layout', () {
      final item = DownloadItemModel.fromJson(
        legacy(localPath: '', status: 3),
      );
      expect(
        item.relativePath,
        DownloadLayout.artefactFor(
          'g8vhps',
          kind: DownloadKind.video,
          extension: '.mp4',
        ),
      );
    });

    test('HLS is recovered from the url, not left as a plain video', () {
      final item = DownloadItemModel.fromJson(legacy(
        localPath: '/x/downloads/g8vhps/index.m3u8',
        status: 3,
        videoUrl: 'https://example.test/pl/token/master.m3u8',
      ));
      expect(item.kind, DownloadKind.hls);
      expect(item.unit, DownloadUnit.segments);
    });

    test('a legacy status index maps to the right name', () {
      // 4 was `failed` in the old index order, and the ceiling of 3 turned it
      // into `completed`.
      expect(
        DownloadItemModel.fromJson(legacy(localPath: '/x', status: 4)).status,
        DownloadStatus.failed,
      );
      expect(
        DownloadItemModel.fromJson(legacy(localPath: '/x', status: 3)).status,
        DownloadStatus.completed,
      );
    });

    test('segment counts do not become a byte size', () {
      // The old row overloaded totalBytes: 648 was a SEGMENT COUNT while the
      // transfer ran, and the list printed "648 B" for a 214 MB episode.
      final item = DownloadItemModel.fromJson(legacy(
        localPath: '/x/downloads/g8vhps/index.m3u8',
        status: 1,
        videoUrl: 'https://example.test/master.m3u8',
      ));
      expect(item.totalUnits, 648);
      expect(item.sizeBytes, 0);
    });

    test('a finished playlist reads its old number as bytes, not segments', () {
      // The overload flipped meaning at the finish line: the old service
      // rewrote totalBytes from a segment count to a byte size on completion,
      // so reading it as segments printed "224962314 segments" and reading it
      // as bytes mid-transfer printed "648 B" for a 214 MB episode.
      final item = DownloadItemModel.fromJson(legacy(
        localPath: '/x/downloads/g8vhps/index.m3u8',
        status: 3,
        videoUrl: 'https://example.test/master.m3u8',
      )..['totalBytes'] = 224962314);
      expect(item.status, DownloadStatus.completed);
      expect(item.sizeBytes, 224962314);
      expect(item.totalUnits, 0);
    });

    test('a manga chapter keeps its kind and counts pages', () {
      final item = DownloadItemModel.fromJson(legacy(
        localPath: '/x/downloads/g8vhps',
        status: 3,
        kind: 'manga',
        videoUrl: '',
      ));
      expect(item.kind, DownloadKind.manga);
      expect(item.unit, DownloadUnit.pages);
      expect(item.artefactIsDirectory, isTrue);
    });
  });

  test('a v2 row round-trips every field that matters', () {
    final original = itemWith(DownloadStatus.completed).copyWith(
      sizeBytes: 224962314,
      completedUnits: 648,
      totalUnits: 648,
      attempts: 2,
    );
    final restored =
        DownloadItemModel.fromJson(DownloadItemModel.toJson(original));
    expect(restored.sizeBytes, 224962314);
    expect(restored.completedUnits, 648);
    expect(restored.totalUnits, 648);
    expect(restored.attempts, 2);
    expect(restored.relativePath, original.relativePath);
  });
}
