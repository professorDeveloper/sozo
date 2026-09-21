import 'dart:async';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/theme/app_colors.dart';

/// A split-flap countdown.
///
/// The point of the shape is that it reports CHANGE, not just a number: a
/// digit that flips is the difference between "there is a clock here" and "it
/// is running". A line of text saying "in 3d 4h" says neither — it looked
/// identical whether it had been computed a second ago or when the page opened,
/// which it had been, because nothing ticked it.
///
/// Every digit animates independently, so the seconds flip once a second and
/// the days sit still for a day. That is also what makes it cheap: one short
/// controller runs at a time, and the widget above rebuilds once a second
/// rather than every frame.
class FlipClock extends StatefulWidget {
  const FlipClock({
    super.key,
    required this.target,
    this.onFinished,
    this.compact = false,
    this.now,
  });

  /// The moment being counted down to.
  final DateTime target;

  /// Called once, when the clock reaches zero. The caller decides what a
  /// finished countdown becomes — usually a reload, since the thing being
  /// waited for has just happened.
  final VoidCallback? onFinished;

  /// Narrower cards and smaller labels, for a row that has to share its line.
  final bool compact;

  /// What time it is, for a caller that needs to say.
  ///
  /// Null is the wall clock, which is every use in the app. It exists because
  /// a countdown that reads `DateTime.now()` directly cannot be driven at all:
  /// a widget test's clock does not advance, so there is no way to assert that
  /// the thing ticks — which is the entire behaviour.
  final DateTime Function()? now;

  @override
  State<FlipClock> createState() => _FlipClockState();
}

class _FlipClockState extends State<FlipClock> {
  Timer? _tick;
  late Duration _left;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _left = _remaining();
    // Aligned to the second boundary rather than to whenever the page opened,
    // so two clocks on one screen flip together instead of a fifth of a second
    // apart.
    _tick = Timer.periodic(const Duration(milliseconds: 200), (_) {
      final next = _remaining();
      if (next.inSeconds == _left.inSeconds) return;
      if (!mounted) return;
      setState(() => _left = next);
      if (next == Duration.zero && !_finished) {
        _finished = true;
        widget.onFinished?.call();
      }
    });
  }

  @override
  void didUpdateWidget(FlipClock old) {
    super.didUpdateWidget(old);
    if (old.target != widget.target) {
      _finished = false;
      setState(() => _left = _remaining());
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Duration _remaining() {
    final d = widget.target.difference((widget.now ?? DateTime.now)());
    return d.isNegative ? Duration.zero : d;
  }

  @override
  Widget build(BuildContext context) {
    final days = _left.inDays;
    final hours = _left.inHours % 24;
    final minutes = _left.inMinutes % 60;
    final seconds = _left.inSeconds % 60;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Days are dropped once there are none, rather than shown as "00".
        // A pair of zeros on the left is the clock claiming a precision the
        // rest of the row already has, and it costs the space the seconds need.
        if (days > 0) ...[
          _Group(
            value: days,
            label: 'detail.cd_days'.tr(),
            compact: widget.compact,
            // Past ninety-nine days a third card is the honest answer; a
            // clamped "99" would be a lie a viewer cannot see through.
            pad: days >= 100 ? 3 : 2,
          ),
          _Separator(compact: widget.compact),
        ],
        _Group(
          value: hours,
          label: 'detail.cd_hours'.tr(),
          compact: widget.compact,
        ),
        _Separator(compact: widget.compact),
        _Group(
          value: minutes,
          label: 'detail.cd_minutes'.tr(),
          compact: widget.compact,
        ),
        // Seconds are always on, days or no days.
        //
        // They were dropped past a day on the grounds that a digit flipping
        // sixty times a minute next to one that moves once a day is noise. It
        // is not: the second card is the only part of this that is visibly
        // alive, and without it a clock four days out is a static row of
        // numbers that could as easily be a stopped one. The cost is a repaint
        // a second, of four cards.
        _Separator(compact: widget.compact),
        _Group(
          value: seconds,
          label: 'detail.cd_seconds'.tr(),
          compact: widget.compact,
        ),
      ],
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({
    required this.value,
    required this.label,
    required this.compact,
    this.pad = 2,
  });

  final int value;
  final String label;
  final bool compact;
  final int pad;

  @override
  Widget build(BuildContext context) {
    final digits = value.toString().padLeft(pad, '0');
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < digits.length; i++) ...[
              if (i > 0) const SizedBox(width: 3),
              FlipDigit(digit: digits[i], compact: compact),
            ],
          ],
        ),
        SizedBox(height: compact ? 3 : 5),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: AppColors.textHint,
            fontSize: compact ? 8 : 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.9,
          ),
        ),
      ],
    );
  }
}

class _Separator extends StatelessWidget {
  const _Separator({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(horizontal: compact ? 3 : 4),
    child: SizedBox(
      height: FlipDigit.heightFor(compact),
      child: Center(
        child: Text(
          ':',
          style: TextStyle(
            color: AppColors.textHint.withValues(alpha: 0.55),
            fontSize: compact ? 13 : 16,
            fontWeight: FontWeight.w900,
            height: 1,
          ),
        ),
      ),
    ),
  );
}

/// One card, which turns over when its digit changes.
///
/// A split-flap, built the way one is built: the card is two leaves meeting at
/// a fold. The top leaf carrying the OLD digit falls forward to the fold, and
/// then the bottom leaf carrying the NEW one swings up from it, while behind
/// them the new digit's top and the old digit's bottom sit still.
///
/// What it replaced was one rigid card rotating a full half-turn about its own
/// middle, which is not the same movement at all. Both halves of the glyph went
/// edge-on together, so the digit vanished into a line and reappeared — a
/// squash and a pop, with the swap hidden in the moment it was invisible. There
/// is nothing to hide here: the new digit's top half is on screen from the
/// first frame, uncovered by the leaf falling off it, which is the whole reason
/// the mechanism reads as a mechanism.
///
/// The leaf falls on [Curves.easeIn] and rises on [Curves.easeOut] — it is
/// being dropped and then caught, and an even rate through both reads as a
/// diagram of a flip rather than a flip.
class FlipDigit extends StatefulWidget {
  const FlipDigit({super.key, required this.digit, this.compact = false});

