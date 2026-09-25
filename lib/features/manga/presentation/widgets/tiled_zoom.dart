import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:soplay/features/manga/data/page_tiles.dart';

/// A page that gets sharper when you zoom into it.
///
/// [child] is the page as the reader already draws it — decoded to the width of
/// the column it sits in, which is right for reading and wrong the moment
/// somebody pinches. Zoomed, that bitmap is magnified rather than re-read, so a
/// dense page or small lettering turns to mush exactly when it is being looked
/// at closely.
///
/// So above [_sharpenAt] this decodes the part of the file that is on screen,
/// at the size it is being shown at, and paints it over the top. Nothing here
/// ever holds the whole page: [sourcePath] is opened by a region decoder that
/// keeps the file rather than the image.
///
/// The base child is never removed. It is what is on screen while a tile is
/// being decoded, what stays when the decoder declines the file, and what the
/// whole widget falls back to on any platform without [PageTiles].
class TiledZoom extends StatefulWidget {
  const TiledZoom({
    super.key,
    required this.child,
    required this.sourcePath,
    this.maxScale = 4,
  });

  final Widget child;

  /// The file behind [child], or null when there is not one yet — a network
  /// page still downloading, say. Null means this behaves exactly like the
  /// InteractiveViewer it replaces.
  final String? sourcePath;

  final double maxScale;

  /// Below this there is nothing to gain: the page is being drawn at or under
  /// the size it was decoded for, so a tile would be the same pixels.
  static const double _sharpenAt = 1.35;

  @override
  State<TiledZoom> createState() => _TiledZoomState();
}

class _TiledZoomState extends State<TiledZoom> {
  final TransformationController _controller = TransformationController();

  OpenPage? _page;
  Future<OpenPage?>? _opening;

  Uint8List? _tile;

  /// The rect [_tile] covers, in image pixels, so a pan inside it costs
  /// nothing.
  ({int left, int top, int right, int bottom})? _tileRect;

  Timer? _settle;
  int _decodeToken = 0;
  Size _viewport = Size.zero;
  Size _drawn = Size.zero;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTransform);
  }

  @override
  void didUpdateWidget(TiledZoom old) {
    super.didUpdateWidget(old);
    if (old.sourcePath != widget.sourcePath) _release();
  }

  @override
  void dispose() {
    _settle?.cancel();
    _controller.removeListener(_onTransform);
    _controller.dispose();
    _release();
    super.dispose();
  }

  void _release() {
    final handle = _page?.handle;
    _page = null;
    _opening = null;
    _tile = null;
    _tileRect = null;
    if (handle != null) unawaited(PageTiles.close(handle));
  }

  double get _scale => _controller.value.getMaxScaleOnAxis();

  Offset get _offset => Offset(
    _controller.value.getTranslation().x,
    _controller.value.getTranslation().y,
  );

  void _onTransform() {
    if (_scale < TiledZoom._sharpenAt) {
      if (_tile != null) setState(() => _tile = null);
      _settle?.cancel();
      return;
    }
    // Only once the gesture has settled. Decoding on every frame of a pinch
    // would queue dozens of region reads for viewports nobody ever looked at,
    // and the base image is perfectly readable in the meantime.
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 120), _sharpen);
  }

  Future<void> _sharpen() async {
    final path = widget.sourcePath;
    if (!PageTiles.isSupported || path == null || path.isEmpty) return;
    if (_viewport.isEmpty || _drawn.isEmpty) return;

    final page = _page ?? await (_opening ??= PageTiles.open(path));
    if (!mounted || page == null) return;
    _page = page;

    final rect = PageTiles.visibleRect(
      scale: _scale,
      offset: _offset,
      viewport: _viewport,
      drawn: _drawn,
      imageWidth: page.width,
      imageHeight: page.height,
    );
    final current = _tileRect;
    if (current != null &&
        rect.left >= current.left &&
        rect.top >= current.top &&
        rect.right <= current.right &&
        rect.bottom <= current.bottom) {
      return;
    }

    final dpr = MediaQuery.devicePixelRatioOf(context);
    final sample = PageTiles.sampleSizeFor(
      sourcePixels: rect.right - rect.left,
      // What the region will actually occupy on the glass. Asking for more
      // than that is memory spent on pixels the panel cannot show.
      targetPixels: (_viewport.width * 1.5 * dpr).round(),
    );

    final token = ++_decodeToken;
    final bytes = await PageTiles.region(
      page.handle,
      left: rect.left,
      top: rect.top,
      right: rect.right,
      bottom: rect.bottom,
      sampleSize: sample,
    );
    if (!mounted || token != _decodeToken || bytes == null) return;
    setState(() {
      _tile = bytes;
      _tileRect = rect;
    });
  }

  /// Where [_tileRect] sits in the untransformed child, so the tile can be
  /// positioned in the same coordinate space the child is laid out in and let
  /// the InteractiveViewer's own matrix carry it.
  Rect? get _tilePlacement {
    final rect = _tileRect;
    final page = _page;
    if (rect == null || page == null || _drawn.isEmpty) return null;
    final sx = _drawn.width / page.width;
    final sy = _drawn.height / page.height;
    return Rect.fromLTRB(
      rect.left * sx,
      rect.top * sy,
      rect.right * sx,
      rect.bottom * sy,
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _viewport = Size(
        constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width,
        constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : MediaQuery.sizeOf(context).height,
      );
      return InteractiveViewer(
        transformationController: _controller,
        maxScale: widget.maxScale,
        child: _MeasuredChild(
          onSize: (size) => _drawn = size,
          child: Stack(
            children: [
              widget.child,
              if (_tile != null && _tilePlacement != null)
                Positioned.fromRect(
                  rect: _tilePlacement!,
                  child: Image.memory(
                    _tile!,
                    fit: BoxFit.fill,
                    gaplessPlayback: true,
                    // Nearest-neighbour would show the sample step as blocking
                    // at the moment the tile lands.
                    filterQuality: FilterQuality.medium,
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// Reports its child's laid-out size, which is the page's drawn size and the
/// thing every coordinate here is relative to.
class _MeasuredChild extends SingleChildRenderObjectWidget {
  const _MeasuredChild({required this.onSize, required super.child});

  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasured(onSize);

  @override
  void updateRenderObject(BuildContext context, _RenderMeasured renderObject) {
    renderObject.onSize = onSize;
  }
}

class _RenderMeasured extends RenderProxyBox {
  _RenderMeasured(this.onSize);

  ValueChanged<Size> onSize;

  @override
  void performLayout() {
    super.performLayout();
    onSize(size);
  }
}
