import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/manga/domain/translate/page_translation.dart';

OcrBlock block(double l, double t, double r, double b, String text,
        {double line = 20}) =>
    OcrBlock(rect: Rect.fromLTRB(l, t, r, b), text: text, lineHeight: line);

PageTranslation translation(String lang) => PageTranslation(
  imageSize: const Size(800, 1200),
  targetLang: lang,
  blocks: [
    TranslatedBlock(
      rect: const Rect.fromLTRB(10, 10, 100, 50),
      source: 'Hello',
      text: 'مرحبا',
    ),
  ],
);

void main() {
  group('mergeBlocks', () {
    test('joins a bubble split into stacked blocks', () {
      final out = mergeBlocks([
        block(100, 100, 300, 140, 'WHERE ARE'),
        block(110, 150, 290, 190, 'YOU GOING?'),
      ]);
      expect(out, hasLength(1));
      expect(out.single.rect, const Rect.fromLTRB(100, 100, 300, 190));
      expect(out.single.text, 'WHERE ARE\nYOU GOING?');
    });

    test('keeps bubbles apart when the gap is wider than a line', () {
      final out = mergeBlocks([
        block(100, 100, 300, 140, 'FIRST'),
        block(100, 200, 300, 240, 'SECOND'),
      ]);
      expect(out.map((b) => b.text), ['FIRST', 'SECOND']);
    });

    test('does not join side-by-side bubbles that barely overlap', () {
      final out = mergeBlocks([
        block(100, 100, 300, 140, 'LEFT'),
        block(290, 150, 500, 190, 'RIGHT'),
      ]);
      expect(out, hasLength(2));
    });

    test('joins transitively, in reading order', () {
      final out = mergeBlocks([
        block(100, 200, 300, 240, 'C'),
        block(100, 100, 300, 140, 'A'),
        block(100, 150, 300, 190, 'B'),
      ]);
      expect(out.single.text, 'A\nB\nC');
    });

    test('orders separate blocks top to bottom, then left to right', () {
      final out = mergeBlocks([
        block(500, 105, 700, 140, 'RIGHT'),
        block(10, 100, 200, 140, 'LEFT'),
        block(10, 600, 200, 640, 'BELOW'),
      ]);
      expect(out.map((b) => b.text), ['LEFT', 'RIGHT', 'BELOW']);
    });

    test('drops blocks with no letters', () {
      final out = mergeBlocks([
        block(10, 10, 40, 30, '12'),
        block(10, 500, 200, 540, '...'),
        block(300, 300, 500, 340, 'HEY'),
      ]);
      expect(out.map((b) => b.text), ['HEY']);
    });
  });

  group('normalizeOcrText', () {
    test('turns all caps into sentence case and joins lines', () {
      expect(
        normalizeOcrText("I DON'T\nKNOW. WHERE\nIS HE?"),
        "I don't know. Where is he?",
      );
    });

    test('rejoins a word hyphenated at a line end', () {
      expect(normalizeOcrText('SOME-\nTHING'), 'Something');
    });

    test('leaves mixed case alone', () {
      expect(normalizeOcrText('Hello  there\nTokyo'), 'Hello there Tokyo');
    });
  });

  group('fitFontSize', () {
    // A fake layout: every character is 0.6em wide, lines wrap at the width.
    Size Function(double) measurer(String text, double width) => (size) {
      final perLine = (width / (0.6 * size)).floor().clamp(1, 1 << 20);
      final lines = (text.length / perLine).ceil();
      final w = text.length >= perLine ? width : text.length * 0.6 * size;
      return Size(w, lines * size * 1.2);
    };

    test('returns the largest size that fits', () {
      const box = Size(120, 60);
      final size = fitFontSize(
        box: box,
        measure: measurer('Hello there friend', box.width),
      );
      expect(measurer('Hello there friend', box.width)(size).height,
          lessThanOrEqualTo(box.height));
      expect(measurer('Hello there friend', box.width)(size + 0.5).height,
          greaterThan(box.height));
    });

    test('is capped at max for short text', () {
      expect(
        fitFontSize(
          box: const Size(500, 500),
          max: 24,
          measure: measurer('Hi', 500),
        ),
        24,
      );
    });

    test('falls back to min when nothing fits', () {
      expect(
        fitFontSize(
          box: const Size(10, 4),
          min: 6,
          measure: measurer('A very long sentence indeed', 10),
        ),
        6,
      );
    });

    test('an empty box gets min', () {
      expect(
        fitFontSize(box: Size.zero, min: 7, measure: (_) => Size.zero),
        7,
      );
    });
  });

  group('pageTranslateDocKey', () {
    test('names chapter and page', () {
      expect(
        pageTranslateDocKey('https://x.example/ch/12', 3),
        'manga:https://x.example/ch/12:3',
      );
    });

    test('hashes a chapter url too long for the server to keep whole', () {
      final url = 'https://x.example/${'a' * 300}';
      final a = pageTranslateDocKey(url, 1);
      final b = pageTranslateDocKey(url, 2);
      expect(a.length, lessThanOrEqualTo(kDocKeyLimit));
      expect(a, endsWith(':1'));
      expect(a, isNot(b));
      expect(a, pageTranslateDocKey(url, 1));
    });
  });

  test('isRtlLanguage', () {
    expect(isRtlLanguage('ar'), isTrue);
    expect(isRtlLanguage('AR-eg'), isTrue);
    expect(isRtlLanguage('en'), isFalse);
  });

  test('PageTranslation survives a JSON round trip', () {
    final back = PageTranslation.tryFromJson(translation('ar').toJson())!;
    expect(back.imageSize, const Size(800, 1200));
    expect(back.targetLang, 'ar');
    expect(back.blocks.single.rect, const Rect.fromLTRB(10, 10, 100, 50));
    expect(back.blocks.single.text, 'مرحبا');
    expect(PageTranslation.tryFromJson({'w': 'x'}), isNull);
  });

  group('PageOverlays', () {
    const key = 'ch#0';

    test('a stored translation is not shown until applied', () {
      final o = PageOverlays()..store(key, translation('ar'));
      expect(o.visible(key), isNull);
      expect(o.translationFor(key, 'ar'), isNotNull);
      expect(o.translationFor(key, 'uz'), isNull);
      o.apply(key);
      expect(o.visible(key), isNotNull);
      expect(o.isApplied(key), isTrue);
    });

    test('show original hides it and toggles back', () {
      final o = PageOverlays()
        ..store(key, translation('ar'))
        ..apply(key);
      o.toggleOriginal(key);
      expect(o.visible(key), isNull);
      expect(o.isApplied(key), isTrue);
      o.toggleOriginal(key);
      expect(o.visible(key), isNotNull);
    });

    test('apply can keep the original showing', () {
      final o = PageOverlays()
        ..store(key, translation('ar'))
        ..apply(key, showOriginal: true);
      expect(o.visible(key), isNull);
      expect(o.entry(key)!.showOriginal, isTrue);
    });

    test('toggling a page that was never applied does nothing', () {
      final o = PageOverlays()..store(key, translation('ar'));
      o.toggleOriginal(key);
      expect(o.entry(key)!.showOriginal, isFalse);
      expect(o.visible(key), isNull);
    });

    test('remove takes it off and keeps the translation', () {
      final o = PageOverlays()
        ..store(key, translation('ar'))
        ..apply(key);
      o.remove(key);
      expect(o.visible(key), isNull);
      expect(o.translationFor(key, 'ar'), isNotNull);
    });

    test('a fresh translation in the same language stays applied', () {
      final o = PageOverlays()
        ..store(key, translation('ar'))
        ..apply(key);
      o.store(key, translation('ar'));
      expect(o.visible(key), isNotNull);
      o.store(key, translation('uz'));
      expect(o.visible(key), isNull);
    });

    test('notifies listeners on every change', () {
      var calls = 0;
      final o = PageOverlays()..addListener(() => calls++);
      o
        ..store(key, translation('ar'))
        ..apply(key)
        ..toggleOriginal(key)
        ..remove(key);
      expect(calls, 4);
    });
  });
}
