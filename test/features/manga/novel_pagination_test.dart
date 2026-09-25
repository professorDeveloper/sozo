// Book layout: the chapter cut into pages that hold exactly what fits.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/manga/presentation/widgets/novel_pagination.dart';
import 'package:soplay/features/manga/presentation/widgets/novel_text.dart';

final String chapter = [
  '<h2>Chapter Seven</h2>',
  for (var i = 0; i < 14; i++)
    '<p>Paragraph $i. ${'The river ran on past the mill and under the bridge. ' * (1 + i % 5)}</p>',
  '<hr>',
  '<p>${'A very long closing paragraph that will not fit on one page. ' * 40}</p>',
].join();

NovelPageMetrics metricsFor(
  BuildContext context, {
  double width = 320,
  double height = 420,
  double fontSize = 16,
  double inset = 0,
  bool justify = false,
  TextScaler scaler = TextScaler.noScaling,
}) => NovelPageMetrics(
  width: width,
  height: height,
  fontSize: fontSize,
  lineHeight: 1.6,
  justify: justify,
  textScaler: scaler,
  paragraphSpacing: fontSize * 1.6 * 0.85,
  baseStyle: DefaultTextStyle.of(context).style,
  firstPageInset: inset,
);

/// Pumps a scaffold and hands back its context, so the metrics carry the
/// same ambient style the reader's pages do.
Future<BuildContext> host(WidgetTester t) async {
  late BuildContext ctx;
  await t.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox();
          },
        ),
      ),
    ),
  );
  return ctx;
}

String joined(List<NovelBlock> blocks, List<NovelPage> pages) {
  final out = StringBuffer();
  for (final page in pages) {
    for (final s in page.slices) {
      out.write(blocks[s.block].text.substring(s.start, s.end));
      out.write('|');
    }
  }
  return out.toString();
}

void main() {
  final blocks = parseNovelBlocks(chapter);

  testWidgets('every character lands on exactly one page, in order', (t) async {
    final ctx = await host(t);
    final pages = paginateNovel(blocks, metricsFor(ctx));
    expect(pages.length, greaterThan(3));
    final text = joined(blocks, pages).replaceAll('|', '');
    expect(text, blocks.map((b) => b.text).join());
  });

  testWidgets('a paragraph too long for a page carries on over the next', (
    t,
  ) async {
    final ctx = await host(t);
    final pages = paginateNovel(blocks, metricsFor(ctx));
    final last = blocks.length - 1;
    final pieces = [
      for (final p in pages)
        for (final s in p.slices)
          if (s.block == last) s,
    ];
    expect(pieces.length, greaterThan(1));
    for (var i = 1; i < pieces.length; i++) {
      expect(pieces[i].start, pieces[i - 1].end);
    }
    // Broken between words, at a line boundary.
    expect(blocks[last].text[pieces.first.end - 1], ' ');
    // Each continuation starts a page.
    for (final piece in pieces.skip(1)) {
      final page = pages.firstWhere((p) => p.slices.contains(piece));
      expect(page.slices.first, piece);
      expect((page.block, page.offset), (piece.block, piece.start));
    }
  });

  testWidgets('bigger type needs more pages; the first page keeps room for '
      'the header', (t) async {
    final ctx = await host(t);
    final small = paginateNovel(blocks, metricsFor(ctx, fontSize: 14));
    final large = paginateNovel(blocks, metricsFor(ctx, fontSize: 22));
    expect(large.length, greaterThan(small.length));
    final plain = paginateNovel(blocks, metricsFor(ctx));
    final inset = paginateNovel(blocks, metricsFor(ctx, inset: 200));
    expect(inset.first.slices.length, lessThan(plain.first.slices.length));
  });

  for (final (justify, scale) in [(false, 1.0), (true, 1.3)]) {
    testWidgets('each page, drawn as the reader draws it, fits its height '
        '(justify: $justify, scale: $scale)', (t) async {
      const width = 320.0;
      const height = 420.0;
      final ctx = await host(t);
      final metrics = metricsFor(
        ctx,
        width: width,
        height: height,
        justify: justify,
        scaler: TextScaler.linear(scale),
      );
      final pages = paginateNovel(blocks, metrics);
      for (final page in pages) {
        final key = GlobalKey();
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: OverflowBox(
                    alignment: Alignment.topCenter,
                    minHeight: 0,
                    maxHeight: double.infinity,
                    child: Column(
                      key: key,
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        NovelText(
                          html: chapter,
                          color: Colors.black,
                          fontSize: metrics.fontSize,
                          lineHeight: metrics.lineHeight,
                          justify: metrics.justify,
                          paragraphSpacing: metrics.paragraphSpacing,
                          slices: page.slices,
                          textScaler: metrics.textScaler,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final drawn = t.getSize(find.byKey(key)).height;
        // The trailing paragraph gap may hang off the bottom; the text may not.
        expect(
          drawn - metrics.paragraphSpacing,
          lessThanOrEqualTo(height + 1),
          reason: 'page starting at ${page.block}:${page.offset}',
        );
        // And no page but the last is left half empty.
        if (!identical(page, pages.last)) {
          expect(drawn, greaterThan(height * 0.7));
        }
      }
    });
  }

  testWidgets('a place in the chapter is found again after a new cut', (
    t,
  ) async {
    final ctx = await host(t);
    final before = paginateNovel(blocks, metricsFor(ctx));
    final page = before[before.length ~/ 2];
    final after = paginateNovel(blocks, metricsFor(ctx, fontSize: 20));
    final found = after[novelPageOf(after, page.block, page.offset)];
    final foundStart = (found.block, found.offset);
    // The new page starts at or before the old place and reaches past it.
    expect(
      found.block < page.block ||
          (found.block == page.block && found.offset <= page.offset),
      isTrue,
      reason: '$foundStart',
    );
    final end = found.slices.last;
    expect(
      end.block > page.block ||
          (end.block == page.block && end.end >= page.offset),
      isTrue,
    );
    expect(novelPageOf(after, 0, 0), 0);
  });

  testWidgets('an empty chapter is still one page', (t) async {
    final ctx = await host(t);
    final pages = paginateNovel(const [], metricsFor(ctx));
    expect(pages, hasLength(1));
    expect(pages.single.slices, isEmpty);
  });
}
