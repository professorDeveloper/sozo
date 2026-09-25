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
              // Four, not three: a leaf tilted towards the viewer overflows its
              // card by a couple of points, and at three the cards touched.
              if (i > 0) const SizedBox(width: 4),
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
/// A split-flap, built the way one is built. The card is two leaves meeting at
/// a fold: the leaf carrying the old digit's top falls forward onto the fold
/// and keeps going past it, and what comes down on the far side is the back of
/// the same leaf — the new digit's bottom. Behind it, the new digit's top half
/// has been on screen since the first frame, and the old digit's bottom half
/// stays until the leaf lands on it.
///
/// ## What was wrong with it
///
/// Two things, and both were invisible in the widget tree — which is why the
/// tests it had all passed.
///
/// The halves were not halves. They sat in a `Stack` under `StackFit.expand`,
/// which hands every non-positioned child TIGHT constraints: the
/// `SizedBox(height: h / 2)` inside each one was overruled, the `Align`'s
/// `heightFactor` had nothing left to shrink-wrap, and both layers painted the
/// WHOLE card. The old digit's face covered the new one completely, so nothing
/// behind the leaf ever changed, and the digit swapped in a single frame at the
/// end when the outgoing face was dropped. The animation was, at the only
/// moment that mattered, a cut.
///
/// And the leaf turned the wrong way. `rotateX` with a positive angle brings
/// the top of a widget TOWARDS the viewer; the fall was written negative, so
/// the flap folded backwards into the card. That was hard to see, because the
/// perspective was 0.0016 on a card 36 points tall — about half a pixel of
/// foreshortening at the extreme, which is no perspective at all, and a
/// rotation with no depth cue is a vertical squash.
///
/// ## What it does now
///
/// The perspective is scaled to the card, so the free edge of the leaf gains
/// about a fifth of its width at the extreme: enough to read as a flap
/// standing out of the display rather than a rectangle getting shorter. It
/// overflows the card while it does, which is why the stack is told not to
/// clip — a thing coming towards you is wider than its housing.
///
/// The run is not split down the middle. The leaf is released and then lands,
/// so the drop takes the longer share on an accelerating curve and the landing
/// is shorter and decelerates into place. Split evenly, with matching curves,
/// it reads as a panel being opened and closed by hand.
///
/// And the light comes from above and in front. The leaf loses it as it turns
/// edge-on and takes it back coming down, its free edge catches a highlight at
/// the extreme, and it throws a shadow onto the half below it. All three peak
/// at a right angle out of the card and are gone when it is flat, because all
/// three are the same quantity — the sine of the turn — which is also why they
/// stay in step with each other.
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
  /// Long enough to be a movement rather than a cut, and over well before the
  /// next second lands on top of it.
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );

  late String _shown = widget.digit;

  /// The digit being flipped away from. Null when the card is at rest, which
  /// is what lets a settled card skip the whole stack and paint one face.
  String? _outgoing;

  static const double _quarter = math.pi / 2;

  /// Where the drop ends and the landing begins, as a fraction of the run.
  ///
  /// Not the half. A flap is released and then arrives: the first ninety
  /// degrees are a fall, which wants the longer share and an accelerating
  /// curve, and the second ninety are the landing, which is quicker and
  /// settles. The two phases also meet at their fastest here, which is what
  /// carries the eye across the fold.
  static const double _foldAt = 0.58;

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((status) {
      if (status != AnimationStatus.completed || !mounted) return;
      // Dropped at the end rather than left set: a settled card is one
      // DecoratedBox again, instead of three layers and a perspective matrix
      // held for as long as the page is open.
      setState(() => _outgoing = null);
    });
  }

  @override
  void didUpdateWidget(FlipDigit old) {
    super.didUpdateWidget(old);
    if (old.digit == widget.digit) return;
    // Mid-flip when the next second lands — which happens whenever a frame is
    // late — the leaf would otherwise carry a digit two steps old. The turn in
    // flight is abandoned and the new one starts from the digit that was
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
    final outgoing = _outgoing;

    if (outgoing == null) {
      return SizedBox(width: w, height: h, child: _face(_shown));
    }

    // Built here rather than inside the builder. These four are the same four
    // widgets for the whole turn, and Flutter skips updating a child whose
    // widget is identical to the mounted one — so the faces are laid out once
    // and repainted, instead of being rebuilt sixty times a second.
    final restingTop = _clipped(_face(_shown), top: true);
    final restingBottom = _clipped(_face(outgoing), top: false);
    final fallingLeaf = _clipped(_face(outgoing), top: true);
    final landingLeaf = _clipped(_face(_shown), top: false);

    return SizedBox(
      width: w,
      height: h,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          final falling = t < _foldAt;
          // One half-turn across the two phases, continuous at the fold: the
          // drop runs 0 to 90 degrees, the landing 90 to 180.
          final turn = falling
              ? _quarter * Curves.easeIn.transform(t / _foldAt)
              : _quarter *
                    (1 +
                        Curves.easeOut.transform(
                          (t - _foldAt) / (1 - _foldAt),
                        ));
          // Square to the card is where the leaf catches the most light and
          // throws the most shadow. Flat either way, it does neither.
          final tilt = math.sin(turn);

          return Stack(
            // A leaf tilted towards the viewer is wider than the card it came
            // out of. Clipping it back to the card is the one thing that would
            // undo the perspective.
            clipBehavior: Clip.none,
            children: [
              Positioned(top: 0, left: 0, right: 0, child: restingTop),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                // The shadow the leaf throws down the card, strongest at the
                // fold and fading out below it.
                child: _shadowed(restingBottom, tilt * 0.45),
              ),
              Positioned(
                top: falling ? 0 : null,
                bottom: falling ? null : 0,
                left: 0,
                right: 0,
                child: Transform(
                  // The hinge is the fold: the lower edge of the falling leaf,
                  // the upper edge of the one landing.
                  alignment: falling
                      ? Alignment.bottomCenter
                      : Alignment.topCenter,
                  transform: Matrix4.identity()
                    // Scaled to the card, not a constant: the free edge should
                    // gain about a fifth of its width at the extreme, and the
                    // card is 36 points tall on a phone and 28 in a row that
                    // has to share its line.
                    ..setEntry(3, 2, 0.33 / h)
                    // Positive brings the top towards the viewer, which is the
                    // direction a flap falls. The landing leaf is the same
                    // sweep continued: a quarter turn past the fold is where
                    // it starts, and flat is where it stops.
                    ..rotateX(falling ? turn : turn - math.pi),
                  child: _leaf(
                    falling ? fallingLeaf : landingLeaf,
                    falling: falling,
                    tilt: tilt,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Half of a face, clipped rather than drawn as its own box.
  ///
  /// Drawing a half independently would give it its own rounded corners at the
  /// fold and its own slice of the gradient, and the two halves would stop
  /// lining up. Clipping keeps the rounding on the outer corners only, drops
  /// the border along the fold, and leaves each half carrying its own side of
  /// the seam.
  ///
  /// It has to be laid out with its height unbounded — in a [Positioned] with
  /// only one edge set, not as a [Stack] child under `StackFit.expand` — or
  /// [Align.heightFactor] has nothing to shrink-wrap and the half is the whole
  /// card. That was the bug.
  Widget _clipped(Widget face, {required bool top}) => ClipRect(
    child: Align(
      alignment: top ? Alignment.topCenter : Alignment.bottomCenter,
      heightFactor: 0.5,
      child: face,
    ),
  );

  /// The leaf in flight: shaded as it turns away from the light, with the
  /// thickness of its free edge catching it.
  Widget _leaf(Widget half, {required bool falling, required double tilt}) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        half,
        if (tilt > 0.01)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black.withValues(alpha: tilt * 0.5),
            ),
          ),
        // The lit edge of the flap, at the end that is furthest from the
        // hinge. One line, at its brightest when the leaf is square to the
        // card and there is nothing else of it left to see.
        if (tilt > 0.05)
          Positioned(
            top: falling ? 0 : null,
            bottom: falling ? null : 0,
            left: 0,
            right: 0,
            child: SizedBox(
              height: 1,
              child: ColoredBox(
                color: Colors.white.withValues(alpha: tilt * 0.45),
              ),
            ),
          ),
      ],
    );
  }

  /// The half below the leaf, with the leaf's shadow on it.
  Widget _shadowed(Widget half, double strength) {
    if (strength < 0.01) return half;
    return Stack(
      children: [
        half,
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: strength),
                  Colors.transparent,
                ],
                stops: const [0, 0.8],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// The whole card. Every layer above is this, clipped differently.
  Widget _face(String digit) {
    final w = FlipDigit.widthFor(widget.compact);
    final h = FlipDigit.heightFor(widget.compact);
    return SizedBox(
      width: w,
      height: h,
      child: DecoratedBox(
        decoration: BoxDecoration(
          // Lighter above the fold, darker below it, which is what a
          // split-flap looks like lit from above.
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.surfaceVariant, AppColors.card],
          ),
          borderRadius: BorderRadius.circular(widget.compact ? 5 : 7),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: Text(
                digit,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: widget.compact ? 15 : 19,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  // A column of digits that does not jitter as the glyphs
                  // change width.
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            // The seam, over the glyph because that is where it is: the fold
            // crosses the digit rather than passing behind it. Each half
            // carries its own side of it, so it stays put while the leaf turns.
            Align(
              child: SizedBox(
                height: 1,
                width: double.infinity,
                child: ColoredBox(color: Colors.black.withValues(alpha: 0.45)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
