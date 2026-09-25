import 'dart:typed_data';

import 'package:archive/archive.dart';

/// One chapter on the way into a book.
class EpubChapter {
  const EpubChapter({
    required this.title,
    required this.html,
    this.images = const {},
  });

  final String title;

  /// The chapter's markup, as the source wrote it. Sanitised on the way in —
  /// see [EpubBuilder.toXhtml].
  final String html;

  /// File name inside the book to raw bytes, for every picture the chapter
  /// refers to. The `src` attributes in [html] are expected to name these.
  final Map<String, Uint8List> images;
}

/// Turns downloaded chapters into an EPUB that any reader can open.
///
/// A downloaded novel lived in the app and nowhere else. There was no way to
/// put it on an e-reader, send it to somebody, or keep it once the app is gone
/// — and a chapter of prose, unlike an episode of video, is exactly the kind of
/// thing people expect to be able to take with them.
///
/// EPUB 3, written by hand rather than with a library: the format is a zip with
/// four small XML files in it, and a dependency for that would be more code
/// than this, not less.
///
/// Two rules of the container matter and both are easy to get wrong:
///
///  * `mimetype` must be the FIRST entry and must be STORED, not deflated. A
///    reader identifies the file by reading those bytes at a fixed offset, and
///    a compressed one is not an EPUB as far as it is concerned.
///  * every document must be well-formed XML. Source HTML is not — `<br>` and
///    `<img ...>` are unclosed, and `&` is routinely bare — so it is repaired
///    on the way in rather than trusted.
abstract final class EpubBuilder {
  /// Void elements: legal unclosed in HTML, fatal unclosed in XML.
  static const List<String> _void = [
    'area', 'base', 'br', 'col', 'embed', 'hr', 'img',
    'input', 'link', 'meta', 'source', 'track', 'wbr',
  ];

  /// An `&` that does not start an entity. XML rejects it outright, and it is
  /// the single most common reason a scraped chapter will not open.
  static final RegExp _bareAmp = RegExp(
    r'&(?!#\d+;|#[xX][0-9a-fA-F]+;|[a-zA-Z][a-zA-Z0-9]*;)',
  );

  static final RegExp _scripts = RegExp(
    r'<(script|style)\b[^>]*>.*?</\1\s*>',
    caseSensitive: false,
    dotAll: true,
  );

  /// The chapter's markup as a well-formed XHTML document.
  ///
  /// Repair rather than re-render: the source's own paragraphs, emphasis and
  /// picture placement are the chapter, and a "safe" rewrite that kept only the
  /// text would throw away most of what makes it readable.
  static String toXhtml(String title, String html) {
    var body = html.replaceAll(_scripts, '');
    body = body.replaceAllMapped(_bareAmp, (_) => '&amp;');
    for (final tag in _void) {
      // `<br>` and `<br />` both, without turning the second into `<br / />`.
      body = body.replaceAllMapped(
        RegExp('<$tag\\b([^>]*?)/?>', caseSensitive: false, dotAll: true),
        (m) => '<$tag${m.group(1)}/>',
      );
    }
    return '<?xml version="1.0" encoding="utf-8"?>\n'
        '<html xmlns="http://www.w3.org/1999/xhtml" '
        'xmlns:epub="http://www.idpf.org/2007/ops">\n'
        '<head><title>${escape(title)}</title>'
        '<meta charset="utf-8"/></head>\n'
        '<body><h1>${escape(title)}</h1>\n$body\n</body>\n</html>\n';
  }

  static String escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  /// The media type a reader needs declared for each picture.
  ///
  /// An unknown extension is declared as jpeg rather than skipped: a wrong
  /// label is usually opened anyway, and a picture left out of the manifest
  /// makes the book itself invalid.
  static String mediaTypeOf(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.svg')) return 'image/svg+xml';
    if (lower.endsWith('.avif')) return 'image/avif';
    return 'image/jpeg';
  }

