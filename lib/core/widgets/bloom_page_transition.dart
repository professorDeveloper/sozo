import 'package:flutter/material.dart';

/// How a title's page arrives: it blooms.
///
/// The incoming page starts a little small and a little low, and fades in
/// over the first half of the run while the scale and the rise ease out over
/// all of it — most of the distance at once, the last of it unhurried, the
/// same emphasized-decelerate the cards use to land. The page it covers
/// settles back and dims, so there is depth: the new page is in front of the
/// old one, not instead of it.
///
/// Popping runs the same thing backwards, which is the right shape for
/// leaving too: the page shrinks away and the one behind it comes forward.
/// Stateful so the curves are made once and disposed: a [CurvedAnimation]
/// attaches a listener to its parent in its constructor, and a route rebuilds
/// its transition on every frame of the run.
class BloomPageTransition extends StatefulWidget {
  const BloomPageTransition({
    super.key,
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
  });

  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Widget child;

  static const Duration duration = Duration(milliseconds: 380);
  static const Duration reverseDuration = Duration(milliseconds: 260);
  static const Curve _settle = Cubic(0.05, 0.7, 0.1, 1.0);

  @override
  State<BloomPageTransition> createState() => _BloomPageTransitionState();
}

class _BloomPageTransitionState extends State<BloomPageTransition> {
  late CurvedAnimation _settle;
  late CurvedAnimation _fade;
  late CurvedAnimation _behind;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  @override
  void didUpdateWidget(BloomPageTransition old) {
    super.didUpdateWidget(old);
    if (!identical(old.animation, widget.animation) ||
        !identical(old.secondaryAnimation, widget.secondaryAnimation)) {
      _detach();
      _attach();
    }
  }

  void _attach() {
    _settle = CurvedAnimation(
      parent: widget.animation,
      curve: BloomPageTransition._settle,
      reverseCurve: Curves.easeInCubic,
    );
    _fade = CurvedAnimation(
      parent: widget.animation,
      curve: const Interval(0, 0.55, curve: Curves.easeOut),
      reverseCurve: const Interval(0.3, 1, curve: Curves.easeIn),
    );
    _behind = CurvedAnimation(
      parent: widget.secondaryAnimation,
      curve: Curves.easeOutCubic,
    );
  }

  void _detach() {
    _settle.dispose();
    _fade.dispose();
    _behind.dispose();
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return FadeTransition(opacity: widget.animation, child: widget.child);
    }
    return AnimatedBuilder(
      animation: Listenable.merge([_settle, _fade, _behind]),
      child: widget.child,
      builder: (context, child) {
        final t = _settle.value;
        final back = _behind.value;
        final scale = (0.94 + 0.06 * t) * (1 - back * 0.03);
        return Opacity(
          opacity: _fade.value * (1 - back * 0.35),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..translateByDouble(0, 28 * (1 - t), 0, 1)
              ..scaleByDouble(scale, scale, 1, 1),
            child: child,
          ),
        );
      },
    );
  }
}
