// A chapter has to be openable on the site that published it.
//
// The blocker was never the UI: a Mihon or Aniyomi extension stores
// `SManga.url` and `SChapter.url` as paths relative to its own `baseUrl` —
// `/manga/x/chapter-1`, not a link — so the app held nothing a browser could be
// handed, for the whole extension ecosystem. The hosts are the only place that
// has both halves, so that is where they are joined, and `webUrl` is what
// arrives here.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/detail/data/models/episode_model.dart';

void main() {
  group('the chapter carries its own page', () {
    test('webUrl survives the json', () {
      final e = EpisodeModel.fromJson(const {
        'episode': 3,
        'label': 'Chapter 3',
        'mediaRef': '/manga/x/ch-3',
        'webUrl': 'https://source.test/manga/x/ch-3',
      });
      expect(e.webUrl, 'https://source.test/manga/x/ch-3');
    });

    test('and a provider that names none leaves it null', () {
      // Not an empty string: the reader hides the action on null, and an empty
      // string would put a button on screen that opens nothing.
      final e = EpisodeModel.fromJson(const {
        'episode': 1,
        'label': 'Episode 1',
        'mediaRef': 'anikoto:8688:1',
      });
      expect(e.webUrl, isNull);
      expect(
        EpisodeModel.fromJson(const {'webUrl': '   '}).webUrl,
        isNull,
        reason: 'whitespace is not a link',
      );
    });
  });

  group('the hosts resolve a relative path against their own base', () {
    // Read from the Kotlin rather than reimplemented here: the rule has to be
    // the same on both hosts, and the only way to check that is to look.
    String host(String path) => File(path).readAsStringSync();
    final manga = host('android/app/src/main/kotlin/com/soplay/sozo/manga/MangaHost.kt');
    final aniyomi = host('android/app/src/main/kotlin/com/soplay/sozo/aniyomi/AniyomiHost.kt');

    test('both have the helper and both send the field', () {
      for (final src in [manga, aniyomi]) {
        expect(src, contains('private fun webUrl('));
        expect(src, contains('put("webUrl"'));
      }
    });

    test('an absolute path is left alone', () {
      for (final src in [manga, aniyomi]) {
        expect(src, contains('if (p.startsWith("http://") || p.startsWith("https://")) return p'));
      }
    });

    test('and a source with no base sends nothing at all', () {
      // An action that cannot work must not reach the screen, so the field is
      // omitted rather than sent empty.
      for (final src in [manga, aniyomi]) {
        expect(src, contains('if (base.isEmpty()) return ""'));
        expect(src, contains('takeIf { it.isNotEmpty() }?.let { put("webUrl"'));
      }
    });
  });

  test('the reader only offers the action when there is a link', () {
    final reader = File(
      'lib/features/manga/presentation/pages/reader_page.dart',
    ).readAsStringSync();
    expect(reader, contains('if (_chapterOnSite case final uri?)'));
    // http(s) only: a source that hands back a `javascript:` or an app scheme
    // must not be launched into whatever claims it.
    expect(reader, contains("uri.scheme != 'http' && uri.scheme != 'https'"));
  });
}
