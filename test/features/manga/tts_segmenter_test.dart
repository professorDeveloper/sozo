import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/manga/domain/reading/tts_segmenter.dart';
import 'package:soplay/features/manga/presentation/widgets/novel_text.dart';

/// Chapters in the shapes real Mangayomi novel sources return — the
/// kolnovel/WordPress wrapper of a centred heading, a rule and a break around
/// `content.rendered` — filled with public-domain prose, so the segmenter is
/// tested on the punctuation real books use rather than on tidy examples.
void main() {
  List<String> said(String html) => [
    for (final u in segmentForSpeech(parseNovelBlocks(html))) u.text,
  ];

  group('real chapters', () {
    test('an English chapter in the WordPress wrapper', () {
      const html =
          '<h2 style="text-align: center;">Chapter 1</h2><hr><br>'
          '<p>It is a truth universally acknowledged, that a single man in '
          'possession of a good fortune, must be in want of a wife.</p>'
          '<p>&ldquo;My dear Mr. Bennet,&rdquo; said his lady to him one day, '
          '&ldquo;have you heard that Netherfield Park is let at last?&rdquo;'
          '</p><p>Mr. Bennet replied that he had not.</p>'
          '<p>&ldquo;But it is,&rdquo; returned she; &ldquo;for Mrs. Long has '
          'just been here, and she told me all about it.&rdquo;</p>'
          '<p>Mr. Bennet made no answer.</p>';
      expect(said(html), [
        'Chapter 1',
        'It is a truth universally acknowledged, that a single man in '
            'possession of a good fortune, must be in want of a wife.',
        '“My dear Mr. Bennet,” said his lady to him one day, “have you heard '
            'that Netherfield Park is let at last?”',
        'Mr. Bennet replied that he had not.',
        '“But it is,” returned she; “for Mrs. Long has just been here, and '
            'she told me all about it.”',
        'Mr. Bennet made no answer.',
      ]);
    });

    test('a question inside a quote followed by its speaker stays whole', () {
      const html =
          '<p>"What is his name?" she asked. "Bingley." '
          '"Is he married or single?"</p>';
      expect(said(html), [
        '"What is his name?" she asked.',
        '"Bingley."',
        '"Is he married or single?"',
      ]);
    });

    test('a Russian chapter, with its dashes and abbreviations', () {
      const html =
          '<h3>Часть первая</h3><p>Все счастливые семьи похожи друг на друга, '
          'каждая несчастливая семья несчастлива по-своему.</p>'
          '<p>Все смешалось в доме Облонских. Жена узнала, что муж был в связи '
          'с бывшею в их доме француженкою-гувернанткой, и объявила мужу, что '
          'не может жить с ним в одном доме, т. е. под одной крышей.</p>';
      expect(said(html), [
        'Часть первая',
        'Все счастливые семьи похожи друг на друга, каждая несчастливая '
            'семья несчастлива по-своему.',
        'Все смешалось в доме Облонских.',
        'Жена узнала, что муж был в связи с бывшею в их доме '
            'француженкою-гувернанткой, и объявила мужу, что не может жить с '
            'ним в одном доме, т. е. под одной крышей.',
      ]);
    });

    test('Chinese splits on full-width stops with no space after them', () {
      const html =
          '<p>詩曰：混沌未分天地亂，茫茫渺渺無人見。自從盤古破鴻濛，開闢從茲清濁辨。'
          '覆載群生仰至仁，發明萬物皆成善。</p>';
      expect(said(html), [
        '詩曰：混沌未分天地亂，茫茫渺渺無人見。',
        '自從盤古破鴻濛，開闢從茲清濁辨。',
        '覆載群生仰至仁，發明萬物皆成善。',
      ]);
    });

    test('Japanese keeps a closing bracket with its sentence', () {
      const html =
          '<p>吾輩は猫である。名前はまだ無い。「どこで生れたかとんと見当がつかぬ。」'
          'と思った。</p>';
      expect(said(html), [
        '吾輩は猫である。',
        '名前はまだ無い。',
        '「どこで生れたかとんと見当がつかぬ。」',
        'と思った。',
      ]);
    });
  });

  group('what is not a sentence end', () {
    test('initials, decimals and a trailing ellipsis mid-thought', () {
      expect(sentenceTexts('J. K. Rowling paid 3.5 dollars. Then she left.'), [
        'J. K. Rowling paid 3.5 dollars.',
        'Then she left.',
      ]);
      expect(sentenceTexts('See No. 5 and vol. 2. He said no. Done.'), [
        'See No. 5 and vol. 2.',
        'He said no.',
        'Done.',
      ]);
      expect(sentenceTexts('Well... maybe not. Fine!'), [
        'Well... maybe not.',
        'Fine!',
      ]);
    });

    test('"I." at the end of a sentence still ends it', () {
      expect(sentenceTexts('It was I. Nobody else.'), [
        'It was I.',
        'Nobody else.',
      ]);
    });

    test('text with no terminator is one sentence', () {
      expect(sentenceTexts('No full stop here'), ['No full stop here']);
    });
  });

  group('what is not spoken', () {
    test('rules and symbol-only lines are skipped', () {
      const html = '<p>Before.</p><hr><p>* * *</p><p>…</p><p>After.</p>';
      expect(said(html), ['Before.', 'After.']);
    });

    test('empty chapters produce nothing', () {
      expect(said(''), isEmpty);
    });
  });

  group('offsets', () {
    test('each utterance points at its own text in its block', () {
      const html =
          '<h2>Chapter 3</h2><hr><p>He said <b>no</b>. She <i>laughed</i>. '
          'They left.</p>';
      final blocks = parseNovelBlocks(html);
      for (final u in segmentForSpeech(blocks)) {
        expect(blocks[u.block].text.substring(u.start, u.end), u.text);
      }
      final paragraph = segmentForSpeech(blocks).where((u) => u.block == 2);
      expect(paragraph.map((u) => u.text), [
        'He said no.',
        'She laughed.',
        'They left.',
      ]);
    });
  });

  group('length cap', () {
    test('a run-on sentence is cut at commas, within the cap', () {
      final clause = List.filled(12, 'and the rain kept falling').join(', ');
      final blocks = parseNovelBlocks('<p>$clause.</p>');
      final parts = segmentForSpeech(blocks, maxLength: 80);
      expect(parts.length, greaterThan(1));
      for (final p in parts) {
        expect(p.text.length, lessThanOrEqualTo(80));
      }
      expect(parts.map((p) => p.text).join(' '), '$clause.');
    });

    test('text with no break at all is cut hard, and nothing is lost', () {
      final wall = 'あ' * 250;
      final parts = segmentForSpeech(
        parseNovelBlocks('<p>$wall</p>'),
        maxLength: 100,
      );
      expect(parts.map((p) => p.text.length), [100, 100, 50]);
    });
  });

  group('TtsScript', () {
    const html =
        '<p>One two three.</p><p>Four five six.</p><p>Seven eight nine.</p>';

    test('permille rises to 1000 at the last sentence', () {
      final s = TtsScript.fromBlocks(parseNovelBlocks(html));
      expect(s.length, 3);
      // 14 of the chapter's 45 characters.
      expect(s.permilleAfter(0), 311);
      expect(s.permilleAfter(2), 1000);
    });

    test('a permille maps back to the sentence holding it', () {
      final s = TtsScript.fromBlocks(parseNovelBlocks(html));
      expect(s.indexAtPermille(0), 0);
      expect(s.indexAtPermille(500), 1);
      expect(s.indexAtPermille(1000), 2);
    });

    test('a preface is spoken first but is not part of the page', () {
      final s = TtsScript.fromBlocks(
        parseNovelBlocks(html),
        preface: 'Chapter 4',
      );
      expect(s[0].block, -1);
      expect(s[0].text, 'Chapter 4');
      expect(s.permilleAfter(0), 0);
      expect(s.indexAtPermille(0), 1);
    });
  });
}

List<String> sentenceTexts(String text) => [
  for (final (s, e) in sentenceRanges(text)) text.substring(s, e).trim(),
];
