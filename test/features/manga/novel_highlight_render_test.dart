// Highlights drawn into the prose, whole or cut to a book page, and offered
// from the selection menu.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/manga/presentation/widgets/novel_text.dart';

const yellow = Color(0x80FFD54F);
const blue = Color(0x8064B5F6);

Future<List<TextSpan>> spansOf(
  WidgetTester t,
  String html, {
  List<NovelMark> marks = const [],
  List<NovelSlice>? slices,
  String query = '',
}) async {
  await t.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: NovelText(
          html: html,
          color: Colors.white,
          fontSize: 16,
          marks: marks,
          slices: slices,
          query: query,
        ),
      ),
    ),
  );
  final text = t.widget<SelectableText>(find.byType(SelectableText).first);
  return text.textSpan!.children!.whereType<TextSpan>().toList();
}

String painted(List<TextSpan> spans, Color color) => [
  for (final s in spans)
    if (s.style?.backgroundColor == color) s.text!,
].join();

void main() {
  testWidgets('a highlight paints its range and nothing else', (t) async {
    final spans = await spansOf(
      t,
      '<p>The quick brown fox jumps.</p>',
      marks: const [NovelMark(0, 4, 15, yellow)],
    );
    expect(painted(spans, yellow), 'quick brown');
    expect(spans.map((s) => s.text).join(), 'The quick brown fox jumps.');
  });

  testWidgets('across emphasis runs, keeping the emphasis', (t) async {
    final spans = await spansOf(
      t,
      '<p>He said <b>no</b> twice.</p>',
      marks: const [NovelMark(0, 3, 14, yellow)],
    );
    expect(painted(spans, yellow), 'said no twi');
    expect(
      spans.singleWhere((s) => s.text == 'no').style?.fontWeight,
      FontWeight.w700,
    );
  });

  testWidgets('a note shows as a dotted underline', (t) async {
    final spans = await spansOf(
      t,
      '<p>Mark me with a note.</p>',
      marks: const [NovelMark(0, 0, 7, blue, noted: true)],
    );
    final marked = spans.firstWhere((s) => s.text == 'Mark me');
    expect(marked.style?.decoration, TextDecoration.underline);
    expect(marked.style?.decorationStyle, TextDecorationStyle.dotted);
  });

  testWidgets('only the marks of the block they belong to', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NovelText(
            html: '<p>First block.</p><p>Second block.</p>',
            color: Colors.white,
            fontSize: 16,
            marks: const [NovelMark(1, 0, 6, yellow)],
          ),
        ),
      ),
    );
    final texts = t
        .widgetList<SelectableText>(find.byType(SelectableText))
        .map((w) => w.textSpan!.children!.whereType<TextSpan>().toList())
        .toList();
    expect(painted(texts[0], yellow), isEmpty);
    expect(painted(texts[1], yellow), 'Second');
  });

  testWidgets('on a book page the highlight is cut with the text', (t) async {
    // The page holds characters 10.. of the paragraph; the highlight runs
    // from 4 to 15, so only 10..15 of it is on this page.
    final spans = await spansOf(
      t,
      '<p>The quick brown fox jumps.</p>',
      marks: const [NovelMark(0, 4, 15, yellow)],
      slices: const [NovelSlice(0, 10, 26)],
    );
    expect(spans.map((s) => s.text).join(), 'brown fox jumps.');
    expect(painted(spans, yellow), 'brown');
  });

  testWidgets('find still marks a word that a highlight splits', (t) async {
    final spans = await spansOf(
      t,
      '<p>Sunday came.</p>',
      marks: const [NovelMark(0, 0, 3, yellow)],
      query: 'sunday',
    );
    final found = spans.where(
      (s) => s.style?.backgroundColor == const Color(0x66FFD54F),
    );
    expect(found.map((s) => s.text).join(), 'Sunday');
  });

  testWidgets('the selection menu offers Highlight, in block offsets', (
    t,
  ) async {
    (int, int, int)? picked;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NovelText(
            html: '<p>Alpha beta gamma delta.</p>',
            color: Colors.white,
            fontSize: 20,
            // A page that starts at "gamma".
            slices: const [NovelSlice(0, 11, 23)],
            onHighlight: (b, s, e) => picked = (b, s, e),
          ),
        ),
      ),
    );
    await t.longPressAt(
      t.getTopLeft(find.byType(SelectableText)) + const Offset(8, 10),
    );
    await t.pumpAndSettle();
    expect(find.text('manga.highlight'), findsOneWidget);
    expect(find.text('manga.remove_highlight'), findsNothing);
    await t.tap(find.text('manga.highlight'));
    await t.pumpAndSettle();
    expect(picked, isNotNull);
    final (block, start, end) = picked!;
    expect(block, 0);
    expect('Alpha beta gamma delta.'.substring(start, end), 'gamma');
  });

  testWidgets('and Remove highlight over one that exists', (t) async {
    (int, int, int)? removed;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NovelText(
            html: '<p>Alpha beta gamma delta.</p>',
            color: Colors.white,
            fontSize: 20,
            marks: const [NovelMark(0, 0, 10, yellow)],
            onHighlight: (_, _, _) {},
            onUnhighlight: (b, s, e) => removed = (b, s, e),
          ),
        ),
      ),
    );
    await t.longPressAt(
      t.getTopLeft(find.byType(SelectableText)) + const Offset(8, 10),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('manga.remove_highlight'));
    await t.pumpAndSettle();
    expect(removed?.$1, 0);
    expect(removed!.$2, lessThan(10));
  });
}
