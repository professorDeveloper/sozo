// Read-aloud in the real reader, with a fake speech engine and fake sources.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/anilist/data/anilist_tracker.dart';
import 'package:soplay/features/detail/domain/entities/episode_entity.dart';
import 'package:soplay/features/detail/domain/repositories/detail_repository.dart';
import 'package:soplay/features/detail/domain/usecases/get_pages_usecase.dart';
import 'package:soplay/features/download/domain/entities/download_item.dart';
import 'package:soplay/features/download/domain/repositories/download_repository.dart';
import 'package:soplay/features/download/domain/usecases/enqueue_download_usecase.dart';
import 'package:soplay/features/download/domain/usecases/get_downloads_usecase.dart';
import 'package:soplay/features/history/data/history_service.dart';
import 'package:soplay/features/history/domain/entities/history_item.dart';
import 'package:soplay/features/manga/data/tts/tts_engine.dart';
import 'package:soplay/features/manga/domain/entities/manga_page_entity.dart';
import 'package:soplay/features/manga/domain/entities/manga_pages_entity.dart';
import 'package:soplay/features/manga/domain/entities/reader_args.dart';
import 'package:soplay/features/manga/presentation/pages/reader_page.dart';
import 'package:soplay/features/manga/presentation/tts/tts_player_bar.dart';

import 'fake_tts_engine.dart';

class Settings implements HiveService {
  double rate = 1.0;
  bool autoNext = true;
  String layout = 'scroll';
  final voices = <String, String>{};

