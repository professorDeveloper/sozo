// Reader regressions exercise real widget controllers with fake repositories.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/features/anilist/data/anilist_tracker.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/detail/domain/entities/episode_entity.dart';
import 'package:soplay/features/detail/domain/repositories/detail_repository.dart';
import 'package:soplay/features/detail/domain/usecases/get_pages_usecase.dart';
import 'package:soplay/features/download/domain/entities/download_item.dart';
import 'package:soplay/features/download/domain/entities/download_request.dart';
import 'package:soplay/features/download/domain/repositories/download_repository.dart';
import 'package:soplay/features/download/domain/usecases/get_downloads_usecase.dart';
import 'package:soplay/features/download/domain/usecases/enqueue_download_usecase.dart';
import 'package:soplay/features/history/data/history_service.dart';
import 'package:soplay/features/history/domain/entities/history_item.dart';
import 'package:soplay/features/manga/domain/entities/manga_page_entity.dart';
import 'package:soplay/features/manga/domain/entities/manga_pages_entity.dart';
import 'package:soplay/features/manga/domain/entities/reader_args.dart';
import 'package:soplay/features/manga/presentation/pages/reader_page.dart';

class Settings implements HiveService {
  final bool spread;
  final String mode;
  Settings({this.spread = false, this.mode = 'horizontal'});
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
  // The reader asks before telling a tracker anything; incognito is the one
  // reader setting that reaches past this screen.
  @override
  bool get isIncognito => false;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Stands in for the real tracker so a finished chapter can be observed
/// without an account, a token or a network.
class Tracker implements AnilistTracker {
  Tracker({this.connected = false});
  bool connected;
  final reported = <int>[];
  @override
  bool get isConnected => connected;
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
  int enqueueCount = 0;
  EnqueueOutcome outcome = EnqueueOutcome.started;
  DownloadRequest? lastRequest;
  @override
  Future<List<MangaPageEntity>> localMangaPages(String id) async => [];
  @override
  DownloadItem? byId(String id) => null;
  @override
  Future<EnqueueOutcome> enqueue(DownloadRequest request) async {
    enqueueCount++;
    lastRequest = request;
    return outcome;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class Content implements DetailRepository {
  final bool novel;
  final refs = <String>[];
  Content({this.novel = false});
  @override
  Future<Result<MangaPagesEntity>> getPages({
    required String ref,
    required String provider,
  }) async {
    refs.add(ref);
    return Success(
      MangaPagesEntity(
        pages: novel
            ? []
            : List.generate(
                9,
                (i) => MangaPageEntity(
                  index: i,
                  imageUrl: '/tmp/sozo-reader-test-page-$i.png',
                  headers: {'Referer': 'page-$i'},
                  cookie: 'cookie-$i',
                ),
              ),
        headers: const {},
        html: novel
            ? List.generate(
                40,
                (i) =>
                    '<p>Chapter $ref, paragraph $i. Reading should scroll within this chapter.</p>',
              ).join()
            : null,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class History implements HistoryService {
  final saved = <HistoryItem>[];
  @override
  HistoryItem? get(String contentUrl, {int? episodeIndex, int? episodeNumber}) {
    final matching = saved.where(
      (i) => i.contentUrl == contentUrl && i.episodeNumber == episodeNumber,
    );
    return matching.isEmpty ? null : matching.last;
  }

  @override
  Future<void> save(HistoryItem item) async {
    saved.add(item);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// A tracker that is down, from the reader's point of view.
class Throwing extends Tracker {
  Throwing() : super(connected: true);
  int calls = 0;
  @override
  Future<int?> reportChapter({
    required String provider,
    required String contentUrl,
    required String title,
    required int chapterNumber,
  }) async {
    calls++;
    throw StateError('tracker down');
  }
}

Future<void> open(
  WidgetTester t, {
  required Settings settings,
  required Content content,
  int? resume = 0,
  History? history,
  Tracker? tracker,
}) async {
  getIt.registerSingleton<HiveService>(settings);
  getIt.registerSingleton<AnilistTracker>(tracker ?? Tracker());
  getIt.registerSingleton<GetDownloadsUseCase>(
    GetDownloadsUseCase(Downloads()),
  );
  getIt.registerSingleton<EnqueueDownloadUseCase>(
    EnqueueDownloadUseCase(getIt<GetDownloadsUseCase>().repository),
  );
  getIt.registerSingleton<GetPagesUseCase>(GetPagesUseCase(content));
  getIt.registerSingleton<HistoryService>(history ?? History());
  t.view.physicalSize = const Size(1200, 800);
  t.view.devicePixelRatio = 1;
  await t.pumpWidget(
    MaterialApp(
      home: ReaderPage(
        args: ReaderArgs(
          title: 'Audit',
          provider: 'test',
          contentUrl: 'test://title',
          resumePage: resume,
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
}

Future<void> close(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump();
  t.view.resetPhysicalSize();
  t.view.resetDevicePixelRatio();
  await getIt.reset();
}

void main() {
  tearDown(() async {
    await getIt.reset();
  });
  testWidgets('chapter transition flushes pending reading position', (t) async {
    await open(t, settings: Settings(), content: Content());
    final history = getIt<HistoryService>() as History;
    await t.pump(const Duration(milliseconds: 900));
    expect(history.saved.single.positionMs, 0);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pump();
    await t.pump(const Duration(milliseconds: 250));
    expect(find.text('2/9'), findsOneWidget);
    await t.tap(find.widgetWithIcon(IconButton, Icons.skip_next_rounded));
    await t.pump();
    await t.pump(const Duration(milliseconds: 900));
    expect(history.saved.where((v) => v.episodeNumber == 1).last.positionMs, 1);
    expect(history.saved.last.episodeNumber, 2);
    await close(t);
  });
  testWidgets('horizontal swipe reaches PageView despite tap overlay', (
    t,
  ) async {
    await open(t, settings: Settings(), content: Content());
    final view = t.widget<PageView>(find.byType(PageView));
    expect(view.controller!.page, 0);
    await t.drag(find.byType(PageView), const Offset(-700, 0));
    await t.pump(const Duration(milliseconds: 400));
    expect(view.controller!.page, greaterThan(0));
    await close(t);
  });
  testWidgets('chapter download preserves distinct image headers and cookies', (
    t,
  ) async {
    await open(t, settings: Settings(), content: Content());
    final downloads = getIt<GetDownloadsUseCase>().repository as Downloads;
    await t.tap(find.widgetWithIcon(IconButton, Icons.download_outlined));
    await t.pump();
    expect(downloads.lastRequest!.imageHeaders.length, 9);
    expect(downloads.lastRequest!.imageHeaders[0], {
      'Referer': 'page-0',
      'Cookie': 'cookie-0',
    });
    expect(downloads.lastRequest!.imageHeaders[1], {
      'Referer': 'page-1',
      'Cookie': 'cookie-1',
    });
    await close(t);
  });
  testWidgets('reader reports no space when download enqueue rejects', (
    t,
  ) async {
    await open(t, settings: Settings(), content: Content());
    final downloads = getIt<GetDownloadsUseCase>().repository as Downloads;
    downloads.outcome = EnqueueOutcome.noSpace;
    await t.tap(find.widgetWithIcon(IconButton, Icons.download_outlined));
    await t.pump();
    expect(downloads.enqueueCount, 1);
    expect(find.text('downloads.error.no_space'), findsOneWidget);
    expect(find.text('manga.download_started'), findsNothing);
    await close(t);
  });
  testWidgets(
    'spread restores containing slot and arrows navigate whole spreads',
    (t) async {
      await open(
        t,
        settings: Settings(spread: true),
        content: Content(),
        resume: 5,
      );
      var view = t.widget<PageView>(find.byType(PageView));
      expect(view.controller!.page, 3);
      expect(find.text('6/9'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(t.takeException(), isNull);
      expect(view.controller!.page, 4);
      expect(find.text('8/9'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(view.controller!.page, 3);
      // Moving to portrait must retain the current page, rather than an old offset.
      t.view.physicalSize = const Size(800, 1200);
      await t.pump();
      await t.pump();
      view = t.widget<PageView>(find.byType(PageView));
      expect(view.controller!.page, 5);
      await close(t);
    },
  );
  testWidgets('spread chapter change resets the spread controller to cover', (
    t,
  ) async {
    await open(
      t,
      settings: Settings(spread: true),
      content: Content(),
      resume: 5,
    );
    await t.tap(find.widgetWithIcon(IconButton, Icons.skip_next_rounded));
    await t.pump();
    await t.pump();
    expect(t.widget<PageView>(find.byType(PageView)).controller!.page, 0);
    expect(find.text('1/9'), findsOneWidget);
    await close(t);
  });
  testWidgets('novel PageDown scrolls prose and progress can seek', (t) async {
    final content = Content(novel: true);
    await open(
      t,
      settings: Settings(mode: 'vertical'),
      content: content,
    );
    expect(find.text('0%'), findsOneWidget);
    expect(find.text('1/0'), findsNothing);
    expect(t.widget<Slider>(find.byType(Slider)).onChanged, isNotNull);
    final scroll = t
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .controller!;
    await t.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(content.refs, ['one']);
    expect(scroll.offset, greaterThan(0));
    t.widget<Slider>(find.byType(Slider)).onChangeEnd!(500);
    await t.pump();
    expect(scroll.offset, closeTo(scroll.position.maxScrollExtent * .5, 1));
    expect(find.text('50%'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.end);
    await t.pump();
    expect(find.text('100%'), findsOneWidget);
    await close(t);
  });
  testWidgets(
    'novel horizontal preference does not turn edge taps into chapter skips',
    (t) async {
      final content = Content(novel: true);
      await open(t, settings: Settings(), content: content);
      await t.tapAt(const Offset(1000, 600));
      await t.pump();
      expect(content.refs, ['one']);
      await close(t);
    },
  );
  testWidgets('novel settings fit a short window and only show text controls', (
    t,
  ) async {
    await open(t, settings: Settings(), content: Content(novel: true));
    t.view.physicalSize = const Size(700, 450);
    await t.pump();
    await t.tap(find.widgetWithIcon(IconButton, Icons.tune));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(t.takeException(), isNull);
    expect(find.text('manga.text_size'), findsOneWidget);
    expect(find.text('manga.reading_mode'), findsNothing);
    await close(t);
  });
  testWidgets('novel download is disabled with an explanation', (t) async {
    await open(t, settings: Settings(), content: Content(novel: true));
    final button = find.widgetWithIcon(IconButton, Icons.download_outlined);
    expect(t.widget<IconButton>(button).onPressed, isNull);
    expect(find.byTooltip('manga.novel_download_unavailable'), findsOneWidget);
    expect(
      (getIt<GetDownloadsUseCase>().repository as Downloads).enqueueCount,
      0,
    );
    await close(t);
  });
  testWidgets(
    'offline-style args without resume restore saved chapter position',
    (t) async {
      final history = History();
      history.saved.add(
        const HistoryItem(
          contentUrl: 'test://title',
          provider: 'test',
          title: 'Audit',
          isSerial: true,
          episodeIndex: 0,
          episodeNumber: 1,
          positionMs: 4,
          durationMs: 8,
          watchedAt: 1,
        ),
      );
      await open(
        t,
        settings: Settings(),
        content: Content(),
        resume: null,
        history: history,
      );
      expect(t.widget<PageView>(find.byType(PageView)).controller!.page, 4);
      expect(find.text('5/9'), findsOneWidget);
      await close(t);
    },
  );
  testWidgets('explicit start-over overrides stored chapter position', (
    t,
  ) async {
    final history = History();
    history.saved.add(
      const HistoryItem(
        contentUrl: 'test://title',
        provider: 'test',
        title: 'Audit',
        isSerial: true,
        episodeIndex: 0,
        episodeNumber: 1,
        positionMs: 4,
        durationMs: 8,
        watchedAt: 1,
      ),
    );
    await open(
      t,
      settings: Settings(),
      content: Content(),
      resume: 0,
      history: history,
    );
    expect(t.widget<PageView>(find.byType(PageView)).controller!.page, 0);
    await close(t);
  });
  testWidgets('a chapter opened and abandoned tells the tracker nothing', (
    t,
  ) async {
    final tracker = Tracker(connected: true);
    await open(t, settings: Settings(), content: Content(), tracker: tracker);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('2/9'), findsOneWidget);
    await t.pump(const Duration(milliseconds: 900));
    expect(tracker.reported, isEmpty);
    await close(t);
  });
  testWidgets('a chapter read to its last page reports once, and only once', (
    t,
  ) async {
    final tracker = Tracker(connected: true);
    await open(t, settings: Settings(), content: Content(), tracker: tracker);
    await t.sendKeyEvent(LogicalKeyboardKey.end);
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('9/9'), findsOneWidget);
    await t.pump(const Duration(milliseconds: 900));
    expect(tracker.reported, [1]);
    // Paging back over the end and returning to it is ordinary reading, not a
    // second chapter.
    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    await t.sendKeyEvent(LogicalKeyboardKey.end);
    await t.pump();
    await t.pump(const Duration(milliseconds: 900));
    expect(tracker.reported, [1]);
    await close(t);
  });
  testWidgets('a novel chapter read to the end of its scroll reports', (
    t,
  ) async {
    // Prose is one long scroll with no last page, so the scroll position is
    // the only evidence there is that it was read.
    final tracker = Tracker(connected: true);
    await open(
      t,
      settings: Settings(mode: 'vertical'),
      content: Content(novel: true),
      tracker: tracker,
    );
    await t.pump(const Duration(milliseconds: 900));
    expect(tracker.reported, isEmpty);
    await t.sendKeyEvent(LogicalKeyboardKey.end);
    await t.pump();
    expect(find.text('100%'), findsOneWidget);
    await t.pump(const Duration(milliseconds: 900));
    expect(tracker.reported, [1]);
    await close(t);
  });
  testWidgets('nothing is reported while no tracker is connected', (t) async {
    final tracker = Tracker();
    await open(t, settings: Settings(), content: Content(), tracker: tracker);
    await t.sendKeyEvent(LogicalKeyboardKey.end);
    await t.pump();
    await t.pump(const Duration(milliseconds: 900));
    expect(tracker.reported, isEmpty);
    // Connecting mid-sitting: the chapter was finished, so the next time the
    // reader's position is recorded it must still be reportable.
    tracker.connected = true;
    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    await t.sendKeyEvent(LogicalKeyboardKey.end);
    await t.pump();
    await t.pump(const Duration(milliseconds: 900));
    expect(tracker.reported, [1]);
    await close(t);
  });
  testWidgets('a tracker that throws never reaches the reader', (t) async {
    // A dead tracker, an expired token and no network all arrive here as a
    // rejected future. None of them may put an error over the page.
    final tracker = Throwing();
    await open(t, settings: Settings(), content: Content(), tracker: tracker);
    await t.sendKeyEvent(LogicalKeyboardKey.end);
    await t.pump();
    await t.pump(const Duration(milliseconds: 900));
    expect(tracker.calls, 1);
    expect(t.takeException(), isNull);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('9/9'), findsOneWidget);
    await close(t);
  });
}
