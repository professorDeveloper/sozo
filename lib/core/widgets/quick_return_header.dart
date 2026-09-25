import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// A header that scrolls away with the list under it and comes back the
/// moment the list is pulled the other way — Android's
/// `scroll|enterAlways|snap`, the floating app bar every store and inbox uses.
///
/// Built for screens whose header cannot be a sliver of ONE scroll view: a
/// search field and filters above a `TabBarView`, where each tab is its own
/// list with its own controller. [NestedScrollView] is the stock answer and
/// the wrong one there, because it takes the inner controllers over — and
/// with them every "open the list on the current item" jump those screens do.
///
/// ## How it moves
///
/// The header is laid over the top of the body, not above it, and each list
/// starts with a [QuickReturnSpacer] as tall as the header. So the body's
/// viewport never changes size: hiding the header is a translation, one
/// transform per frame, and nothing is laid out again. (Collapsing a header
/// that sat ABOVE the list resized the list's viewport on every frame while
/// the list was also scrolling — the content moved at twice the finger's
/// speed and jumped when it finished.)
///
/// It follows the finger one-to-one, and only the finger: a drag or the fling
/// after it. A scroll the app makes itself — a jump to the item in use —
/// leaves it where it is. On release it settles fully in or fully out, and it
/// never leaves a gap at the top of a list scrolled less than its height.
class QuickReturnController {
  QuickReturnController({required TickerProvider vsync})
    : _snap = AnimationController(
        vsync: vsync,
        duration: const Duration(milliseconds: 200),
      ) {
    _snap.addListener(() {
      final t = Curves.easeOutCubic.transform(_snap.value);
      hidden.value = _from + (_to - _from) * t;
    });
  }

  /// How much of the header is scrolled out of view, from 0 to [extent].
  final ValueNotifier<double> hidden = ValueNotifier<double>(0);

  /// The header's measured height.
  final ValueNotifier<double> extent = ValueNotifier<double>(0);

  /// Whether content is scrolled beneath the header, for its shadow.
  final ValueNotifier<bool> overlapped = ValueNotifier<bool>(false);

  final AnimationController _snap;
  double _from = 0;
  double _to = 0;

  /// A drag, or the fling that follows one, is in progress.
  bool _user = false;

  /// The list's offset at the last update, so a list that returns to the top
  /// on its own can bring the header back with it.
  double _pixels = 0;

  bool handle(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    if (n is ScrollStartNotification) {
      _user = n.dragDetails != null;
      if (_user) _snap.stop();
    } else if (n is ScrollUpdateNotification) {
      _pixels = n.metrics.pixels;
      overlapped.value = _pixels > 0.5;
      if (n.dragDetails != null) _user = true;
      if (_user) {
        _set(hidden.value + (n.scrollDelta ?? 0));
      } else {
        _set(hidden.value); // re-clamp: never more hidden than scrolled
      }
    } else if (n is ScrollEndNotification) {
      _pixels = n.metrics.pixels;
      if (_user) _settle();
      _user = false;
    }
    return false;
  }

  void _set(double value) {
    final top = math.min(extent.value, math.max(_pixels, 0.0));
    hidden.value = value.clamp(0.0, top);
  }

  void _settle() {
    final h = extent.value;
    final v = hidden.value;
    if (v <= 0 || v >= h) return;
    // Out only if there is room: a list scrolled less than the header's
    // height would show the empty spacer where the header was.
    _animateTo(v > h / 2 && _pixels >= h ? h : 0);
  }

  /// Brings the header fully back — a new tab, a new search.
  void show() => _animateTo(0);

  void _animateTo(double target) {
    if ((hidden.value - target).abs() < 0.5) {
      hidden.value = target;
      return;
    }
    if (SchedulerBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations) {
      hidden.value = target;
      return;
    }
    _from = hidden.value;
    _to = target;
    _snap.forward(from: 0);
  }

  void _measured(double height) {
    if ((extent.value - height).abs() < 0.5) return;
    extent.value = height;
    _set(hidden.value);
  }

  void dispose() {
    _snap.dispose();
    hidden.dispose();
    extent.dispose();
    overlapped.dispose();
  }
}

/// The body with [header] floating over its top edge.
class QuickReturnLayout extends StatelessWidget {
  const QuickReturnLayout({
    super.key,
    required this.controller,
    required this.header,
    required this.body,
    required this.background,
  });

  final QuickReturnController controller;
  final Widget header;
  final Widget body;

  /// Opaque, because content passes underneath.
  final Color background;

  @override
  Widget build(BuildContext context) {
    // An explicit ClipRect, not the Stack's own clipBehavior. A Stack clips
    // only when a child's LAYOUT overflows it, and a translation is not
    // layout: the header slid up by a Transform was painted over whatever
    // sits above this box — the search field, the tabs — while taps there
    // still reached those widgets underneath. It looked like the header and
    // behaved like what it covered.
    return ClipRect(
      child: Stack(
        children: [
          Positioned.fill(
            child: NotificationListener<ScrollNotification>(
              onNotification: controller.handle,
              child: body,
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ValueListenableBuilder<double>(
              valueListenable: controller.hidden,
              builder: (context, hidden, child) =>
                  Transform.translate(offset: Offset(0, -hidden), child: child),
              child: _SizeReporter(
                onHeight: controller._measured,
                child: ValueListenableBuilder<bool>(
                  valueListenable: controller.overlapped,
                  builder: (context, overlapped, child) => AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    decoration: BoxDecoration(
                      color: background,
                      boxShadow: [
                        if (overlapped)
                          const BoxShadow(
                            color: Color(0x33000000),
                            blurRadius: 12,
                            offset: Offset(0, 4),
                          ),
                      ],
                    ),
                    child: child,
                  ),
                  child: header,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Room at the top of a list for the header floating over it.
class QuickReturnSpacer extends StatelessWidget {
  const QuickReturnSpacer({super.key, required this.controller});

  final QuickReturnController controller;

  /// As the first sliver of a [CustomScrollView].
  static Widget sliver(QuickReturnController controller) =>
      SliverToBoxAdapter(child: QuickReturnSpacer(controller: controller));

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
    valueListenable: controller.extent,
    builder: (context, h, _) => SizedBox(height: h),
  );
}

/// Reports its child's height after each layout that changes it.
class _SizeReporter extends SingleChildRenderObjectWidget {
  const _SizeReporter({required this.onHeight, super.child});

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSizeReporter(onHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSizeReporter renderObject,
  ) => renderObject.onHeight = onHeight;
}

class _RenderSizeReporter extends RenderProxyBox {
  _RenderSizeReporter(this.onHeight);

  ValueChanged<double> onHeight;
  double? _last;

  @override
  void performLayout() {
    super.performLayout();
    final h = size.height;
    if (_last == h) return;
    _last = h;
    // Not during layout: the spacer listening to this rebuilds, and a
    // rebuild may not be scheduled from inside another object's layout.
    SchedulerBinding.instance.addPostFrameCallback((_) => onHeight(h));
  }
}
