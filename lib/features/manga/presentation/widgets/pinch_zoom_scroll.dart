import 'package:flutter/material.dart';

/// Pinch zoom over a scrolling list of pages, for the continuous reader.
///
/// One finger still scrolls: a vertical drag belongs to the list and a sideways
/// one pans the zoomed page. Two fingers must belong to the zoom, and a list
/// that can still drag takes a pinch whose fingers move up or down for a scroll,
/// so while two are down the list is told not to scroll at all.
class PinchZoomScroll extends StatefulWidget {
  const PinchZoomScroll({super.key, required this.builder, this.maxScale = 4});

  /// The list, given the physics it has to use right now.
  final Widget Function(BuildContext context, ScrollPhysics? physics) builder;
  final double maxScale;

  @override
  State<PinchZoomScroll> createState() => _PinchZoomScrollState();
}

class _PinchZoomScrollState extends State<PinchZoomScroll> {
  final ValueNotifier<bool> _pinching = ValueNotifier(false);
  final TransformationController _transform = TransformationController();
  int _pointers = 0;

  void _track(int change) {
    _pointers = (_pointers + change).clamp(0, 10);
    _pinching.value = _pointers >= 2;
  }

  @override
  void dispose() {
    _pinching.dispose();
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _track(1),
      onPointerUp: (_) => _track(-1),
      onPointerCancel: (_) => _track(-1),
      child: InteractiveViewer(
        transformationController: _transform,
        maxScale: widget.maxScale,
        child: ValueListenableBuilder<bool>(
          valueListenable: _pinching,
          builder: (context, pinching, _) => widget.builder(
            context,
            pinching ? const NeverScrollableScrollPhysics() : null,
          ),
        ),
      ),
    );
  }
}
