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
        // Seconds are dropped when the wait is measured in days: a digit
        // flipping sixty times a minute next to a number that moves once a day
        // is noise, and it keeps a phone's screen busy for nothing.
        if (days == 0) ...[
          _Separator(compact: widget.compact),
          _Group(
            value: seconds,
            label: 'detail.cd_seconds'.tr(),
            compact: widget.compact,
          ),
        ],
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
/// The turn is the real thing rather than a cross-fade: the card rotates away
/// carrying the old digit and back carrying the new one, about its own centre,
/// with a perspective so the far edge narrows. A fade would read as a glitch at
/// this size; the rotation reads as a mechanism.
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
    duration: const Duration(milliseconds: 320),
  );

  late String _shown = widget.digit;
  String? _outgoing;

  @override
  void didUpdateWidget(FlipDigit old) {
    super.didUpdateWidget(old);
    if (old.digit == widget.digit) return;
    _outgoing = old.digit;
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
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final outgoing = _outgoing;
        if (t == 0 || t == 1 || outgoing == null) return _card(_shown, 0);
        // Halfway is edge-on, which is where the digit is swapped. Before it,
        // the card carries the old one; after, the new.
        return t < 0.5
            ? _card(outgoing, -math.pi * t)
            : _card(_shown, math.pi * (1 - t));
      },
    );
  }

  Widget _card(String digit, double angle) {
    final w = FlipDigit.widthFor(widget.compact);
    final h = FlipDigit.heightFor(widget.compact);
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        // The far edge narrows. Without it the card scales rather than turns,
        // which is what makes a flip look like a squash.
        ..setEntry(3, 2, 0.0015)
        ..rotateX(angle),
      child: Container(
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
            // The hinge line, at the fold.
            Align(
              alignment: Alignment.center,
              child: Container(
                height: 1,
                color: Colors.black.withValues(alpha: 0.35),
              ),
            ),
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
          ],
        ),
      ),
    );
  }
}
