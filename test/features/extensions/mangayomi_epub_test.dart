import 'dart:async';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/extensions/data/mangayomi_epub.dart';

Uint8List bookBytes({bool epub3 = false}) {
  final zip = Archive();
  void add(String name, String text) =>
      zip.addFile(ArchiveFile.string(name, text));
  add(
    'META-INF/container.xml',
    '<container><rootfiles><rootfile full-path="OEBPS/book.opf"/></rootfiles></container>',
  );
  add(
    'OEBPS/book.opf',
    '''<package><manifest>
    <item id="one" href="one.xhtml" media-type="application/xhtml+xml"/>
    <item id="two" href="two.xhtml" media-type="application/xhtml+xml"/>
    <item id="nav" href="nav.xml" ${epub3 ? 'properties="nav" media-type="application/xhtml+xml"' : 'media-type="application/x-dtbncx+xml"'}/>
    </manifest><spine><itemref idref="two"/><itemref idref="one"/></spine></package>''',
  );
  add(
    'OEBPS/nav.xml',
    epub3
        ? '<html><nav><a href="one.xhtml">Opening</a><a href="two.xhtml#part">Opening</a></nav></html>'
        : '<ncx><navMap><navPoint><navLabel><text>Opening</text></navLabel><content src="one.xhtml"/></navPoint><navPoint><navLabel><text>Opening</text></navLabel><content src="two.xhtml#part"/></navPoint></navMap></ncx>',
  );
  add('OEBPS/one.xhtml', '<html><body><p>First file</p></body></html>');
  add('OEBPS/two.xhtml', '<html><body><p>Second file</p></body></html>');
  return Uint8List.fromList(ZipEncoder().encode(zip));
}

void main() {
  for (final epub3 in [false, true]) {
    test('EPUB${epub3 ? 3 : 2} uses spine order and unique chapter labels', () {
      final parsed = decodeEpub(bookBytes(epub3: epub3));
      expect(parsed.keys.toList(), ['Opening', 'Opening (2)']);
      expect(parsed['Opening'], contains('Second file'));
      expect(parsed['Opening (2)'], contains('First file'));
    });
  }
  test(
    'host coalesces downloads and reuses parsed text for chapter reads',
    () async {
      var downloads = 0;
      final pending = Completer<Uint8List>();
      final host = MangayomiEpub((url, headers) {
        downloads++;
        expect(headers['Cookie'], 'session=fixture');
        return pending.future;
      });
      final request = {
        'method': 'book',
        'url': 'https://books.example/book.epub',
        'headers': {'Cookie': 'session=fixture'},
      };
      final first = host.call(request);
      final second = host.call(request);
      pending.complete(bookBytes());
      expect(await first, {
        'chapters': ['Opening', 'Opening (2)'],
      });
      expect(await second, await first);
      expect(
        await host.call({
          ...request,
          'method': 'chapter',
          'chapter': 'Opening',
        }),
        contains('Second file'),
      );
      expect(downloads, 1);
    },
  );
  test('failed fetch can be retried without poisoning book cache', () async {
    var attempts = 0;
    final host = MangayomiEpub((url, headers) async {
      if (++attempts == 1) throw StateError('offline');
      return bookBytes();
    });
    final request = {
      'method': 'book',
      'url': 'https://books.example/book.epub',
    };
    await expectLater(host.call(request), throwsStateError);
    expect(await host.call(request), isA<Map>());
    expect(attempts, 2);
  });
  test(
    'unsupported document fails explicitly rather than yielding no chapters',
    () {
      expect(
        () => decodeEpub(Uint8List.fromList('%PDF-1.7'.codeUnits)),
        throwsA(anything),
      );
    },
  );
}
