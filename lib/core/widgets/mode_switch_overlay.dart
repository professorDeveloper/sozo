import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:soplay/core/content/catalogue.dart';
import 'package:soplay/core/content/content_mode.dart';
import 'package:soplay/core/content/content_mode_style.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/widgets/sozo_signature.dart';
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
/// from there. The glyph column starts small and offset towards that point too,
/// so the mark arrives *from* the press rather than materialising in the
/// middle.
///
/// ## Why each mode opens differently
///
/// One iris for all three destinations made the transition a template: the
/// colour changed and nothing else did. Each mode now has its own way of
/// arriving — Watch opens as an iris, Manga cuts in as a panel on the diagonal
/// its own glyph is built from, Novels opens outwards from the spine like a
/// spread. It costs one [Path] per frame and it is the difference between a
/// transition that was configured and one that was authored.
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
  static const Duration enterDuration = Duration(milliseconds: 280);

  /// The cover lifting off the new content.
  static const Duration exitDuration = Duration(milliseconds: 280);

  /// The mark being signed: outline, then fill, then the badge. Starts once
  /// the cover has most of the screen and runs on into the hold.
  ///
  /// Sized against [minimumBeat] on purpose. The pen must have finished before
  /// the cover starts lifting — a mark caught half-written reads as an
  /// interrupted animation rather than a fast one — and every millisecond
  /// beyond that is a millisecond the user waits on the app's most repeated
  /// action.
  static const Duration signDuration = Duration(milliseconds: 500);

  /// The floor on the whole thing: long enough to read the word and watch the
  /// signature finish, short enough that nobody waits through it twice.
  static const Duration minimumBeat = Duration(milliseconds: 820);

  /// How long the cover will wait for the new mode's first load before lifting
  /// anyway. A reload that takes longer than this is not going to be saved by
  /// covering it for longer; at that point the loading state underneath is the
  /// more honest thing to show.
  static const Duration maxWait = Duration(seconds: 2);

  /// The shape the new screen arrives in, for [mode], at [progress].
  ///
  /// Public because the guarantee it carries is worth asserting rather than
  /// eyeballing: at `progress == 1` every one of the three shapes must contain
  /// all four corners of the screen. A shape that does not leaves a wedge of
  /// the old home showing along one edge for the whole hold, which looks like
  /// a rendering fault and is exactly the kind of thing that survives review.
  static Path revealPath({
    required ContentMode mode,
    required Offset center,
    required double reach,
    required double progress,
  }) {
    final t = progress.clamp(0.0, 1.0);
    final r = reach * t;
    if (r <= 0) return Path();
    switch (mode) {
      // An iris. Watch is where most people already are, so its arrival is
      // the plainest of the three on purpose.
      case ContentMode.video:
        return Path()..addOval(Rect.fromCircle(center: center, radius: r));

      // A panel dropped on the page, cut on the diagonal the manga glyph is
      // built from. A square rotated to any angle still contains the circle
      // of radius r it was built around, so the corner guarantee holds.
      case ContentMode.manga:
        final panel = Path()
          ..addRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset.zero, width: 2 * r, height: 2 * r),
              Radius.circular(math.min(r * 0.06, 18)),
            ),
          );
        return panel.transform(
          (Matrix4.identity()
                ..translateByDouble(center.dx, center.dy, 0, 1)
                ..rotateZ(_panelTilt))
              .storage,
        );

      // A spread opening at the spine. The spine is vertical, so the cover
      // has most of its height from the first frame and the pages travel
      // outwards — a book being opened, rather than a hole being made.
      case ContentMode.novel:
        return Path()
          ..addRect(
            Rect.fromCenter(
              center: center,
              width: 2 * reach * t,
              height: 2 * reach * (0.25 + 0.75 * t),
            ),
          );
    }
  }

  /// The slope a manga panel is cut on — the same one in the manga glyph, so
  /// the cover and the mark it reveals agree.
  static const double _panelTilt = -0.38;

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
    // Started, not awaited: the pen does not begin until ~33ms in, which is
    // more than the parse needs, and a mode switch must not wait on an asset
    // read even once.
    unawaited(SozoSignature.precache());
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

  /// The signature. Its own clock, because it outlasts the reveal: the
  /// cover is in place at 280ms and the pen is still writing at 500.
  late final AnimationController _sign = AnimationController(
    vsync: this,
    duration: ModeSwitchOverlay.signDuration,
  );

  /// The hold. Runs in a loop from the moment the glyph is drawn until the
  /// cover lifts: the glyph breathes and a ring leaves it each cycle, so a
  /// wait on a slow reload is a thing that is alive rather than a thing
  /// that has stopped. On a switch that loads in time this never starts,
  /// which is correct — there is nothing to wait for.
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

  /// The pen. Starts once the cover has most of the screen, so nothing is
  /// drawn where the old screen can still be seen; eased so the outline
  /// is quick and the fill and badge settle.
  late final Animation<double> _draw = CurvedAnimation(
    parent: _sign,
    curve: Curves.easeInOutCubic,
  );
  bool _signing = false;

  /// The mark's own arrival: it comes in from the press with a little
  /// overshoot, so it lands rather than appears. Back-out rather than a
  /// bounce — one overshoot, no wobble.
  late final Animation<double> _land = CurvedAnimation(
    parent: _enter,
    curve: const Interval(0.1, 1, curve: Curves.easeOutBack),
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
    _sign.addStatusListener(_onSigned);
  }

  void _onSigned(AnimationStatus status) {
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
    if (!_signing && _open.value >= 0.34) {
      _signing = true;
      _sign.forward();
    }
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
      _exit.forward();
    }
  }

  @override
  void dispose() {
    widget.release?.removeListener(_onRelease);
    _enter.removeListener(_maybeHaptic);
    _sign.removeStatusListener(_onSigned);
    _enter.dispose();
    _exit.dispose();
    _pulse.dispose();
    _sign.dispose();
    super.dispose();
  }

  /// What the cover says it is taking you to.
  ///
  /// A catalogue's own name is not enough on its own: AniList is three shelves
  /// and all three share a name, a colour and a logo, so "ANILIST" was the
  /// same cover whether you had asked for anime, manga or light novels. The
  /// mode is what tells them apart, so it is in the word.
  String get _label {
    final c = widget.catalogue;
    if (c == null) return widget.mode.labelKey.tr().toUpperCase();
    return '${c.labelKey.tr()} · ${widget.mode.labelKey.tr()}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.catalogue?.accent ?? widget.mode.accent;
    final size = MediaQuery.sizeOf(context);
    final center = widget.origin?.center ?? size.center(Offset.zero);
    // Far enough to cover the corner furthest from where it started, or the
    // reveal leaves a wedge of the old screen showing at one edge.
    final reach = _farthestCorner(center, size);
    // How far the press was from the middle, as a fraction of the screen.
    // Everything on the cover leans this way by a different amount, which is
    // what gives a flat colour field a front and a back.
    final lean = Offset(
      (center.dx - size.width / 2) / size.width,
      (center.dy - size.height / 2) / size.height,
    );

    return AbsorbPointer(
      // Not IgnorePointer: taps used to fall through the cover onto whatever
      // happened to be under it, which the user could not see and had not
      // aimed at.
      child: AnimatedBuilder(
        animation: Listenable.merge([_enter, _exit]),
        builder: (context, child) {
          final cover = Transform.scale(scale: _coverGrow.value, child: child);
          if (_reduceMotion) {
            // The lift is already in the cover's own colours; this is only the
            // arrival, which reduced motion turns from a reveal into a fade.
            return Opacity(opacity: _coverIn.value, child: cover);
          }
          final open = _open.value.clamp(0.0, 1.0);
          return Stack(
            fit: StackFit.expand,
            children: [
              // Once the reveal owns the screen the clip is a full-screen
              // antialiased path being rasterised for nothing, so it is
              // dropped for the whole hold and the entire exit.
              if (open >= 1)
                cover
              else
                ClipPath(
                  clipper: _RevealClipper(
                    center: center,
                    reach: reach,
                    progress: open,
                    mode: widget.mode,
                  ),
                  child: cover,
                ),
              // Above the cover and unclipped: the rings run ahead of the
              // reveal over the old screen, the rim glows at its edge, and
              // the wave at the end crosses the new one.
              IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _RipplePainter(
                      origin: center,
                      reach: reach,
                      // The glyph box sits 16px above the centre of the column
                      // it shares with the label.
                      glyphCenter: size.center(const Offset(0, -16)),
                      accent: accent,
                      open: open,
                      exit: _exit.value,
                      pulse: _pulse,
                    ),
                    willChange: true,
                  ),
                ),
              ),
            ],
          );
        },
        child: AnimatedBuilder(
          animation: Listenable.merge([_enter, _exit]),
          builder: (context, inner) {
            final out = _coverOut.value;
            return Material(
              // The app's own ground, with the mode's colour pooled where the
              // glyph lands. A flat wash of the accent would be a different
              // app for half a second; this is the same app, lit.
              //
              // The exit fades these colours rather than wrapping the screen
              // in an Opacity: an Opacity below 1 buys a full-screen offscreen
              // buffer on every frame of the lift, which is the one moment the
              // new home underneath is also being laid out.
              color: AppColors.background.withValues(alpha: out),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    // The pool leans hardest towards the press: it is the
                    // layer furthest back, so it moves most.
                    center: Alignment(
                      (lean.dx * 1.1).clamp(-0.8, 0.8),
                      (-0.12 + lean.dy * 1.1).clamp(-0.9, 0.9),
                    ),
                    radius: 0.9,
                    colors: [
                      accent.withValues(alpha: 0.22 * out),
                      accent.withValues(alpha: 0.06 * out),
                      Colors.transparent,
                    ],
                    stops: const [0, 0.45, 1],
                  ),
                ),
                child: inner,
              ),
            );
          },
          child: Center(
            // Only the column fades on the way out — a screen-wide Opacity
            // would buy an offscreen buffer the size of the display for every
            // frame of the lift, and the mark is 104px of it.
            child: FadeTransition(
              opacity: _coverOut,
              child: RepaintBoundary(
                child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: 104,
                    child: AnimatedBuilder(
                      animation: Listenable.merge([_draw, _land, _pulse, _exit]),
                      builder: (context, _) {
                        final land = _reduceMotion
                            ? 1.0
                            : _land.value.clamp(0.0, 1.2);
                        // The breath fades out with the lift instead of being
                        // stopped dead: halting the controller snapped the
                        // scale back in a single frame, exactly as the cover
                        // began to leave.
                        final breath = _pulse.isAnimating
                            ? 0.035 *
                                  math.sin(_pulse.value * math.pi) *
                                  (1 - _exit.value * 3).clamp(0.0, 1.0)
                            : 0.0;
                        return Transform.translate(
                          // The mark comes in from the press and settles in
                          // the middle — a sixth of the way there, so it is
                          // felt as direction rather than seen as travel.
                          offset: Offset(
                            -lean.dx * 90 * (1 - land),
                            -lean.dy * 90 * (1 - land),
                          ),
                          child: Transform.scale(
                            scale: (0.62 + 0.38 * land) * (1 + breath),
                            child: Center(
                              child: SozoSignature(
                                mode: widget.mode,
                                catalogue: widget.catalogue,
                                color: accent,
                                size: 92,
                                progress: _reduceMotion ? 1 : _draw.value,
                              ),
                            ),
                          ),
                        );
                      },
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
                            _label,
                            textAlign: TextAlign.center,
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
///
/// Every [Paint] here is built once and mutated in place. They are not shared
/// between painters — one overlay is on screen at a time — and a fresh Paint
/// per ring per frame is six allocations a frame for the length of a switch.
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

  final Paint _stroke = Paint()..style = PaintingStyle.stroke;
  final Paint _soft = Paint()
    ..style = PaintingStyle.stroke
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
  final Paint _wavePaint = Paint()
    ..style = PaintingStyle.stroke
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);

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
      _soft
        ..color = accent.withValues(alpha: 0.45 * (1 - open))
        ..strokeWidth = 18,
    );
  }

  /// Three rings, each released a little after the last, running out past
  /// the edge and thinning as they go.
  void _leadRings(Canvas canvas) {
    for (var i = 0; i < 3; i++) {
      final start = 0.05 * i;
      if (open <= start) continue;
      final t = _ease.transform(((open - start) / (1 - start)).clamp(0.0, 1.0));
      final r = reach * (0.18 + 1.0 * t);
      final alpha = (0.55 - 0.15 * i) * (1 - t);
      if (alpha <= 0.01) continue;
      canvas.drawCircle(
        origin,
        r,
        _stroke
          ..color = accent.withValues(alpha: alpha)
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
      _stroke
        ..color = accent.withValues(alpha: alpha)
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
      _wavePaint
        ..color = accent.withValues(alpha: alpha)
        ..strokeWidth = 3 - 2 * t,
    );
    canvas.drawCircle(
      glyphCenter,
      r * 0.72,
      _stroke
        ..color = accent.withValues(alpha: alpha * 0.5)
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_RipplePainter old) =>
      old.open != open ||
      old.exit != exit ||
      old.origin != origin ||
      old.reach != reach ||
      old.glyphCenter != glyphCenter ||
      old.accent != accent;
}

/// How the new screen arrives, which is different for each mode.
///
/// The shape itself is [ModeSwitchOverlay.revealPath]; this only hands it the
/// frame's numbers. A mode switch is the one moment the app has to say which
/// of three quite different things you are now in, and it has half a second
/// to do it, so all three grow from where the switch was asked for and none
/// of them looks like the others on the way.
class _RevealClipper extends CustomClipper<Path> {
  const _RevealClipper({
    required this.center,
    required this.reach,
    required this.progress,
    required this.mode,
  });

  final Offset center;
  final double reach;
  final double progress;
  final ContentMode mode;

  @override
  Path getClip(Size size) => ModeSwitchOverlay.revealPath(
    mode: mode,
    center: center,
    reach: reach,
    progress: progress,
  );

  @override
  bool shouldReclip(_RevealClipper old) =>
      old.progress != progress ||
      old.center != center ||
      old.reach != reach ||
      old.mode != mode;
}