  final String digit;
  final bool compact;

  static double widthFor(bool compact) => compact ? 20 : 26;
  static double heightFor(bool compact) => compact ? 28 : 36;

  @override
  State<FlipDigit> createState() => _FlipDigitState();
}

class _FlipDigitState extends State<FlipDigit>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 340),
  );

  late String _shown = widget.digit;

  /// The digit being flipped away from. Null when the card is at rest, which
  /// is what lets a resting card skip the whole stack and paint one face.
  String? _outgoing;

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((status) {
      if (status != AnimationStatus.completed || !mounted) return;
      // Dropped at the end rather than left set, so a settled card is one
      // Container again instead of four layers and a perspective matrix.
      setState(() => _outgoing = null);
    });
  }

  @override
  void didUpdateWidget(FlipDigit old) {
    super.didUpdateWidget(old);
    if (old.digit == widget.digit) return;
    // Mid-flip when the next second lands — which happens whenever a frame is
    // late — the leaf would otherwise carry a digit two steps old. The one in
    // flight is abandoned and the new turn starts from the digit that was
    // actually on screen.
    _outgoing = _shown;
    _shown = widget.digit;
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = FlipDigit.widthFor(widget.compact);
    final h = FlipDigit.heightFor(widget.compact);

    return SizedBox(
      width: w,
      height: h,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final outgoing = _outgoing;
          if (outgoing == null) return _face(_shown);

          final t = _c.value;
          final falling = t < 0.5;
          // The fold is at a quarter turn, not a half: each leaf travels only
          // to the flat, and the other one takes it from there.
          final angle = falling
              ? -_quarter * Curves.easeIn.transform(t * 2)
              : -_quarter * (1 - Curves.easeOut.transform((t - 0.5) * 2));

          return Stack(
            fit: StackFit.expand,
            children: [
              // Behind the leaf: what the card will read as when it settles,
              // top half already correct.
              _half(_shown, top: true),
              // And what it read as before, bottom half not yet replaced.
              _half(outgoing, top: false),
              // The leaf in flight. Falling, it is the old top, hinged at its
              // lower edge; rising, the new bottom, hinged at its upper one.
              Align(
                alignment: falling
                    ? Alignment.topCenter
                    : Alignment.bottomCenter,
                child: Transform(
                  alignment: falling
                      ? Alignment.bottomCenter
                      : Alignment.topCenter,
                  transform: Matrix4.identity()
                    // The far edge narrows. Without it the leaf scales instead
                    // of turning, which is what makes a flip look like a
                    // squash.
                    ..setEntry(3, 2, 0.0016)
                    ..rotateX(falling ? angle : -angle),
                  child: _half(
                    falling ? outgoing : _shown,
                    top: falling,
                    // A leaf turning away from the light loses it. This is the
                    // difference between a card that moves and a card with a
                    // thickness — and on the way back up it lifts again, so
                    // the new digit arrives lit rather than appearing.
                    shade: falling
                        ? Curves.easeIn.transform(t * 2) * 0.55
                        : (1 - Curves.easeOut.transform((t - 0.5) * 2)) * 0.55,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static const double _quarter = math.pi / 2;

  /// One leaf: the card, clipped to the half of it that this leaf is.
  ///
  /// Clipped out of the whole face rather than drawn as its own box, so the
  /// rounding, the gradient and the glyph are continuous across the fold —
  /// half a card drawn independently has its own rounded corners at the fold
  /// and its own slice of the gradient, and the two halves stop lining up.
  Widget _half(String digit, {required bool top, double shade = 0}) {
    final h = FlipDigit.heightFor(widget.compact);
    return SizedBox(
      height: h / 2,
      child: ClipRect(
        child: Align(
          alignment: top ? Alignment.topCenter : Alignment.bottomCenter,
          heightFactor: 0.5,
          child: SizedBox(
            height: h,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _face(digit),
                if (shade > 0)
                  IgnorePointer(
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: shade),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The whole card, at rest.
  Widget _face(String digit) {
    final w = FlipDigit.widthFor(widget.compact);
    final h = FlipDigit.heightFor(widget.compact);
    return Container(
      width: w,
      height: h,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        // A vertical seam, because a split-flap has one: the card is lighter
        // above the fold and darker below it.
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.surfaceVariant, AppColors.card],
        ),
        borderRadius: BorderRadius.circular(widget.compact ? 5 : 7),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            digit,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: widget.compact ? 15 : 19,
              fontWeight: FontWeight.w800,
              height: 1,
              // A column of digits that does not jitter as the glyphs change
              // width.
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          // The hinge, drawn over the glyph because that is where it is: the
          // fold crosses the digit, it does not pass behind it.
          Align(
            child: Container(
              height: 1,
              color: Colors.black.withValues(alpha: 0.45),
            ),
          ),
        ],
      ),
    );
  }
}
