// The furthest-page rule, exercised through the real readers.
//
// ChapterProgress is told how far somebody got; deciding that number is the
// reader's job and each of its three layouts answers it differently. These are
// the two layouts where the furthest page is not the current one.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/anilist/data/anilist_tracker.dart';
import 'package:soplay/features/detail/domain/entities/episode_entity.dart';
import 'package:soplay/features/detail/domain/repositories/detail_repository.dart';
import 'package:soplay/features/detail/domain/usecases/get_pages_usecase.dart';
import 'package:soplay/features/download/domain/entities/download_item.dart';
import 'package:soplay/features/download/domain/entities/download_request.dart';
import 'package:soplay/features/download/domain/repositories/download_repository.dart';
import 'package:soplay/features/download/domain/usecases/enqueue_download_usecase.dart';
import 'package:soplay/features/download/domain/usecases/get_downloads_usecase.dart';
import 'package:soplay/features/history/data/history_service.dart';
import 'package:soplay/features/history/domain/entities/history_item.dart';
import 'package:soplay/features/manga/domain/entities/manga_page_entity.dart';
import 'package:soplay/features/manga/domain/entities/manga_pages_entity.dart';
import 'package:soplay/features/manga/domain/entities/reader_args.dart';
import 'package:soplay/features/manga/presentation/pages/reader_page.dart';

