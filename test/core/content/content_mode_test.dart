import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/content/content_mode.dart';

void main() {
  group('ids', () {
    test('are unique and stable-looking', () {
      final ids = ContentMode.values.map((m) => m.id).toList();
      expect(ids.toSet().length, ids.length);
      for (final id in ids) {
        expect(RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(id), isTrue, reason: id);
      }
    });

    test('an unknown or missing id is video', () {
      // What every install upgraded from a build with no modes hands us, and
      // the only answer that can never leave somebody on an empty screen.
      expect(ContentMode.fromId(null), ContentMode.video);
      expect(ContentMode.fromId(''), ContentMode.video);
      expect(ContentMode.fromId('audiobook'), ContentMode.video);
    });

    test('a stored id round-trips', () {
      for (final m in ContentMode.values) {
        expect(ContentMode.fromId(m.id), m);
      }
    });
  });

  group('which mode a provider belongs to', () {
    test('a server provider is video', () {
      // Every backend provider is a video source; that is both the safe answer
      // and what the app did before modes existed.
      expect('hianimes'.contentMode, ContentMode.video);
      expect('uzmovi'.contentMode, ContentMode.video);
    });

    test('a CloudStream or Aniyomi source is video', () {
      expect('cs:some.plugin'.contentMode, ContentMode.video);
      expect('an:some.extension'.contentMode, ContentMode.video);
    });

    test('a Mihon source is manga', () {
      expect('mn:eu.kanade.tachiyomi.extension.all.mangadex'.contentMode,
          ContentMode.manga);
    });

    test('an unresolvable Mangayomi source reads as manga, not video', () {
      // DI is not up in a unit test, so the source cannot be looked up. Manga
      // is the right fallback for a reader: the manga index dwarfs the novel
      // one, and calling it video would send a chapter to the video player.
      expect('my:12345'.contentMode, ContentMode.manga);
    });

    test('accepts agrees with contentMode', () {
      expect(ContentMode.video.accepts('hianimes'), isTrue);
      expect(ContentMode.manga.accepts('hianimes'), isFalse);
      expect(ContentMode.manga.accepts('mn:x'), isTrue);
    });
  });

  group('labels', () {
    test('every mode names a translation key under mode.', () {
      for (final m in ContentMode.values) {
        expect(m.labelKey.startsWith('mode.'), isTrue, reason: m.id);
      }
    });
  });
}
