import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/download/domain/entities/download_failure.dart';

void main() {
  group('DownloadFailureKind.classify', () {
    test('the engines\' own not-media words are a web page', () {
      expect(
        DownloadFailureKind.classify(
          'not media: the server answered with a web page (text/html)',
        ),
        DownloadFailureKind.notMedia,
      );
      // What the Android service wrote before 3.2.1.
      expect(
        DownloadFailureKind.classify(
          'not media: the server answered with text/html; charset=UTF-8',
        ),
        DownloadFailureKind.notMedia,
      );
    });

    test('a segment url ending in .html is not a web page', () {
      expect(
        DownloadFailureKind.classify(
          'could not fetch https://cdn.test/IgBCTApFy/content/page-3.html',
        ),
        isNot(DownloadFailureKind.notMedia),
      );
      expect(
        DownloadFailureKind.classify(
          'Connection reset while reading '
          'https://ifhid.test/seg-2-f1-v1-a1.html',
        ),
        DownloadFailureKind.network,
      );
    });

    test('the other buckets are unchanged', () {
      expect(DownloadFailureKind.classify('HTTP 403'), DownloadFailureKind.refused);
      expect(DownloadFailureKind.classify('HTTP 404'), DownloadFailureKind.gone);
      expect(
        DownloadFailureKind.classify('Read timed out'),
        DownloadFailureKind.network,
      );
      expect(
        DownloadFailureKind.classify('incomplete: 10 of 20 bytes'),
        DownloadFailureKind.incomplete,
      );
      expect(DownloadFailureKind.classify(''), DownloadFailureKind.unknown);
    });
  });
}
