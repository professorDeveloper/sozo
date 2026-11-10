import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/network/web_page_sniff.dart';

void main() {
  test('MPEG-TS served as page-N.html is media', () {
    // vidapi's page-0.html and anikoto's seg-2-f1-v1-a1.html, as served.
    expect(looksLikeWebPage([0x47, 0x40, 0x00, 0x30, 0x10, 0x00]), isFalse);
    expect(looksLikeWebPage([0x47, 0x40, 0x00, 0x11]), isFalse);
  });

  test('containers, images and SVG are media', () {
    expect(
      looksLikeWebPage([0, 0, 0, 24, ...'ftypmp42'.codeUnits]),
      isFalse,
    );
    expect(looksLikeWebPage([0x1a, 0x45, 0xdf, 0xa3]), isFalse);
    expect(looksLikeWebPage([0xff, 0xd8, 0xff, 0xe0]), isFalse);
    expect(looksLikeWebPage('<?xml version="1.0"?><svg>'.codeUnits), isFalse);
    expect(looksLikeWebPage('<svg xmlns="x">'.codeUnits), isFalse);
  });

  test('random bytes, as an encrypted segment is, are media', () {
    final random = Random(7);
    for (var i = 0; i < 2000; i++) {
      final bytes = List.generate(512, (_) => random.nextInt(256));
      expect(looksLikeWebPage(bytes), isFalse);
    }
  });

  test('a web page is refused, past a BOM and blank lines', () {
    expect(looksLikeWebPage('<!DOCTYPE html><html>'.codeUnits), isTrue);
    expect(looksLikeWebPage('<HTML lang="en">'.codeUnits), isTrue);
    expect(looksLikeWebPage('<head><title>403'.codeUnits), isTrue);
    expect(looksLikeWebPage('<script>location="/"'.codeUnits), isTrue);
    expect(
      looksLikeWebPage([0xef, 0xbb, 0xbf, ...'\r\n \t<!doctype html>'.codeUnits]),
      isTrue,
    );
  });

  test('nothing, or only blanks, is not a page', () {
    expect(looksLikeWebPage(const []), isFalse);
    expect(looksLikeWebPage('  \n'.codeUnits), isFalse);
    expect(looksLikeWebPage('<ht'.codeUnits), isFalse);
  });
}