  /// The whole book, ready to write to disk.
  ///
  /// [identifier] should be stable for one title so a reader can tell two
  /// exports of the same book apart from two different books.
  static Uint8List build({
    required String title,
    required List<EpubChapter> chapters,
    String? author,
    String? identifier,
    String language = 'en',
  }) {
    final archive = Archive();

    // First, and stored. See the class comment: this one is not an
    // optimisation choice, it is what makes the file an EPUB.
    archive.add(
      ArchiveFile.string('mimetype', 'application/epub+zip')
        ..compression = CompressionType.none,
    );

    archive.add(
      ArchiveFile.string('META-INF/container.xml', _container),
    );

    final names = <String>[];
    for (var i = 0; i < chapters.length; i++) {
      final name = 'chapter_${i.toString().padLeft(4, '0')}.xhtml';
      names.add(name);
      archive.add(
        ArchiveFile.string(
          'OEBPS/$name',
          toXhtml(chapters[i].title, chapters[i].html),
        ),
      );
    }

    // Pictures are written under the chapter that owns them, so two chapters
    // whose sources both called a file `p_000.jpg` do not overwrite each other.
    final images = <String, String>{};
    for (var i = 0; i < chapters.length; i++) {
      for (final entry in chapters[i].images.entries) {
        final path = 'images/${i.toString().padLeft(4, '0')}_${entry.key}';
        images[path] = mediaTypeOf(entry.key);
        archive.add(ArchiveFile.bytes('OEBPS/$path', entry.value));
      }
    }

    archive.add(ArchiveFile.string('OEBPS/nav.xhtml', _nav(chapters, names)));
    archive.add(
      ArchiveFile.string(
        'OEBPS/content.opf',
        _opf(
          title: title,
          author: author,
          identifier: identifier ?? 'sozo:${title.hashCode}',
          language: language,
          chapters: names,
          images: images,
        ),
      ),
    );

    return ZipEncoder().encodeBytes(archive);
  }

  static const String _container =
      '<?xml version="1.0" encoding="utf-8"?>\n'
      '<container version="1.0" '
      'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">\n'
      '  <rootfiles>\n'
      '    <rootfile full-path="OEBPS/content.opf" '
      'media-type="application/oebps-package+xml"/>\n'
      '  </rootfiles>\n'
      '</container>\n';

  static String _nav(List<EpubChapter> chapters, List<String> names) {
    final items = [
      for (var i = 0; i < chapters.length; i++)
        '      <li><a href="${names[i]}">'
            '${escape(chapters[i].title)}</a></li>',
    ].join('\n');
    return '<?xml version="1.0" encoding="utf-8"?>\n'
        '<html xmlns="http://www.w3.org/1999/xhtml" '
        'xmlns:epub="http://www.idpf.org/2007/ops">\n'
        '<head><title>Contents</title><meta charset="utf-8"/></head>\n'
        '<body>\n  <nav epub:type="toc" id="toc">\n'
        '    <h1>Contents</h1>\n    <ol>\n$items\n    </ol>\n'
        '  </nav>\n</body>\n</html>\n';
  }

  static String _opf({
    required String title,
    required String? author,
    required String identifier,
    required String language,
    required List<String> chapters,
    required Map<String, String> images,
  }) {
    final manifest = <String>[
      '    <item id="nav" href="nav.xhtml" '
          'media-type="application/xhtml+xml" properties="nav"/>',
      for (var i = 0; i < chapters.length; i++)
        '    <item id="c$i" href="${chapters[i]}" '
            'media-type="application/xhtml+xml"/>',
      for (final (i, entry) in images.entries.indexed)
        '    <item id="img$i" href="${entry.key}" '
            'media-type="${entry.value}"/>',
    ].join('\n');
    final spine = [
      for (var i = 0; i < chapters.length; i++) '    <itemref idref="c$i"/>',
    ].join('\n');
    return '<?xml version="1.0" encoding="utf-8"?>\n'
        '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
        'unique-identifier="bookid">\n'
        '  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">\n'
        '    <dc:identifier id="bookid">${escape(identifier)}</dc:identifier>\n'
        '    <dc:title>${escape(title)}</dc:title>\n'
        '    <dc:language>${escape(language)}</dc:language>\n'
        '${author == null ? '' : '    <dc:creator>${escape(author)}</dc:creator>\n'}'
        '  </metadata>\n'
        '  <manifest>\n$manifest\n  </manifest>\n'
        '  <spine>\n$spine\n  </spine>\n'
        '</package>\n';
  }
}