  @override
  bool get readerSpread => false;
  @override
  String getReaderMode(String url) => 'vertical';
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
  String getNovelLayout() => layout;
  @override
  String getNovelTheme() => '';
  @override
  double getNovelMargin() => 20;
  @override
  bool get isIncognito => false;
  @override
  double getTtsRate() => rate;
  @override
  Future<void> saveTtsRate(double v) async => rate = v;
  @override
  double getTtsPitch() => 1.0;
  @override
  Future<void> saveTtsPitch(double v) async {}
  @override
  bool getTtsAutoNext() => autoNext;
  @override
  Future<void> saveTtsAutoNext(bool v) async => autoNext = v;
  @override
  String? getTtsVoice(String lang) => voices[lang];
  @override
  Future<void> saveTtsVoice(String lang, String? name) async {}
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class Tracker implements AnilistTracker {
  @override
  bool get isConnected => false;
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
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class Content implements DetailRepository {
  Content({this.long = false});
  final bool long;
  final refs = <String>[];
  @override
  Future<Result<MangaPagesEntity>> getPages({
    required String ref,
    required String provider,
  }) async {
    refs.add(ref);
    return Success(
      MangaPagesEntity(
        pages: const [],
        headers: const {},
        html: long
            ? '<h2>Chapter $ref</h2>'
                  '${List.generate(60, (i) => '<p>Line $i of $ref.</p>').join()}'
            : '<h2>Chapter $ref</h2><hr>'
                  '<p>First of $ref. Second of $ref.</p><p>Last of $ref.</p>',
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class History implements HistoryService {
  final saved = <HistoryItem>[];
  @override
  HistoryItem? get(
    String contentUrl, {
    int? episodeIndex,
    int? episodeNumber,
  }) => null;
  @override
  Future<void> save(HistoryItem item) async => saved.add(item);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  late FakeEngine engine;
  late Content content;
  late History history;

  Future<void> open(
    WidgetTester t, {
    String layout = 'scroll',
    bool long = false,
  }) async {
    engine = FakeEngine();
    content = Content(long: long);
    history = History();
    getIt.registerSingleton<HiveService>(Settings()..layout = layout);
    getIt.registerSingleton<AnilistTracker>(Tracker());
    getIt.registerSingleton<GetDownloadsUseCase>(
      GetDownloadsUseCase(Downloads()),
    );
    getIt.registerSingleton<EnqueueDownloadUseCase>(
      EnqueueDownloadUseCase(getIt<GetDownloadsUseCase>().repository),
    );
    getIt.registerSingleton<GetPagesUseCase>(GetPagesUseCase(content));
    getIt.registerSingleton<HistoryService>(history);
    getIt.registerSingleton<TtsEngine>(engine);
    t.view.physicalSize = const Size(1200, 800);
    t.view.devicePixelRatio = 1;
    await t.pumpWidget(
      const MaterialApp(
        home: ReaderPage(
          args: ReaderArgs(
            title: 'Audit',
            provider: 'test',
            contentUrl: 'test://title',
            resumePage: 0,
            chapters: [
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

  Future<void> finishSentence(WidgetTester t) async {
    engine.finish();
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  }

  tearDown(() async => getIt.reset());

  testWidgets('listen reads the chapter, shows the bar and paints the '
      'sentence', (t) async {
    await open(t);
    expect(find.byType(TtsPlayerBar), findsNothing);
    await t.tap(find.widgetWithIcon(IconButton, Icons.headphones_rounded));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    expect(engine.spoken, ['Chapter one']);
    expect(find.byType(TtsPlayerBar), findsOneWidget);

    await finishSentence(t);
    expect(engine.spoken.last, 'First of one.');
    final painted = <String>[];
    for (final w in t.widgetList<SelectableText>(find.byType(SelectableText))) {
      w.textSpan!.visitChildren((s) {
        if (s is TextSpan && s.style?.backgroundColor != null) {
          painted.add(s.text!);
        }
        return true;
      });
    }
    expect(painted, ['First of one.']);
    await close(t);
  });

  testWidgets('at the chapter end it loads the next one and keeps reading', (
    t,
  ) async {
    await open(t);
    await t.tap(find.widgetWithIcon(IconButton, Icons.headphones_rounded));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    for (var i = 0; i < 4; i++) {
      await finishSentence(t);
    }
    await t.pump(const Duration(milliseconds: 100));
    expect(content.refs, ['one', 'two']);
    expect(engine.spoken.last, 'Chapter two');
    // Heard to the end counts as read to the end.
    expect(
      history.saved.where((h) => h.episodeNumber == 1).last.positionMs,
      1000,
    );
    await close(t);
  });

  testWidgets('the bar pauses and resumes; leaving the reader stops it', (
    t,
  ) async {
    await open(t);
    await t.tap(find.widgetWithIcon(IconButton, Icons.headphones_rounded));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    await t.tap(find.byIcon(Icons.pause_rounded));
    await t.pump();
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    await t.tap(find.byIcon(Icons.play_arrow_rounded));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    expect(engine.spoken, ['Chapter one', 'Chapter one']);
    engine.calls.clear();
    await close(t);
    expect(engine.calls, contains('stop'));
  });

  testWidgets('space toggles reading while it is on', (t) async {
    await open(t);
    await t.tap(find.widgetWithIcon(IconButton, Icons.headphones_rounded));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.pump();
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    await close(t);
  });

  testWidgets('choosing another chapter stops reading', (t) async {
    await open(t);
    await t.tap(find.widgetWithIcon(IconButton, Icons.headphones_rounded));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    await t.tap(find.widgetWithIcon(IconButton, Icons.skip_next_rounded));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    expect(find.byType(TtsPlayerBar), findsNothing);
    await close(t);
  });
  testWidgets('the settings sheet carries the read-aloud controls', (t) async {
    await open(t);
    engine.voiceList = const [
      TtsVoice(name: 'en-us-x-iol-local', locale: 'en-US'),
      TtsVoice(name: 'ru-ru-x-dfc-local', locale: 'ru-RU'),
    ];
    await t.tap(find.widgetWithIcon(IconButton, Icons.tune));
    await t.pumpAndSettle();
    expect(find.byType(TtsSettingsSection), findsOneWidget);
    await t.ensureVisible(find.text('manga.tts_voice').first);
    await t.pumpAndSettle();
    await t.tap(find.text('manga.tts_voice').first);
    await t.pumpAndSettle();
    // Only the chapter's language is offered.
    expect(find.text('en-us-x-iol-local'), findsOneWidget);
    expect(find.text('ru-ru-x-dfc-local'), findsNothing);
    await close(t);
  });

  testWidgets('in the book layout the voice paints on the page and turns '
      'it when it reads on', (t) async {
    await open(t, layout: 'book', long: true);
    String counter() => t
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data ?? '')
        .firstWhere((s) => RegExp(r'^\d+/\d+$').hasMatch(s));
    expect(counter(), startsWith('1/'));
    await t.tap(find.widgetWithIcon(IconButton, Icons.headphones_rounded));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    expect(engine.spoken, ['Chapter one']);
    await finishSentence(t);
    expect(engine.spoken.last, 'Line 0 of one.');
    var painted = false;
    for (final w in t.widgetList<SelectableText>(find.byType(SelectableText))) {
      w.textSpan!.visitChildren((s) {
        if (s is TextSpan &&
            s.text == 'Line 0 of one.' &&
            s.style?.backgroundColor != null) {
          painted = true;
        }
        return true;
      });
    }
    expect(painted, isTrue);
    for (var i = 0; i < 30 && counter().startsWith('1/'); i++) {
      await finishSentence(t);
      await t.pump(const Duration(milliseconds: 700));
    }
    expect(counter(), startsWith('2/'));
    expect(t.takeException(), isNull);
    await close(t);
  });
}
