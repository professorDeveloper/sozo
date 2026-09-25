// A novel chapter could not be downloaded at all.
//
// A comic source implements `getPageList` and answers with image urls; a novel
// source implements `getHtmlContent` and answers with one document. The
// download path only ever looked at the first, so a novel chapter arrived with
// zero pages and the transfer failed the whole thing with "the chapter has no
// pages" — on a shelf the app has a reader for.
//
// The fix is a second shape, not a second kind: prose, plus whatever pictures
// the prose points at, written into the same folder so deleting the chapter
// takes the pictures with the words.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/download/data/datasources/download_transfer_data_source.dart';

void main() {
  group('finding the pictures in a chapter', () {
    test('a plain img is found', () {
      expect(
        DownloadTransferDataSource.imageSources(
          '<p>words</p><img src="https://cdn.test/a.jpg"><p>more</p>',
        ),
        ['https://cdn.test/a.jpg'],
      );
    });

    test('single quotes, no quotes, and other attributes first', () {
      final found = DownloadTransferDataSource.imageSources(
        "<img alt='x' class=\"big\" src='https://cdn.test/b.png'>"
        '<img data-n=1 src=https://cdn.test/c.gif >',
      );
      expect(found, ['https://cdn.test/b.png', 'https://cdn.test/c.gif']);
    });

    test('the same picture twice is one file', () {
      expect(
        DownloadTransferDataSource.imageSources(
          '<img src="https://cdn.test/a.jpg"><img src="https://cdn.test/a.jpg">',
        ),
        ['https://cdn.test/a.jpg'],
      );
    });

    test('a data uri is already in the document', () {
      // Fetching it would write the same bytes to disk a second time.
      expect(
        DownloadTransferDataSource.imageSources(
          '<img src="data:image/png;base64,iVBORw0KGgo=">',
        ),
        isEmpty,
      );
    });

    test('an href is not a picture', () {
      expect(
        DownloadTransferDataSource.imageSources(
          '<a href="https://cdn.test/a.jpg">link</a>',
        ),
        isEmpty,
      );
    });
  });

  group('pointing the chapter at what was saved', () {
    test('the src is replaced, the link beside it is not', () {
      // A url that also appears in an href must keep pointing where it pointed.
      const html =
          '<a href="https://cdn.test/a.jpg">source</a>'
          '<img src="https://cdn.test/a.jpg">';
      final out = DownloadTransferDataSource.rewriteImageSources(html, {
        'https://cdn.test/a.jpg': 'p_000.jpg',
      });
      expect(out, contains('<a href="https://cdn.test/a.jpg">'));
      expect(out, contains('src="p_000.jpg"'));
    });

    test('one url that is a prefix of another does not eat it', () {
      const html =
          '<img src="https://cdn.test/a.jpg">'
          '<img src="https://cdn.test/a.jpg?big=1">';
      final out = DownloadTransferDataSource.rewriteImageSources(html, {
        'https://cdn.test/a.jpg': 'p_000.jpg',
        'https://cdn.test/a.jpg?big=1': 'p_001.jpg',
      });
      expect(out, contains('src="p_000.jpg"'));
      expect(out, contains('src="p_001.jpg"'));
    });

    test('a picture that was not saved keeps its original url', () {
      // An image that would not fetch must not cost the chapter. It loads when
      // there is signal and shows a gap when there is not.
      const html = '<img src="https://cdn.test/gone.jpg">';
      expect(
        DownloadTransferDataSource.rewriteImageSources(html, const {}),
        html,
      );
    });

    test('and the prose around it is untouched', () {
      const html = '<p>The word src="x" appears here.</p><img src="u">';
      final out = DownloadTransferDataSource.rewriteImageSources(html, {
        'u': 'p_000.jpg',
      });
      expect(out, contains('The word src="x" appears here.'));
      expect(out, contains('<img src="p_000.jpg">'));
    });

    test('the rewrite runs both ways over the same rule', () {
      // Once on the way to disk, once on the way back out. A file name becomes
      // an absolute path with no second notion of what a src is.
      const original = '<img src="https://cdn.test/a.jpg">';
      final saved = DownloadTransferDataSource.rewriteImageSources(original, {
        'https://cdn.test/a.jpg': 'p_000.jpg',
      });
      final opened = DownloadTransferDataSource.rewriteImageSources(saved, {
        'p_000.jpg': '${Directory.systemTemp.path}/chapter/p_000.jpg',
      });
      expect(opened, contains(Directory.systemTemp.path));
    });
  });

  group('the shape is decided once, at resolve time', () {
    String read(String path) => File(path).readAsStringSync();

    test('a text chapter is stored as prose, not as zero pages', () {
      final repo = read(
        'lib/features/download/data/repositories/download_repository_impl.dart',
      );
      expect(repo, contains('if (result.value.isText)'));
      expect(repo, contains('chapterHtml: result.value.html'));
    });

    test('and the transfer branches on it rather than failing', () {
      final transfer = read(
        'lib/features/download/data/datasources/download_transfer_data_source.dart',
      );
      expect(transfer, contains("(chapterHtml ?? '').trim().isNotEmpty"));
      expect(transfer, contains('await _prose('));
    });

    test('prose stays in-process even where a native downloader exists', () {
      // The native downloader takes a url or a page list and knows nothing
      // about prose; a chapter would reach it with an empty list and fail.
      final repo = read(
        'lib/features/download/data/repositories/download_repository_impl.dart',
      );
      expect(repo, contains('if (_useNative && !current.isProse)'));
    });

    test('the reader looks for prose before it looks for pages', () {
      // Asking for pages first would find the chapter's illustrations and
      // render a novel as a comic.
      final reader = read(
        'lib/features/manga/presentation/pages/reader_page.dart',
      );
      final htmlAt = reader.indexOf('localChapterHtml(localId)');
      final pagesAt = reader.indexOf('localMangaPages(localId)');
      expect(htmlAt, greaterThan(-1));
      expect(pagesAt, greaterThan(-1));
      expect(htmlAt, lessThan(pagesAt));
    });
  });
}
