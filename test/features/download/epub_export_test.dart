// A downloaded novel lived in the app and nowhere else.
//
// There was no way to put it on an e-reader, send it to anybody, or keep it
// once the app is gone — and a chapter of prose, unlike an episode of video, is
// exactly the sort of thing people expect to be able to take with them. Export
// declined every chapter outright: "copying it out would need a zip".
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/download/data/epub_builder.dart';

Archive open(Uint8List bytes) => ZipDecoder().decodeBytes(bytes);

String textOf(Archive a, String name) =>
    utf8.decode(a.files.firstWhere((f) => f.name == name).content as List<int>);

void main() {
  Uint8List book({
    String title = 'A Novel',
    List<EpubChapter>? chapters,
  }) => EpubBuilder.build(
    title: title,
    chapters:
        chapters ??
        const [
          EpubChapter(title: 'Chapter 1', html: '<p>First.</p>'),
          EpubChapter(title: 'Chapter 2', html: '<p>Second.</p>'),
        ],
  );

  group('the container a reader checks first', () {
    test('mimetype is the very first entry', () {
      // A reader identifies the file by reading those bytes at a fixed offset.
      // Anywhere else in the zip and the file is not an EPUB to it.
      final a = open(book());
      expect(a.files.first.name, 'mimetype');
    });

    test('and it is stored, not deflated', () {
      final a = open(book());
      expect(
        utf8.decode(a.files.first.content as List<int>),
        'application/epub+zip',
      );
      // Read back through a decoder that would have had to inflate it: the
      // check that matters is that the raw bytes sit at the known offset, which
      // only holds when the entry is stored.
      // 30 bytes of local file header, then the name, then the content — a
      // deflated entry would put compressed bytes there instead of these.
      final raw = book();
      const at = 30 + 'mimetype'.length;
      expect(
        utf8.decode(raw.sublist(at, at + 'application/epub+zip'.length)),
        'application/epub+zip',
        reason: 'the mimetype was compressed',
      );
    });

    test('container.xml points at the package', () {
      final a = open(book());
      expect(
        textOf(a, 'META-INF/container.xml'),
        contains('full-path="OEBPS/content.opf"'),
      );
    });
  });

  group('every document has to be well-formed XML', () {
    test('an unclosed br and img are closed', () {
      // Legal HTML, fatal XML — and both are in almost every scraped chapter.
      final out = EpubBuilder.toXhtml('T', '<p>a<br>b</p><img src="p_000.jpg">');
      expect(out, contains('<br/>'));
      expect(out, contains('<img src="p_000.jpg"/>'));
      expect(out, isNot(contains('<br>')));
    });

    test('and one that was already closed is not closed twice', () {
      final out = EpubBuilder.toXhtml('T', '<p>a<br />b</p>');
      expect(out, isNot(contains('/ />')));
      expect(out, isNot(contains('<br//>')));
    });

    test('a bare ampersand is escaped, a real entity is not', () {
      final out = EpubBuilder.toXhtml('T', '<p>Tom & Jerry &amp; co &#65; &#x41;</p>');
      expect(out, contains('Tom &amp; Jerry'));
      expect(out, contains('&amp; co'));
      expect(out, contains('&#65;'));
      expect(out, contains('&#x41;'));
      expect(out, isNot(contains('&amp;amp;')));
    });

    test('script and style are dropped', () {
      final out = EpubBuilder.toXhtml(
        'T',
        '<p>keep</p><script>var x = 1 < 2;</script><style>p{}</style>',
      );
      expect(out, contains('keep'));
      expect(out, isNot(contains('var x')));
      expect(out, isNot(contains('<style')));
    });

    test('the title is escaped into the heading', () {
      final out = EpubBuilder.toXhtml('A & B <hi>', '<p>x</p>');
      expect(out, contains('A &amp; B &lt;hi&gt;'));
    });
  });

  group('what the book is made of', () {
    test('a chapter per document, in order, and a spine that agrees', () {
      final a = open(book());
      expect(textOf(a, 'OEBPS/chapter_0000.xhtml'), contains('First.'));
      expect(textOf(a, 'OEBPS/chapter_0001.xhtml'), contains('Second.'));
      final opf = textOf(a, 'OEBPS/content.opf');
      expect(opf.indexOf('idref="c0"'), lessThan(opf.indexOf('idref="c1"')));
    });

    test('the contents list every chapter by name', () {
      final a = open(book());
      final nav = textOf(a, 'OEBPS/nav.xhtml');
      expect(nav, contains('>Chapter 1</a>'));
      expect(nav, contains('>Chapter 2</a>'));
    });

    test('pictures are namespaced by chapter', () {
      // Two chapters whose sources both wrote `p_000.jpg` must not overwrite
      // each other.
      final a = open(
        book(
          chapters: [
            EpubChapter(
              title: 'One',
              html: '<img src="p_000.jpg">',
              images: {'p_000.jpg': Uint8List.fromList([1, 2, 3])},
            ),
            EpubChapter(
              title: 'Two',
              html: '<img src="p_000.jpg">',
              images: {'p_000.jpg': Uint8List.fromList([4, 5, 6])},
            ),
          ],
        ),
      );
      final names = a.files.map((f) => f.name).toList();
      expect(names, contains('OEBPS/images/0000_p_000.jpg'));
      expect(names, contains('OEBPS/images/0001_p_000.jpg'));
    });

    test('and every picture is declared in the manifest', () {
      // A picture left out of the manifest makes the book itself invalid.
      final a = open(
        book(
          chapters: [
            EpubChapter(
              title: 'One',
              html: '<img src="p_000.png">',
              images: {'p_000.png': Uint8List.fromList([1])},
            ),
          ],
        ),
      );
      final opf = textOf(a, 'OEBPS/content.opf');
      expect(opf, contains('href="images/0000_p_000.png"'));
      expect(opf, contains('media-type="image/png"'));
    });

    test('an unknown extension is still declared', () {
      expect(EpubBuilder.mediaTypeOf('x.weird'), 'image/jpeg');
      expect(EpubBuilder.mediaTypeOf('x.WEBP'), 'image/webp');
    });

    test('a title with XML in it does not break the package', () {
      final a = open(book(title: 'Tom & Jerry'));
      expect(textOf(a, 'OEBPS/content.opf'), contains('Tom &amp; Jerry'));
    });
  });
}
