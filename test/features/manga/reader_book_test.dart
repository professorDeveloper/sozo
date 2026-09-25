// The novel reader's book layout and highlights, in the real reader.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:soplay/core/constants/app_constants.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/features/history/data/history_service.dart';
import 'package:soplay/features/manga/data/novel_highlight_store.dart';
import 'package:soplay/features/manga/domain/reading/novel_highlight.dart';
import 'package:soplay/features/manga/presentation/widgets/page_curl.dart';

import 'reader_page_test.dart' show Content, History, Settings, close, open;

/// The page counter in the bottom bar, as (page, pages).
(int, int) counter(WidgetTester t) {
  final label = t
      .widgetList<Text>(find.byType(Text))
      .map((w) => w.data ?? '')
      .firstWhere((s) => RegExp(r'^\d+/\d+$').hasMatch(s));
  final parts = label.split('/');
  return (int.parse(parts[0]), int.parse(parts[1]));
}

/// A finger's swipe: many small moves, the way a screen reports one.
Future<void> swipe(WidgetTester t, Offset from, Offset by) async {
  final gesture = await t.startGesture(from);
  const steps = 40;
  for (var i = 0; i < steps; i++) {
    await gesture.moveBy(by / steps.toDouble());
    await t.pump(const Duration(milliseconds: 8));
  }
  await gesture.up();
}

Future<void> settle(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 700));
}

