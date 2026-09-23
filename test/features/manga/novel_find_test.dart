// Find in chapter: the count the bar shows and the highlights on the page
// must agree, or "3 / 7" points at a paragraph with nothing marked in it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/manga/presentation/widgets/novel_text.dart';

void main() {
  const html =
      '<p>The Sun rose. The sun set.</p><p>No match here.</p>'
      '<p>Sunday: <b>SUN</b> again.</p>';

  test('matches are counted case-insensitively across the chapter', () {
    expect(NovelText.countInChapter(html, 'sun'), 4);
    expect(NovelText.countInChapter(html, '  sun '), 4);
    expect(NovelText.countInChapter(html, ''), 0);
    expect(NovelText.countInChapter(html, 'moon'), 0);
  });

  testWidgets('the active match carries the key the reader scrolls to', (
    tester,
  ) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NovelText(
            html: html,
            color: Colors.white,
            fontSize: 16,
            query: 'sun',
            activeMatch: 2,
            activeKey: key,
          ),
        ),
      ),
    );
    // The third "sun" is the "Sun" in "Sunday", in the third paragraph.
    expect(key.currentContext, isNotNull);
    final text = tester.widget<SelectableText>(
      find.descendant(
        of: find.byKey(key),
        matching: find.byType(SelectableText),
      ),
    );
    final spans = (text.textSpan!.children!).whereType<TextSpan>().toList();
    final marked = spans.where((s) => s.style?.backgroundColor != null);
    expect(marked.length, 2, reason: 'Sunday and SUN, in two runs');
  });
}