class Settings implements HiveService {
  Settings({this.spread = false, this.mode = 'horizontal'});
  final bool spread;
  final String mode;
  @override
  bool get readerSpread => spread;
  @override
  String getReaderMode(String url) => mode;
  @override
  bool getReaderRtl(String url) => false;
  @override
  String getReaderBackground() => 'black';
  @override
  double getNovelFontSize() => 18;
  @override
  double getNovelLineHeight() => 1.62;
  @override
  String getNovelFontFamily() => '';
  @override
  bool getNovelJustify() => false;
  @override
  bool get isIncognito => false;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class Tracker implements AnilistTracker {
  final reported = <int>[];
  @override
  bool get isConnected => true;
  @override
  Future<int?> reportChapter({
    required String provider,
    required String contentUrl,
    required String title,
    required int chapterNumber,
  }) async {
    reported.add(chapterNumber);
    return 1;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class Downloads implements DownloadRepository {
  @override
  final revision = ValueNotifier<int>(0);
  @override
  Future<List<MangaPageEntity>> localMangaPages(String id) async => [];
  @override
  Future<String?> localChapterHtml(String id) async => null;
  @override
  DownloadItem? byId(String id) => null;
  @override
  Future<EnqueueOutcome> enqueue(DownloadRequest request) async =>
      EnqueueOutcome.started;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Nine pages, an odd count, so the spread reader's last slot holds two of
/// them — the case where the page under the reader's finger is not the last
/// page of the chapter.
class Content implements DetailRepository {
  Content({this.pageCount = 9});
  final int pageCount;
  @override
  Future<Result<MangaPagesEntity>> getPages({
    required String ref,
    required String provider,
  }) async => Success(
    MangaPagesEntity(
      pages: List.generate(
        pageCount,
        (i) => MangaPageEntity(
          index: i,
          // A path that does not exist, so every page lays out as the reader's
          // fixed-height error tile and the list has a known, stable extent.
          imageUrl: '/tmp/sozo-reader-report-test-$i.png',
          headers: const {},
        ),
      ),
      headers: const {},
    ),
  );

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class History implements HistoryService {
  final saved = <HistoryItem>[];
  @override
  HistoryItem? get(String contentUrl, {int? episodeIndex, int? episodeNumber}) =>
      null;
  @override
  Future<void> save(HistoryItem item) async => saved.add(item);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<Tracker> open(
  WidgetTester t, {
  required Settings settings,
  Content? content,
}) async {
  // A file that failed to load stays in the global image cache as a failure,
  // and a page that takes that failure from the cache is handed it before it
  // has a listener attached — so it never builds the error tile and lays out
  // flat. The cache outlives the widget tree, so without this the first page
  // of every test after the first is zero pixels tall and every rect below it
  // moves up by a page.
  imageCache.clear();
  imageCache.clearLiveImages();
  final tracker = Tracker();
  getIt.registerSingleton<HiveService>(settings);
  getIt.registerSingleton<AnilistTracker>(tracker);
  getIt.registerSingleton<GetDownloadsUseCase>(
    GetDownloadsUseCase(Downloads()),
  );
  getIt.registerSingleton<EnqueueDownloadUseCase>(
    EnqueueDownloadUseCase(getIt<GetDownloadsUseCase>().repository),
  );
  getIt.registerSingleton<GetPagesUseCase>(
    GetPagesUseCase(content ?? Content()),
  );
  getIt.registerSingleton<HistoryService>(History());
  // Registered here rather than run at the end of each test, so that a test
  // which fails partway still takes the reader down while its dependencies are
  // registered: the reader writes history from dispose, and unmounting it
  // after getIt has been reset throws over the top of the real failure and
  // fails the test after it as well.
  addTearDown(() async {
    await t.pumpWidget(const SizedBox());
    await t.pump();
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  });
  // A 1200x800 viewport, and pages that lay out as the reader's 220-pixel
  // error tile, so nine of them make a chapter two and a half screens tall
  // with known page rects.
  t.view.physicalSize = const Size(1200, 800);
  t.view.devicePixelRatio = 1;
  await t.pumpWidget(
    MaterialApp(
      home: ReaderPage(
        args: ReaderArgs(
          title: 'Audit',
          provider: 'test',
          contentUrl: 'test://title',
          resumePage: 0,
          chapters: const [
            EpisodeEntity(episode: 1, label: 'One', mediaRef: 'one'),
            EpisodeEntity(episode: 2, label: 'Two', mediaRef: 'two'),
          ],
        ),
      ),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 50));
  return tracker;
}

/// Lets the page images finish failing.
///
/// Their files do not exist, and the reader answers a missing image with a
/// fixed-height tile — but the read that fails is real I/O, which a widget
/// test's fake clock never gets to. Until it has, every page is zero pixels
/// tall and the list has nothing to scroll.
Future<void> settleImages(WidgetTester t) async {
  await t.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await t.pump();
}

/// Scrolls the continuous reader up by [pixels], and stops there.
///
/// A plain drag ends with the pointer still moving and the list carries on
/// under its own momentum, so where it lands is a fling curve rather than the
/// number asked for; holding still past the velocity tracker's horizon before
/// lifting leaves it where it was put. The first, small move pays the touch
/// slop, which is why the second one moves the list by exactly [pixels].
Future<void> scrollUp(WidgetTester t, double pixels) async {
  final gesture = await t.startGesture(const Offset(600, 400));
  await gesture.moveBy(const Offset(0, -20));
  await t.pump();
  await gesture.moveBy(Offset(0, -pixels));
  await t.pump();
  await t.pump(const Duration(milliseconds: 200));
  await gesture.up();
  await t.pumpAndSettle();
}

/// Where the ninth and last page of the chapter sits on the screen.
///
/// The tests say what the reader can see rather than how far it was dragged,
/// because "the bottom of the last page has been on screen" is the rule under
/// test and a pixel count is only evidence for it.
Rect lastPage(WidgetTester t) =>
    t.getRect(find.byKey(const ValueKey('v_0_8'), skipOffstage: false));

/// Long enough for the reader's save debounce to fire.
const settle = Duration(milliseconds: 900);

void main() {
  tearDown(() async {
    await getIt.reset();
  });

  testWidgets('the second page of the last spread finishes the chapter', (
    t,
  ) async {
    // Nine pages pair as [0] [1,2] [3,4] [5,6] [7,8]. The spread reader sits on
    // page 8 while reporting page 7 as current, so a rule that read the current
    // page would stop one page short of every odd-length chapter.
    final tracker = await open(t, settings: Settings(spread: true));
    await t.sendKeyEvent(LogicalKeyboardKey.end);
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('8/9'), findsOneWidget);
    await t.pump(settle);
    expect(tracker.reported, [1]);
  });

  testWidgets('the spread before the last one does not finish it', (t) async {
    // The slot holding pages 5 and 6 of 9 is not the end of anything, and the
    // mapping above must not be a blanket "close enough".
    final tracker = await open(t, settings: Settings(spread: true));
    for (var i = 0; i < 3; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
    }
    expect(find.text('6/9'), findsOneWidget);
    await t.pump(settle);
    expect(tracker.reported, isEmpty);
  });

  testWidgets('a continuous chapter scrolled to its end reports', (t) async {
    // The shipped default, and the mode where the current page is no evidence
    // at all: it is whatever straddles the top of the viewport, and at the
    // bottom of this chapter that is page 6 with the last two pages below it.
    final tracker = await open(t, settings: Settings(mode: 'vertical'));
    expect(find.byType(ScrollablePositionedList), findsOneWidget);
    await settleImages(t);
    expect(lastPage(t).top, greaterThan(800));
    await t.pump(settle);
    expect(tracker.reported, isEmpty);

    await scrollUp(t, 1400);
    expect(lastPage(t).bottom, lessThanOrEqualTo(800));
    // The page indicator, at the bottom of a finished chapter, naming a page
    // in the middle of it: this is the reading that the current page cannot
    // give a useful answer to.
    expect(find.text('7/9'), findsOneWidget);
    await t.pump(settle);
    expect(tracker.reported, [1]);
  });

  testWidgets('a continuous chapter scrolled partway does not report', (
    t,
  ) async {
    final tracker = await open(t, settings: Settings(mode: 'vertical'));
    await settleImages(t);
    await scrollUp(t, 400);
    expect(lastPage(t).top, greaterThan(800));
    await t.pump(settle);
    expect(tracker.reported, isEmpty);
  });

  testWidgets('the last page arriving on screen is not reading it', (t) async {
    // Scrolled so the last page has its top on screen and its bottom still
    // below the fold. Arriving at a page is not reading it, in the mode where
    // arriving is one flick.
    final tracker = await open(t, settings: Settings(mode: 'vertical'));
    await settleImages(t);
    await scrollUp(t, 1000);
    expect(lastPage(t).top, lessThan(800));
    expect(lastPage(t).bottom, greaterThan(800));
    await t.pump(settle);
    expect(tracker.reported, isEmpty);

    await scrollUp(t, 400);
    expect(lastPage(t).bottom, lessThanOrEqualTo(800));
    await t.pump(settle);
    expect(tracker.reported, [1]);
  });

  testWidgets('scrolling back up a finished chapter does not report twice', (
    t,
  ) async {
    // The high-water mark only rises, and the ledger only fires once; scrolling
    // back over pages already read is reading, not a second chapter.
    final tracker = await open(t, settings: Settings(mode: 'vertical'));
    await settleImages(t);
    await scrollUp(t, 1400);
    await t.pump(settle);
    expect(tracker.reported, [1]);

    await scrollUp(t, -1400);
    expect(lastPage(t).top, greaterThan(800));
    await t.pump(settle);
    expect(tracker.reported, [1]);
  });
}
