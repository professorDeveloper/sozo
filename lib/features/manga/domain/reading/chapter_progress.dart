/// When a chapter counts as read, and the once-per-chapter ledger that goes
/// with it.
///
/// The reader is the second place in the app that has to answer "has enough of
/// this happened to tell somebody's tracker about it", and the player's answer
/// (`WatchProgress`) does not transfer: a chapter has no duration, and the two
/// shapes a chapter comes in do not even share a unit. A comic is a list of
/// pages; a novel chapter is one continuous scroll with no page index at all,
/// which is why the reader carries prose position in thousandths.
///
/// Both rules exist for the same reason the player's threshold does — opening
/// a chapter is not reading it, and a tracker that hears about every chapter
/// somebody glanced at is worse than one that misses a few.
///
/// Pure: numbers in, answers out. No Flutter, no I/O, no clock of its own.
library;

/// The rules, and the ledger that keeps a tracker from hearing twice.
class ChapterProgress {
  ChapterProgress();

  /// How far through a novel chapter counts as having read it, in the same
  /// thousandths the reader stores prose position in.
  ///
  /// Not 1000. The bottom of a scroll view is one exact pixel, and prose ends
  /// in whatever the source appended — translator notes, a footer, the
  /// reader's own bottom padding — so requiring the very end would quietly
  /// never fire for somebody who read every word. The reader also only records
  /// a position once it has moved half a percent, so this has to be a value
  /// that a coarse scale can actually land on or pass.
  static const int proseReadPermille = 950;

  /// Chapters already reported this session, so a tracker hears once.
  ///
  /// Chapter numbers, not indices: two chapters of one title never share a
  /// number, and the number is what a tracker is told.
  final Set<int> _reported = <int>{};

  /// Whether a comic chapter showing pages up to [furthestPage] (zero-based)
  /// out of [pageCount] has been read.
  ///
  /// The last page, not a fraction of the way in. A comic's final pages are
  /// the ones the chapter was building to, unlike a video's credits, so there
  /// is nothing here that corresponds to the player's 85%.
  ///
  /// [furthestPage] is the furthest page ON SCREEN rather than the current
  /// one, because the double-page reader shows two: its last slot can start at
  /// `pageCount - 2`, and a chapter with an even page count would otherwise
  /// never be read at all.
  ///
  /// False for a chapter with no pages — that is a chapter that failed to
  /// load, and reporting one would mark a title read because its source was
  /// down.
  ///
  /// True for a one-page chapter from the moment it is open, and that is the
  /// intended answer rather than an edge the rule fell through. One page is
  /// the whole chapter and it is already on screen; there is nothing left to
  /// turn to, so [furthestPage] can never grow past 0 and any stricter rule
  /// would mean a colour page, an announcement or a one-shot extra could never
  /// be reported at all. Unlike the zero-page case there is nothing here to
  /// suspect: a page did load.
  static bool isComicRead({required int furthestPage, required int pageCount}) {
    if (pageCount <= 0) return false;
    return furthestPage >= pageCount - 1;
  }

  /// Whether a novel chapter scrolled to [permille] has been read.
  ///
  /// Prose has no last page to reach, so the scroll position is the only
  /// evidence there is. A chapter too short to scroll never moves off zero and
  /// so is never reported; see [proseReadPermille].
  static bool isProseRead(int permille) => permille >= proseReadPermille;

  /// The chapter number a tracker should be told about, or null when it should
  /// not be told anything.
  ///
  /// Null covers a chapter the source numbered 0 or less — extras and omakes
  /// are numbered that way, and "chapter 0 read" written onto a list is not
  /// something the reader can see happen or undo — and a chapter already
  /// reported, which is what re-reading, scrolling back and forth over the
  /// end, or closing and reopening a finished chapter all look like from here.
  ///
  /// [chapterNumber] is not nullable. A chapter that reaches here came from an
  /// EpisodeEntity, whose `episode` is an `int`; a source that gives a chapter
  /// no number at all arrives as 0, which the rule above already covers.
  int? chapterToReport(int chapterNumber) {
    if (chapterNumber <= 0) return null;
    if (!_reported.add(chapterNumber)) return null;
    return chapterNumber;
  }

  /// Whether [chapterNumber] has already been reported this session.
  bool hasReported(int chapterNumber) => _reported.contains(chapterNumber);
}
