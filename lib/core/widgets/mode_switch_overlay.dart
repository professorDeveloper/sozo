import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:soplay/core/content/catalogue.dart';
import 'package:soplay/core/content/content_mode.dart';
import 'package:soplay/core/content/content_mode_style.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/widgets/sozo_mark.dart';
import 'package:easy_localization/easy_localization.dart';

/// The beat between one mode and the next.
///
/// ## Why cover the screen at all
///
/// Switching mode replaces every rail on the home screen at once — different
/// sources, different catalogue, different everything. Doing that in place
/// looks like the app broke: the content someone was reading vanishes and
/// something unrelated appears in its slot, with no signal that they caused it.
///
/// A brief cover turns that into a transition. It also hides the reload, which
/// is the honest reason the timing works out: the new mode's first request is
/// in flight underneath.
///
/// ## Why it grows from the chip
///
/// The first version filled the screen from nowhere, in the app's own
/// background colour, and read as a flash rather than a move — nothing tied
/// what appeared to the thing that had just been pressed. It opens from the
/// chip now, so the cause is visible: you touched there, and the screen opened
/// from there.
///
/// ## Why the mark hands off to a glyph
///
/// A spinner says "wait". The mark says "Sozo", which the viewer already knows.
/// The mode's glyph says which way they went, and it is *drawn* rather than
/// faded in — a single pen along every stroke. That is the difference between
/// an image appearing and something making it.
///
/// ## Why it is wrapped in a [Material]
///
/// This is inserted straight into the root [Overlay], where the nearest
/// ancestor text style is the one `MaterialApp` installs for text that has
/// escaped a `Material`: 48px red monospace with a **double yellow underline**.
/// The label sets a colour and a size, and a merge keeps everything it is not
/// told to replace — so the underline came through and the switch animation
/// drew a yellow line under the mode name. A `Material` replaces that default
/// with the theme's own, which is what every other screen in the app gets.
class ModeSwitchOverlay extends StatefulWidget {
  const ModeSwitchOverlay({
    super.key,
    required this.mode,
    this.release,
    this.origin,
    this.catalogue,
  });

  final ContentMode mode;

  /// Set when the switch is to a catalogue rather than to a mode. Same beat,
  /// the catalogue's colour and sign: it replaces the whole home just as a
  /// mode does, and a change that big with no transition looks like a hang.
  final Catalogue? catalogue;

  /// Where on screen the switch was asked for, in global coordinates — the
  /// chip that was pressed. Null opens from the middle, which is what a switch
  /// with no visible cause (a deep link, a restored session) should look like.
  final Rect? origin;

  /// Flipped to true by [play] when the cover should lift. Null keeps the
  /// cover up indefinitely, which only a test does.
  final ValueListenable<bool>? release;

  /// The cover arriving, and the glyph being drawn under it.
  static const Duration enterDuration = Duration(milliseconds: 260);

  /// The shortest time the cover stays once it has arrived. Below this the eye
  /// catches a flash and reads it as a glitch rather than a transition.
  static const Duration holdDuration = Duration(milliseconds: 140);

  /// The cover lifting off the new content.
  static const Duration exitDuration = Duration(milliseconds: 260);

  /// The floor on the whole thing: long enough to read the word and watch the
  /// glyph finish, short enough that nobody waits through it twice.
  static const Duration minimumBeat = Duration(milliseconds: 660);

  /// How long the cover will wait for the new mode's first load before lifting
  /// anyway. A reload that takes longer than this is not going to be saved by
  /// covering it for longer; at that point the loading state underneath is the
  /// more honest thing to show.
  static const Duration maxWait = Duration(seconds: 2);

  /// Plays the overlay over whatever is on screen and returns when it is gone.
  static Future<void> play(
    BuildContext context,
    ContentMode mode, {
    Future<void>? until,
    Rect? origin,
    Catalogue? catalogue,
  }) async {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final release = ValueNotifier<bool>(false);
    final entry = OverlayEntry(
      builder: (_) => ModeSwitchOverlay(
        mode: mode,
        release: release,
        origin: origin,
        catalogue: catalogue,
      ),
    );
    overlay.insert(entry);
    try {
      await Future.wait<void>([
        Future<void>.delayed(minimumBeat - exitDuration),
        if (until != null)
          // Neither a timeout nor a failed load is worth throwing over: the
          // cover's job is to come off either way.
          until.timeout(maxWait, onTimeout: () {}).catchError((Object _) {}),
      ]);
      release.value = true;
      await Future<void>.delayed(exitDuration);
    } finally {
      // In a finally so an interrupted switch can never strand the cover over
      // the app — it absorbs input, so a stuck one is a frozen app.
      entry.remove();
      release.dispose();
    }
  }

