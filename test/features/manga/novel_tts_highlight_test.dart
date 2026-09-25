import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/manga/presentation/widgets/novel_text.dart';

void main() {
  const paint = Color(0x553D8BFF);

  Future<List<TextSpan>> spansOf(
    WidgetTester tester,
    String html, {
    required int block,
    required int start,
    required int end,
    GlobalKey? key,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: NovelText(
              html: html,
              color: Colors.white,
              fontSize: 16,
              speakingBlock: block,
              speakingStart: start,
              speakingEnd: end,
              speakingKey: key,
              speakingColor: paint,
            ),
          ),
        ),
      ),
    );
    final out = <TextSpan>[];
    for (final w in tester.widgetList<SelectableText>(
      find.byType(SelectableText),
    )) {
      w.textSpan!.visitChildren((s) {
        if (s is TextSpan && s.text != null) out.add(s);
        return true;
      });
    }
    return out;
  }

  String painted(List<TextSpan> spans) => [
    for (final s in spans)
      if (s.style?.backgroundColor == paint) s.text!,
  ].join();

  testWidgets('the spoken sentence is painted and nothing else', (
    tester,
  ) async {
    final spans = await spansOf(
      tester,
      '<p>First one. Second one. Third.</p>',
      block: 0,
      start: 11,
      end: 22,
    );
    expect(painted(spans), 'Second one.');
    expect(spans.map((s) => s.text).join(), 'First one. Second one. Third.');
  });

  testWidgets('a sentence across emphasis runs keeps the emphasis', (
    tester,
  ) async {
    final spans = await spansOf(
      tester,
      '<p>He said <b>no</b> twice. Then left.</p>',
      block: 0,
      start: 0,
      end: 17,
    );
    expect(painted(spans), 'He said no twice.');
    final bold = spans.singleWhere((s) => s.text == 'no');
    expect(bold.style?.fontWeight, FontWeight.w700);
    expect(bold.style?.backgroundColor, paint);
  });

  testWidgets('the speaking block carries the key the reader follows', (
    tester,
  ) async {
    final key = GlobalKey();
    await spansOf(
      tester,
      '<p>One.</p><p>Two.</p>',
      block: 1,
      start: 0,
      end: 4,
      key: key,
    );
    expect(key.currentContext, isNotNull);
    expect(
      find.descendant(
        of: find.byKey(key),
        matching: find.textContaining('Two'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('no speaking block paints nothing', (tester) async {
    final spans = await spansOf(
      tester,
      '<p>One. Two.</p>',
      block: -1,
      start: 0,
      end: 0,
    );
    expect(painted(spans), isEmpty);
  });
}