void main() {
  tearDown(() async => getIt.reset());

  testWidgets('book layout pages the chapter and turns by tap, key and '
      'swipe', (t) async {
    final content = Content(novel: true);
    await open(
      t,
      settings: Settings(mode: 'vertical', layout: 'book'),
      content: content,
    );
    expect(find.byType(PageCurlView), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsNothing);
    final (first, pages) = counter(t);
    expect(first, 1);
    expect(pages, greaterThan(2));

    await t.tapAt(const Offset(1100, 300));
    await settle(t);
    expect(counter(t).$1, 2);

    await t.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await settle(t);
    expect(counter(t).$1, 3);

    await swipe(t, const Offset(500, 300), const Offset(400, 0));
    await settle(t);
    expect(counter(t).$1, 2);

    await t.tapAt(const Offset(60, 300));
    await settle(t);
    expect(counter(t).$1, 1);

    await swipe(t, const Offset(900, 500), const Offset(-500, -40));
    await settle(t);
    expect(counter(t).$1, 2);
    expect(t.takeException(), isNull);

    // Progress is saved from the page, in the thousandths prose uses.
    await t.pump(const Duration(milliseconds: 900));
    final history = getIt<HistoryService>() as History;
    expect(history.saved.last.durationMs, 1000);
    expect(history.saved.last.positionMs, greaterThan(0));
    await close(t);
  });

  testWidgets('a short drag that does not reach halfway springs back', (
    t,
  ) async {
    await open(
      t,
      settings: Settings(mode: 'vertical', layout: 'book'),
      content: Content(novel: true),
    );
    final gesture = await t.startGesture(const Offset(900, 400));
    for (var i = 0; i < 8; i++) {
      await gesture.moveBy(const Offset(-12, 0));
      await t.pump(const Duration(milliseconds: 100));
    }
    await gesture.up();
    await settle(t);
    expect(counter(t).$1, 1);
    await close(t);
  });

  testWidgets('turning past the last page opens the next chapter, and back '
      'past the first returns to the end of the previous one', (t) async {
    final content = Content(novel: true);
    await open(
      t,
      settings: Settings(mode: 'vertical', layout: 'book'),
      content: content,
    );
    await t.sendKeyEvent(LogicalKeyboardKey.end);
    await settle(t);
    final (last, pages) = counter(t);
    expect(last, pages);
    await t.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await settle(t);
    expect(content.refs, ['one', 'two']);
    expect(counter(t).$1, 1);

    await t.sendKeyEvent(LogicalKeyboardKey.pageUp);
    await settle(t);
    expect(content.refs, ['one', 'two', 'one']);
    final (page, total) = counter(t);
    expect(page, total);
    await close(t);
  });

  testWidgets('the layout is switched from the settings sheet and keeps the '
      'place', (t) async {
    final settings = Settings(mode: 'vertical', layout: 'book');
    await open(t, settings: settings, content: Content(novel: true));
    await t.sendKeyEvent(LogicalKeyboardKey.end);
    await settle(t);
    await t.tap(find.widgetWithIcon(IconButton, Icons.tune));
    await t.pumpAndSettle();
    await t.tap(find.text('manga.mode_scroll'));
    await t.pumpAndSettle();
    expect(settings.layout, 'scroll');
    expect(find.byType(PageCurlView), findsNothing);
    final scroll = t
        .widget<SingleChildScrollView>(
          find.byWidgetPredicate(
            (w) => w is SingleChildScrollView && w.controller != null,
          ),
        )
        .controller!;
    expect(scroll.offset, closeTo(scroll.position.maxScrollExtent, 1));
    await close(t);
  });

  group('highlights', () {
    late Directory dir;
    final store = NovelHighlightStore();

    Future<void> seed(WidgetTester t, List<NovelHighlight> items) =>
        t.runAsync(() async {
          dir = await Directory.systemTemp.createTemp('reader_highlights');
          Hive.init(dir.path);
          await Hive.openBox(AppConstants.settingsBox);
          for (final h in items) {
            await store.add('test', 'test://title', h);
          }
        });

    Future<void> unseed(WidgetTester t) => t.runAsync(() async {
      await Hive.close();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    NovelHighlight at(String ref, int chapter, int block, {String note = ''}) =>
        NovelHighlight(
          id: '$ref-$block',
          chapterRef: ref,
          chapter: chapter,
          chapterLabel: ref == 'one' ? 'One' : 'Two',
          block: block,
          start: 0,
          end: 7,
          text: 'Chapter',
          color: HighlightColor.green,
          note: note,
          createdAt: 1,
        );

    bool paintsGreen(WidgetTester t) {
      final green = Color(HighlightColor.green.argb);
      for (final w in t.widgetList<SelectableText>(
        find.byType(SelectableText),
      )) {
        var found = false;
        w.textSpan!.visitChildren((s) {
          final bg = s.style?.backgroundColor;
          if (bg != null &&
              bg.withValues(alpha: 1).toARGB32() == green.toARGB32()) {
            found = true;
          }
          return !found;
        });
        if (found) return true;
      }
      return false;
    }

    testWidgets('are drawn in the scroll layout and in the book', (t) async {
      await seed(t, [at('one', 1, 0)]);
      await open(
        t,
        settings: Settings(mode: 'vertical'),
        content: Content(novel: true),
      );
      expect(paintsGreen(t), isTrue);
      await close(t);

      await open(
        t,
        settings: Settings(mode: 'vertical', layout: 'book'),
        content: Content(novel: true),
      );
      expect(paintsGreen(t), isTrue);
      await close(t);
      await unseed(t);
    });

    testWidgets('the list opens from the menu and jumps to another '
        "chapter's highlight", (t) async {
      await seed(t, [at('one', 1, 1), at('two', 2, 30, note: 'the end')]);
      final content = Content(novel: true);
      await open(
        t,
        settings: Settings(mode: 'vertical', layout: 'book'),
        content: content,
      );
      await t.tap(find.byIcon(Icons.more_vert_rounded));
      await t.pumpAndSettle();
      await t.tap(find.text('manga.highlights'));
      await t.pumpAndSettle();
      expect(find.text('the end'), findsOneWidget);
      expect(find.text('TWO'), findsOneWidget);
      await t.tap(find.text('the end'));
      await settle(t);
      expect(content.refs, ['one', 'two']);
      // Paragraph 30 of 40 is well past the first page.
      final (page, pages) = counter(t);
      expect(page, greaterThan(1));
      expect(page, lessThanOrEqualTo(pages));
      await close(t);
      await unseed(t);
    });
  });
}
