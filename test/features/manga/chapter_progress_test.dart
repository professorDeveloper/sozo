import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/manga/domain/reading/chapter_progress.dart';

void main() {
  group('when a comic chapter counts as read', () {
    test('opening it is not reading it', () {
      // Somebody opening a chapter to look at the art has read nothing, and a
      // list that says otherwise is a list they have to go and correct.
      expect(ChapterProgress.isComicRead(furthestPage: 0, pageCount: 20),
          isFalse);
      expect(ChapterProgress.isComicRead(furthestPage: 18, pageCount: 20),
          isFalse);
    });

    test('the last page is', () {
      expect(
        ChapterProgress.isComicRead(furthestPage: 19, pageCount: 20),
        isTrue,
      );
    });

    test('a one-page chapter is read as soon as it is open', () {
      // Deliberate, not a gap. The only page is the whole chapter and it is
      // already on screen; furthestPage can never grow past 0, so any stricter
      // rule would mean a one-page chapter is never reported at all. The
      // spread mapping that feeds furthestPage is the reader's, and is
      // exercised in reader_chapter_report_test.dart.
      expect(
        ChapterProgress.isComicRead(furthestPage: 0, pageCount: 1),
        isTrue,
      );
    });

    test('a chapter with no pages is never read', () {
      // That is a chapter whose source failed, not one somebody finished.
      expect(
        ChapterProgress.isComicRead(furthestPage: 0, pageCount: 0),
        isFalse,
      );
    });
  });

  group('when a novel chapter counts as read', () {
    test('the top of the scroll is not it', () {
      expect(ChapterProgress.isProseRead(0), isFalse);
      expect(ChapterProgress.isProseRead(500), isFalse);
    });

    test('the last stretch of the scroll is', () {
      // Prose has no last page, and the very bottom is one exact pixel behind
      // whatever the source appended, so it cannot be the test.
      expect(ChapterProgress.isProseRead(949), isFalse);
      expect(ChapterProgress.isProseRead(950), isTrue);
      expect(ChapterProgress.isProseRead(1000), isTrue);
    });

    test('the threshold is reachable on the reader\'s own scale', () {
      // The reader only records prose position once it has moved five
      // thousandths, so a threshold it can step over is no threshold at all.
      expect(ChapterProgress.proseReadPermille % 5, 0);
    });
  });

  group('a tracker hears once', () {
    test('reading it again does not report again', () {
      // Paging back over the end, or reopening a finished chapter, is
      // ordinary reading — and used to be the way to write the same chapter
      // to AniList repeatedly.
      final p = ChapterProgress();
      expect(p.chapterToReport(7), 7);
      expect(p.chapterToReport(7), isNull);
      expect(p.hasReported(7), isTrue);
    });

    test('the next chapter still reports', () {
      final p = ChapterProgress();
      p.chapterToReport(7);
      expect(p.chapterToReport(8), 8);
    });

    test('a chapter numbered zero or less is never reported', () {
      // Sources number extras and omakes that way. "Chapter 0 read" on
      // somebody's list is not something the reader can see happen or undo.
      final p = ChapterProgress();
      expect(p.chapterToReport(0), isNull);
      expect(p.chapterToReport(-1), isNull);
    });
  });

  test('the domain layer stays free of Flutter', () {
    final source = File(
      'lib/features/manga/domain/reading/chapter_progress.dart',
    ).readAsStringSync();
    expect(source.contains('package:flutter/'), isFalse);
    expect(source.contains('get_it'), isFalse);
  });
}
