import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/manga/presentation/widgets/novel_text.dart';

/// Every fixture here is the shape a real Mangayomi novel source returns —
/// `cleanHtmlContent` wraps a WordPress `content.rendered` in a heading and a
/// rule, and the body is whatever the site wrote.
void main() {
  List<String> texts(String html) =>
      [for (final b in parseNovelBlocks(html)) b.text];

  List<NovelBlockKind> kinds(String html) =>
      [for (final b in parseNovelBlocks(html)) b.kind];

  group('structure', () {
    test('the wrapper a real source produces parses into its parts', () {
      // Verbatim from kolnovel.js: a centred h2, a rule, a break, then body.
      const html =
          '<h2 style="text-align: center;">Chapter 12</h2><hr><br>'
          '<p>He opened the door.</p><p>Nobody was there.</p>';
      expect(kinds(html), [
        NovelBlockKind.heading,
        NovelBlockKind.rule,
        NovelBlockKind.paragraph,
        NovelBlockKind.paragraph,
      ]);
      expect(texts(html).first, 'Chapter 12');
      expect(texts(html).last, 'Nobody was there.');
    });

    test('divs are paragraphs too', () {
      // Several sources write one div per paragraph. Treating them as inline
      // collapsed a whole chapter into a single wall of text.
      expect(texts('<div>One.</div><div>Two.</div>'), ['One.', 'Two.']);
    });

    test('a line break splits a paragraph', () {
      expect(texts('<p>One.<br>Two.</p>'), ['One.', 'Two.']);
    });

    test('a rule between text survives; a trailing one does not', () {
      expect(
        kinds('<p>a</p><hr><p>b</p>')
            .where((k) => k == NovelBlockKind.rule)
            .length,
        1,
      );
      // A separator with nothing after it separates nothing.
      expect(kinds('<p>a</p><hr>').contains(NovelBlockKind.rule), isFalse);
    });

    test('empty markup produces nothing rather than a blank block', () {
      expect(parseNovelBlocks(''), isEmpty);
      expect(parseNovelBlocks('<p></p><div>   </div>'), isEmpty);
    });
  });

  group('emphasis', () {
    test('bold and italic become runs', () {
      final blocks =
          parseNovelBlocks('<p>He said <b>no</b> and <i>left</i>.</p>');
      final runs = blocks.single.runs;
      expect(runs.any((r) => r.text == 'no' && r.bold), isTrue);
      expect(runs.any((r) => r.text == 'left' && r.italic), isTrue);
      expect(blocks.single.text, 'He said no and left.');
    });

    test('strong and em are the same thing', () {
      final blocks =
          parseNovelBlocks('<p><strong>A</strong> and <em>B</em></p>');
      expect(blocks.single.runs.any((r) => r.text == 'A' && r.bold), isTrue);
      expect(blocks.single.runs.any((r) => r.text == 'B' && r.italic), isTrue);
    });

    test('plain prose carries no runs, so it renders as one span', () {
      expect(parseNovelBlocks('<p>Just words.</p>').single.runs, isEmpty);
    });
  });

  group('what must never render', () {
    test('script and style contents are dropped, not shown as prose', () {
      // These come from arbitrary third-party sites. Their text would
      // otherwise appear in the middle of the chapter.
      const html = '<p>Real.</p><script>var x = "fake";</script>'
          '<style>.a{color:red}</style>';
      expect(texts(html), ['Real.']);
    });

    test('comments are dropped', () {
      expect(texts('<p>A</p><!-- hidden --><p>B</p>'), ['A', 'B']);
    });

    test('an unknown tag keeps its text', () {
      expect(
        texts('<p>Hello <span class="x">world</span>.</p>'),
        ['Hello world.'],
      );
    });
  });

  group('entities', () {
    test('the ones these sources actually emit are decoded', () {
      expect(
        texts('<p>Tom&rsquo;s &ldquo;plan&rdquo; &mdash; done&hellip;</p>'),
        ['Tom’s “plan” — done…'],
      );
    });

    test('numeric entities are decoded', () {
      expect(texts('<p>&#65;&#66;</p>'), ['AB']);
    });

    test('an escaped ampersand is decoded once, not twice', () {
      // Decoding &amp; first would turn "&amp;lt;" into a literal "<" and
      // silently eat the rest of the paragraph as a tag.
      expect(texts('<p>a &amp;lt; b</p>'), ['a &lt; b']);
    });

    test('a non-breaking space becomes a real space', () {
      expect(texts('<p>a&nbsp;b</p>'), ['a b']);
    });
  });
}
