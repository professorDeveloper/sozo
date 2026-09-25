// A zoomed page was a bitmap decoded at column width, magnified.
//
// That is exactly when a dense page or small lettering turns to mush — the
// moment somebody is looking at it closely. Decoding the whole page at full
// size instead is not an option: a webtoon strip is tens of thousands of pixels
// tall and one of those in memory is hundreds of megabytes. So the part that is
// on screen is re-read from the file at the size it is being shown at.
//
// The decode itself is a platform call. The arithmetic around it is not, and it
// is the part that is actually easy to get wrong, so it is checked here
// exactly — no decoder, no file, no device.
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/manga/data/page_tiles.dart';

void main() {
  group('how much detail to ask for', () {
    test('a source smaller than the target is read whole', () {
      expect(
        PageTiles.sampleSizeFor(sourcePixels: 800, targetPixels: 1080),
        1,
      );
    });

    test('and it halves while a half still covers the target', () {
      expect(PageTiles.sampleSizeFor(sourcePixels: 2160, targetPixels: 1080), 2);
      expect(PageTiles.sampleSizeFor(sourcePixels: 4320, targetPixels: 1080), 4);
      expect(PageTiles.sampleSizeFor(sourcePixels: 8640, targetPixels: 1080), 8);
    });

    test('it never goes under the target', () {
      // Under is the one failure that matters: a tile decoded smaller than the
      // space it is drawn in is blurrier than the page it replaces, which would
      // make the sharp zoom actively worse than no zoom at all.
      for (final source in [1081, 1500, 2159, 3000, 5000, 12000]) {
        final sample = PageTiles.sampleSizeFor(
          sourcePixels: source,
          targetPixels: 1080,
        );
        expect(
          source ~/ sample,
          greaterThanOrEqualTo(1080),
          reason: '$source / $sample is under the target',
        );
      }
    });

    test('a nonsense target does not divide by zero', () {
      expect(PageTiles.sampleSizeFor(sourcePixels: 2000, targetPixels: 0), 1);
      expect(PageTiles.sampleSizeFor(sourcePixels: 2000, targetPixels: -5), 1);
    });
  });

  group('which part of the page is on screen', () {
    const viewport = Size(400, 800);
    const drawn = Size(400, 600);

    test('unzoomed and unpanned, the whole drawn page', () {
      final rect = PageTiles.visibleRect(
        scale: 1,
        offset: Offset.zero,
        viewport: viewport,
        drawn: drawn,
        imageWidth: 2000,
        imageHeight: 3000,
        overscan: 0,
      );
      expect(rect.left, 0);
      expect(rect.top, 0);
      expect(rect.right, 2000);
      // The viewport is taller than the page, so the bottom clamps to the
      // image rather than running past it.
      expect(rect.bottom, 3000);
    });

    test('zoomed in on the top-left corner', () {
      final rect = PageTiles.visibleRect(
        scale: 2,
        offset: Offset.zero,
        viewport: viewport,
        drawn: drawn,
        imageWidth: 2000,
        imageHeight: 3000,
        overscan: 0,
      );
      expect(rect.left, 0);
      expect(rect.top, 0);
      // Half the width at 2x, mapped through drawn(400) -> image(2000).
      expect(rect.right, 1000);
    });

    test('panned right, the rect moves right', () {
      final rect = PageTiles.visibleRect(
        scale: 2,
        offset: const Offset(-200, 0),
        viewport: viewport,
        drawn: drawn,
        imageWidth: 2000,
        imageHeight: 3000,
        overscan: 0,
      );
      // 200 widget px at 2x is 100 drawn px, which is 500 image px.
      expect(rect.left, 500);
      expect(rect.right, 1500);
    });

    test('overscan pads it, and the clamp still holds', () {
      // A small pan should land inside what was already decoded, but padding
      // must never produce a rect the decoder would throw on.
      final rect = PageTiles.visibleRect(
        scale: 2,
        offset: Offset.zero,
        viewport: viewport,
        drawn: drawn,
        imageWidth: 2000,
        imageHeight: 3000,
      );
      expect(rect.left, 0, reason: 'padding must not go negative');
      expect(rect.right, greaterThan(1000));
      expect(rect.right, lessThanOrEqualTo(2000));
      expect(rect.bottom, lessThanOrEqualTo(3000));
    });

    test('a page drawn at zero size does not divide by zero', () {
      final rect = PageTiles.visibleRect(
        scale: 1,
        offset: Offset.zero,
        viewport: viewport,
        drawn: Size.zero,
        imageWidth: 2000,
        imageHeight: 3000,
      );
      expect(rect.left, isA<int>());
      expect(rect.right, lessThanOrEqualTo(2000));
    });
  });

  group('where it applies', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('Android, where BitmapRegionDecoder is', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(PageTiles.isSupported, isTrue);
    });

    test('and nowhere else, which costs nothing', () {
      // Not a gap to apologise for: elsewhere the page is still drawn correctly
      // at column resolution and the reader behaves exactly as it did. Every
      // caller branches on this rather than on a try/catch around a channel
      // that is not there.
      for (final platform in [
        TargetPlatform.iOS,
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        expect(PageTiles.isSupported, isFalse, reason: '$platform');
      }
    });

    test('an unsupported platform answers null rather than throwing', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(await PageTiles.open('/tmp/whatever.jpg'), isNull);
      expect(await PageTiles.region(1, left: 0, top: 0, right: 1, bottom: 1), isNull);
      // And closing something that was never opened is a no-op, not a crash.
      await PageTiles.close(0);
      await PageTiles.closeAll();
    });
  });
}
