
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// An open page, and how big it really is.
typedef OpenPage = ({int handle, int width, int height});

/// Decodes the part of a manga page that is on screen, at the size it is being
/// shown at.
///
/// A page is decoded once, scaled down to the column it is drawn in, and then
/// zoomed — so zooming magnifies a bitmap that was thrown away at screen width.
/// On a dense page, a spread, or anything with small lettering, that is the
/// difference between reading it and not. Decoding at full size instead is not
/// an option: a webtoon strip is tens of thousands of pixels tall, and one of
/// those in memory is hundreds of megabytes.
///
/// Android's `BitmapRegionDecoder` solves exactly this — it holds the file, not
/// the image, and answers for any rectangle at any sample size.
///
/// Android only, and that is not a gap to apologise for: everywhere else the
/// reader keeps doing what it did, which is a correct page at column
/// resolution. [isSupported] is what every caller branches on.
class PageTiles {
  PageTiles._();

  static const MethodChannel _channel = MethodChannel('soplay/tiles');

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Opens [path], or null when it is not an image that can be region-decoded.
  ///
  /// Null is an ordinary answer, not a failure: a GIF, a WEBP the platform
  /// declines, a file still being written. The caller draws the page the
  /// ordinary way and does not offer a sharp zoom.
  static Future<OpenPage?> open(String path) async {
    if (!isSupported || path.isEmpty) return null;
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('open', {
        'path': path,
      });
      if (result == null) return null;
      final width = (result['width'] as num?)?.toInt() ?? 0;
      final height = (result['height'] as num?)?.toInt() ?? 0;
      final handle = (result['handle'] as num?)?.toInt() ?? 0;
      if (handle == 0 || width <= 0 || height <= 0) return null;
      return (handle: handle, width: width, height: height);
    } catch (e) {
      debugPrint('[tiles] open failed: $e');
      return null;
    }
  }

  /// One rectangle of an open page, as encoded image bytes.
  static Future<Uint8List?> region(
    int handle, {
    required int left,
    required int top,
    required int right,
    required int bottom,
    int sampleSize = 1,
  }) async {
    if (!isSupported) return null;
    try {
      return await _channel.invokeMethod<Uint8List>('region', {
        'handle': handle,
        'left': left,
        'top': top,
        'right': right,
        'bottom': bottom,
        'sampleSize': sampleSize,
      });
    } catch (e) {
      debugPrint('[tiles] region failed: $e');
      return null;
    }
  }

  /// Closes one page. The decoder holds a file descriptor and a native buffer,
  /// so a reader that has scrolled two hundred pages holds two hundred of each
  /// if nothing closes them.
  static Future<void> close(int handle) async {
    if (!isSupported || handle == 0) return;
    try {
      await _channel.invokeMethod<bool>('close', {'handle': handle});
    } catch (_) {}
  }

  static Future<void> closeAll() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<bool>('closeAll');
    } catch (_) {}
  }

  /// The power-of-two sample size that gets [sourcePixels] down to about
  /// [targetPixels] without going under it.
  ///
  /// Under is what matters. A tile decoded smaller than the space it is drawn
  /// in is blurrier than the page it is replacing — which would make the sharp
  /// zoom actively worse than no zoom at all. So this rounds towards more
  /// detail, and the decoder rounds down to a power of two itself.
  static int sampleSizeFor({
    required int sourcePixels,
    required int targetPixels,
  }) {
    if (targetPixels <= 0 || sourcePixels <= targetPixels) return 1;
    var sample = 1;
    while (sourcePixels ~/ (sample * 2) >= targetPixels) {
      sample *= 2;
    }
    return sample;
  }

  /// The source rectangle a viewport shows, in image pixels.
  ///
  /// [scale] and [offset] are an InteractiveViewer's, [viewport] is the widget
  /// it fills and [drawn] is the size the page is drawn at before zooming. The
  /// rect is padded by [overscan] of a viewport on each side so a small pan
  /// does not immediately land outside what was decoded.
  ///
  /// Pure arithmetic and public for it: this is the part of tiling that is
  /// actually easy to get wrong, and it can be checked exactly without a
  /// decoder, a file or a device.
  static ({int left, int top, int right, int bottom}) visibleRect({
    required double scale,
    required Offset offset,
    required Size viewport,
    required Size drawn,
    required int imageWidth,
    required int imageHeight,
    double overscan = 0.25,
  }) {
    // Widget space -> drawn-page space.
    final pad = Offset(viewport.width * overscan, viewport.height * overscan);
    final topLeft = (-offset - pad) / scale;
    final bottomRight =
        (Offset(viewport.width, viewport.height) - offset + pad) / scale;

    // Drawn-page space -> image pixels.
    final sx = drawn.width <= 0 ? 1.0 : imageWidth / drawn.width;
    final sy = drawn.height <= 0 ? 1.0 : imageHeight / drawn.height;

    int clampX(double v) => v.clamp(0, imageWidth.toDouble()).round();
    int clampY(double v) => v.clamp(0, imageHeight.toDouble()).round();

    return (
      left: clampX(topLeft.dx * sx),
      top: clampY(topLeft.dy * sy),
      right: clampX(bottomRight.dx * sx),
      bottom: clampY(bottomRight.dy * sy),
    );
  }
}