  @override
  State<ModeSwitchOverlay> createState() => _ModeSwitchOverlayState();
}

class _ModeSwitchOverlayState extends State<ModeSwitchOverlay>
    with TickerProviderStateMixin {
  /// Two controllers rather than one timeline, because the hold between them
  /// is open-ended: it lasts as long as the reload does.
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: ModeSwitchOverlay.enterDuration,
  )..forward();

  late final AnimationController _exit = AnimationController(
    vsync: this,
    duration: ModeSwitchOverlay.exitDuration,
  );

  /// The hold. Runs in a loop from the moment the glyph is drawn until the
  /// cover lifts: the glyph breathes and a ring leaves it each cycle, so a
  /// wait on a slow reload is a thing that is alive rather than a thing
  /// that has stopped.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  /// The reveal. Fast out of the gate and settling at the edge, so it reads as
  /// something released rather than something driven.
  late final Animation<double> _open = CurvedAnimation(
    parent: _enter,
    curve: Curves.easeOutCubic,
  );

  /// Used only when the viewer has asked for less motion — then there is no
  /// reveal and the cover simply arrives.
  late final Animation<double> _coverIn = CurvedAnimation(
    parent: _enter,
    curve: const Interval(0, 0.6, curve: Curves.easeOutCubic),
  );

  late final Animation<double> _coverOut = Tween<double>(
    begin: 1,
    end: 0,
  ).animate(CurvedAnimation(parent: _exit, curve: Curves.easeInCubic));

  /// The cover widens as it leaves, so the lift reads as it receding from the
  /// new screen rather than blinking off it.
  late final Animation<double> _coverGrow = Tween<double>(
    begin: 1,
    end: 1.06,
  ).animate(CurvedAnimation(parent: _exit, curve: Curves.easeIn));

  /// The mark is what is already there; it steps back as the glyph is drawn.
  late final Animation<double> _markOut = CurvedAnimation(
    parent: _enter,
    curve: const Interval(0.22, 0.58, curve: Curves.easeIn),
  );

  /// The pen. Starts once the cover has most of the screen, so nothing is
  /// drawn where the old screen can still be seen.
  late final Animation<double> _draw = CurvedAnimation(
    parent: _enter,
    curve: const Interval(0.34, 1, curve: Curves.easeOutCubic),
  );

  /// Fades in behind the glyph, so the eye lands on the shape first and reads
  /// the word second.
  late final Animation<double> _labelIn = CurvedAnimation(
    parent: _enter,
    curve: const Interval(0.45, 1, curve: Curves.easeOut),
  );

  late final Animation<Offset> _labelRise = Tween<Offset>(
    begin: const Offset(0, 0.5),
    end: Offset.zero,
  ).animate(_labelIn);

  /// Tracking settles as the word lands: it arrives spread out and closes up,
  /// which reads as the name being set rather than typed.
  late final Animation<double> _labelTrack = Tween<double>(
    begin: 6.4,
    end: 3.2,
  ).animate(_labelIn);

  bool _reduceMotion = false;
  bool _tapped = false;

  @override
  void initState() {
    super.initState();
    widget.release?.addListener(_onRelease);
    _enter.addListener(_maybeHaptic);
    _enter.addStatusListener(_onEntered);
  }

  void _onEntered(AnimationStatus status) {
    // Only while there is a release to wait for: a cover with none is a
    // still frame, and a still frame should not tick.
    final waiting = widget.release != null && !(widget.release!.value);
    if (status == AnimationStatus.completed && !_reduceMotion && waiting) {
      _pulse.repeat();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  }

  /// One light tap at the moment the cover owns the screen.
  ///
  /// Not at the start: a tap that lands with the finger still down is felt as
  /// part of the press, not as a consequence of it.
  void _maybeHaptic() {
    if (_tapped || _reduceMotion || _open.value < 0.82) return;
    _tapped = true;
    HapticFeedback.lightImpact();
  }

  @override
  void didUpdateWidget(ModeSwitchOverlay old) {
    super.didUpdateWidget(old);
    if (old.release != widget.release) {
      old.release?.removeListener(_onRelease);
      widget.release?.addListener(_onRelease);
    }
  }

  void _onRelease() {
    if (widget.release?.value ?? false) {
      _pulse.stop();
      _exit.forward();
    }
  }

  @override
  void dispose() {
    widget.release?.removeListener(_onRelease);
    _enter.removeListener(_maybeHaptic);
    _enter.removeStatusListener(_onEntered);
    _enter.dispose();
    _exit.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.catalogue?.accent ?? widget.mode.accent;
    final size = MediaQuery.sizeOf(context);
    final center = widget.origin?.center ?? size.center(Offset.zero);
    // Far enough to cover the corner furthest from where it started, or the
    // reveal leaves a wedge of the old screen showing at one edge.
    final reach = _farthestCorner(center, size);

    return AbsorbPointer(
      // Not IgnorePointer: taps used to fall through the cover onto whatever
      // happened to be under it, which the user could not see and had not
      // aimed at.
      child: AnimatedBuilder(
        animation: Listenable.merge([_enter, _exit]),
        builder: (context, child) {
          final cover = Opacity(
            opacity: _coverOut.value,
            child: Transform.scale(scale: _coverGrow.value, child: child),
          );
          if (_reduceMotion) {
            return Opacity(opacity: _coverIn.value, child: cover);
          }
          return Stack(
            fit: StackFit.expand,
            children: [
              ClipPath(
                clipper: _RevealClipper(
                  center: center,
                  radius: reach * _open.value,
                ),
                child: cover,
              ),
              // Above the cover and unclipped: the rings run ahead of the
              // reveal over the old screen, the rim glows at its edge, and
              // the wave at the end crosses the new one.
              IgnorePointer(
                child: CustomPaint(
                  painter: _RipplePainter(
                    origin: center,
                    reach: reach,
                    // The glyph box sits 16px above the centre of the column it
                    // shares with the label.
                    glyphCenter: size.center(const Offset(0, -16)),
                    accent: accent,
                    open: _open.value,
                    exit: _exit.value,
                    pulse: _pulse,
                  ),
                  isComplex: true,
                  willChange: true,
                ),
              ),
            ],
          );
        },
        child: Material(
          // The app's own ground, with the mode's colour pooled where the
          // glyph lands. A flat wash of the accent would be a different app
          // for half a second; this is the same app, lit.
          color: AppColors.background,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.12),
                radius: 0.9,
                colors: [
                  accent.withValues(alpha: 0.22),
                  accent.withValues(alpha: 0.06),
                  Colors.transparent,
                ],
                stops: const [0, 0.45, 1],
              ),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: 88,
                    child: AnimatedBuilder(
                      animation: Listenable.merge([_enter, _pulse]),
                      builder: (context, _) => Transform.scale(
                        // A breath: in over the first half of the cycle,
                        // out over the second. Small enough to be felt
                        // rather than seen.
                        scale:
                            1 +
                            0.035 *
                                math.sin(_pulse.value * math.pi) *
                                (_pulse.isAnimating ? 1 : 0),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Opacity(
                              opacity: 1 - _markOut.value,
                              child: Transform.scale(
                                scale: 1 - (_markOut.value * 0.28),
                                child: SozoMark(size: 72, color: accent),
                              ),
                            ),
                            ModeGlyph(
                              mode: widget.mode,
                              catalogue: widget.catalogue,
                              color: accent,
                              size: 76,
                              progress: _reduceMotion ? 1 : _draw.value,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  FadeTransition(
                    opacity: _labelIn,
                    child: SlideTransition(
                      position: _labelRise,
                      child: AnimatedBuilder(
                        animation: _labelTrack,
                        builder: (context, _) => Padding(
                          // Letter spacing is added after the last letter too,
                          // so a tracked-out word sits half a space left of
                          // centre under a mark that is exactly centred.
                          padding: EdgeInsetsDirectional.only(
                            start: _labelTrack.value,
                          ),
                          child: Text(
                            (widget.catalogue?.labelKey ?? widget.mode.labelKey)
                                .tr()
                                .toUpperCase(),
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: _labelTrack.value,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static double _farthestCorner(Offset from, Size size) {
    double d(double x, double y) => (Offset(x, y) - from).distance;
    return math.max(
      math.max(d(0, 0), d(size.width, 0)),
      math.max(d(0, size.height), d(size.width, size.height)),
    );
  }
}

/// The water in the switch: what leaves the tap and what leaves the glyph.
///
/// Three things, all rings in the mode's colour. As the cover opens, rings
/// run ahead of its edge over the old screen, so the reveal reads as a drop
/// landing rather than a hole growing; the edge itself carries a soft rim so
/// it is lit rather than cut. While the cover holds, a ring leaves the glyph
/// each breath. And as the cover lifts, one last wave crosses the new screen
/// from where the glyph was.
class _RipplePainter extends CustomPainter {
  _RipplePainter({
    required this.origin,
    required this.reach,
    required this.glyphCenter,
    required this.accent,
    required this.open,
    required this.exit,
    required this.pulse,
  }) : super(repaint: pulse);

  final Offset origin;
  final double reach;
  final Offset glyphCenter;
  final Color accent;
  final double open;
  final double exit;
  final Animation<double> pulse;

  static const Curve _ease = Curves.easeOutCubic;

  @override
  void paint(Canvas canvas, Size size) {
    if (open < 1) {
      _rim(canvas);
      _leadRings(canvas);
    }
    if (open >= 1 && exit == 0 && pulse.isAnimating) _pulseRing(canvas);
    if (exit > 0) _wave(canvas);
  }

  /// A soft band on the reveal's edge.
  void _rim(Canvas canvas) {
    final r = reach * open;
    if (r <= 0) return;
    canvas.drawCircle(
      origin,
      r,
      Paint()
        ..color = accent.withValues(alpha: 0.45 * (1 - open))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 18
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
  }

  /// Three rings, each released a little after the last, running out past
  /// the edge and thinning as they go.
  void _leadRings(Canvas canvas) {
    for (var i = 0; i < 3; i++) {
      final start = 0.05 * i;
      if (open <= start) continue;
      final t = _ease.transform(((open - start) / (1 - start)).clamp(0, 1));
      final r = reach * (0.18 + 1.0 * t);
      final alpha = (0.55 - 0.15 * i) * (1 - t);
      if (alpha <= 0.01) continue;
      canvas.drawCircle(
        origin,
        r,
        Paint()
          ..color = accent.withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 - 1.5 * t,
      );
    }
  }

  /// One ring per breath, leaving the glyph and fading before the next.
  void _pulseRing(Canvas canvas) {
    final t = _ease.transform(pulse.value);
    final r = 44 + 140 * t;
    final alpha = 0.35 * (1 - t);
    canvas.drawCircle(
      glyphCenter,
      r,
      Paint()
        ..color = accent.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 - 1.2 * t,
    );
  }

  /// The last wave: from the glyph out to the corners as the cover lifts.
  void _wave(Canvas canvas) {
    final t = _ease.transform(exit);
    final r = 44 + reach * t;
    final alpha = 0.5 * (1 - t);
    canvas.drawCircle(
      glyphCenter,
      r,
      Paint()
        ..color = accent.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 - 2 * t
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
    );
    canvas.drawCircle(
      glyphCenter,
      r * 0.72,
      Paint()
        ..color = accent.withValues(alpha: alpha * 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_RipplePainter old) =>
      old.open != open ||
      old.exit != exit ||
      old.origin != origin ||
      old.accent != accent;
}

/// A circle that opens from where the switch was asked for.
class _RevealClipper extends CustomClipper<Path> {
  const _RevealClipper({required this.center, required this.radius});

  final Offset center;
  final double radius;

  @override
  Path getClip(Size size) =>
      Path()..addOval(Rect.fromCircle(center: center, radius: radius));

  @override
  bool shouldReclip(_RevealClipper old) =>
      old.radius != radius || old.center != center;
}
