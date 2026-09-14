import 'dart:collection';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

typedef EpubFetch =
    Future<Uint8List> Function(String url, Map<String, String> headers);

/// Downloads once per book and parses off the UI isolate. No files are extracted
/// to disk; the bounded cache contains only the text needed by the novel reader.
class MangayomiEpub {
  MangayomiEpub(this.fetch);
  final EpubFetch fetch;
  final _books = <String, Map<String, String>>{};
  final _pending = <String, Future<Map<String, String>>>{};

  Future<Map<String, String>> _book(String url, Map<String, String> headers) {
    final ordered = SplayTreeMap<String, String>.from(headers);
    final key = '$url\u0000${jsonEncode(ordered)}';
    final cached = _books.remove(key);
    if (cached != null) {
      _books[key] = cached;
      return Future.value(cached);
    }
    return _pending.putIfAbsent(key, () async {
      try {
        final bytes = await fetch(url, headers);
        final book = await _decodeOffThread(bytes);
        _books[key] = book;
        while (_books.length > 2) {
          _books.remove(_books.keys.first);
        }
        return book;
      } finally {
        _pending.remove(key);
      }
    });
  }

  Future<Object> call(Map<String, dynamic> request) async {
    final url = request['url']?.toString() ?? '';
    final raw = request['headers'];
    final headers = <String, String>{
      if (raw is Map)
        for (final entry in raw.entries)
          if (entry.value != null) entry.key.toString(): entry.value.toString(),
    };
    final book = await _book(url, headers);
    if (request['method'] == 'book') return {'chapters': book.keys.toList()};
    final chapter = request['chapter']?.toString() ?? '';
    final html = book[chapter];
    if (html == null) throw StateError('EPUB chapter not found: $chapter');
    return html;
  }
}

// A top-level closure avoids capturing the host's pending Futures into the isolate.
Future<Map<String, String>> _decodeOffThread(Uint8List bytes) =>
    Isolate.run(() => decodeEpub(bytes));

/// EPUB2 NCX and EPUB3 navigation labels, with spine order as reading order.
Map<String, String> decodeEpub(Uint8List bytes) {
  const maxArchive = 64 * 1024 * 1024;
  const maxText = 12 * 1024 * 1024;
  if (bytes.length > 32 * 1024 * 1024) {
    throw const FormatException('EPUB exceeds 32 MB');
  }
  final directory = ZipDirectory()..read(InputMemoryStream(bytes));
  if (directory.fileHeaders.length > 10000) {
    throw const FormatException('EPUB has too many entries');
  }
  var expanded = 0;
  for (final header in directory.fileHeaders) {
    expanded += header.uncompressedSize;
    if (expanded > maxArchive || header.uncompressedSize > maxText) {
      throw const FormatException('EPUB exceeds expanded size limit');
    }
    if (((header.externalFileAttributes >> 16) & 0xf000) == 0xa000) {
      throw const FormatException('EPUB symbolic links are unsupported');
    }
  }
  final archive = ZipDecoder().decodeBytes(bytes);
  final files = {
    for (final file in archive.files.where((f) => f.isFile)) file.name: file,
  };
  String read(String name) {
    final file = files[name];
    if (file == null) throw FormatException('EPUB file missing: $name');
    return utf8.decode(file.content, allowMalformed: true);
  }

  Iterable<XmlElement> elements(XmlNode doc, String name) => doc.descendants
      .whereType<XmlElement>()
      .where((e) => e.name.local == name);
  String resolve(String base, String href) =>
      Uri.parse(base).resolve(href).replace(fragment: '').path;
  final container = XmlDocument.parse(read('META-INF/container.xml'));
  final package = elements(
    container,
    'rootfile',
  ).firstOrNull?.getAttribute('full-path');
  if (package == null) throw const FormatException('EPUB package is missing');
  final opf = XmlDocument.parse(read(package));
  final items = {
    for (final item in elements(opf, 'item')) item.getAttribute('id'): item,
  };
  final labels = <String, String>{};
  for (final item in items.values) {
    final href = item.getAttribute('href');
    if (href == null) continue;
    final nav = (item.getAttribute('properties') ?? '')
        .split(' ')
        .contains('nav');
    final ncx = item.getAttribute('media-type') == 'application/x-dtbncx+xml';
    if (!nav && !ncx) continue;
    final path = resolve(package, href);
    if (!files.containsKey(path)) continue;
    final document = XmlDocument.parse(read(path));
    if (nav) {
      for (final link in elements(document, 'a')) {
        final target = link.getAttribute('href');
        if (target != null) {
          labels.putIfAbsent(
            resolve(path, target),
            () => link.innerText.trim(),
          );
        }
      }
    } else {
      for (final point in elements(document, 'navPoint')) {
        final target = elements(
          point,
          'content',
        ).firstOrNull?.getAttribute('src');
        final label = elements(point, 'navLabel').firstOrNull?.innerText.trim();
        if (target != null && label != null) {
          labels.putIfAbsent(resolve(path, target), () => label);
        }
      }
    }
  }
  final chapters = <String, String>{};
  var textBytes = 0;
  for (final ref in elements(opf, 'itemref')) {
    if (ref.getAttribute('linear') == 'no') continue;
    final item = items[ref.getAttribute('idref')];
    final href = item?.getAttribute('href');
    if (href == null) continue;
    final path = resolve(package, href);
    final html = read(path);
    textBytes += html.length * 2;
    if (textBytes > maxText) {
      throw const FormatException('EPUB text exceeds 12 MB');
    }
    final title = (labels[path]?.isNotEmpty ?? false)
        ? labels[path]!
        : 'Chapter ${chapters.length + 1}';
    var unique = title;
    for (var suffix = 2; chapters.containsKey(unique); suffix++) {
      unique = '$title ($suffix)';
    }
    chapters[unique] = html;
  }
  if (chapters.isEmpty) {
    throw const FormatException('EPUB contains no readable chapters');
  }
  return chapters;
}
