import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/content/content_mode.dart';
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
/// ## Why the mark and not a spinner
///
/// A spinner says "wait". This says "you switched, and here is what to" — the
/// name of the mode is the payload, the mark is what makes it Sozo's rather
/// than a generic loading screen. It is also the one moment in the app where
/// showing the logo is not decoration: something has to fill the gap, and the
/// alternative is a blank screen.
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
  const ModeSwitchOverlay({super.key, required this.mode, this.release});

  final ContentMode mode;

  /// Flipped to true by [play] when the cover should lift. Null keeps the
  /// cover up indefinitely, which only a test does.
  final ValueListenable<bool>? release;

  /// The cover arriving, and the mark landing under it.
  static const Duration enterDuration = Duration(milliseconds: 220);

  /// The shortest time the cover stays once it has arrived. Below this the eye
  /// catches a flash and reads it as a glitch rather than a transition.
  static const Duration holdDuration = Duration(milliseconds: 140);

  /// The cover lifting off the new content.
  static const Duration exitDuration = Duration(milliseconds: 240);

  /// The floor on the whole thing: 600ms, long enough to read the word, short
  /// enough that nobody waits through it twice.
  static const Duration minimumBeat = Duration(milliseconds: 600);

  /// How long the cover will wait for the new mode's first load before lifting
  /// anyway. A reload that takes longer than this is not going to be saved by
  /// covering it for longer; at that point the loading state underneath is the
  /// more honest thing to show.
  static const Duration maxWait = Duration(seconds: 2);

  /// Plays the overlay over whatever is on screen and returns when it is gone.
  ///
  /// [until] is the work the cover exists to hide — the new mode's first load.
  /// The cover holds for [minimumBeat] and then for as long as that takes, up
  /// to [maxWait]. Without it the animation ran for a fixed 620ms and, on a
  /// slow source, lifted onto a screen that was still empty: the switch looked
  /// like it had failed and the content arrived a second later as if unrelated.
  ///
  /// Pass nothing when there is no reload to wait for — the cover then just
  /// plays its beat.
  static Future<void> play(
    BuildContext context,
    ContentMode mode, {
    Future<void>? until,
  }) async {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final release = ValueNotifier<bool>(false);
    final entry = OverlayEntry(
      builder: (_) => ModeSwitchOverlay(mode: mode, release: release),
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

  /// The cover arrives ahead of the mark, so the old screen is gone before
  /// anything is asked of the eye.
  late final Animation<double> _coverIn = CurvedAnimation(
    parent: _enter,
    curve: const Interval(0, 0.6, curve: Curves.easeOutCubic),
  );

  late final Animation<double> _coverOut = Tween<double>(
    begin: 1,
    end: 0,
  ).animate(CurvedAnimation(parent: _exit, curve: Curves.easeInCubic));

  /// The mark settles rather than bouncing: it arrives slightly large and
  /// eases down, which reads as landing.
  late final Animation<double> _markIn = Tween<double>(
    begin: 1.16,
    end: 1,
  ).animate(CurvedAnimation(parent: _enter, curve: Curves.easeOutCubic));

  /// …and on the way out it drifts open rather than blinking off, so the lift
  /// reads as the cover receding from the new content rather than a cut.
  late final Animation<double> _markOut = Tween<double>(
    begin: 1,
    end: 1.07,
  ).animate(CurvedAnimation(parent: _exit, curve: Curves.easeIn));

  /// Fades in behind the mark, so the eye lands on the shape first and reads
  /// the word second.
  late final Animation<double> _labelIn = CurvedAnimation(
    parent: _enter,
    curve: const Interval(0.4, 1, curve: Curves.easeOut),
  );

  late final Animation<Offset> _labelRise = Tween<Offset>(
    begin: const Offset(0, 0.5),
    end: Offset.zero,
  ).animate(_labelIn);

  @override
  void initState() {
    super.initState();
    widget.release?.addListener(_onRelease);
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
    if (widget.release?.value ?? false) _exit.forward();
  }

  @override
  void dispose() {
    widget.release?.removeListener(_onRelease);
    _enter.dispose();
    _exit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AbsorbPointer(
      // Not IgnorePointer: taps used to fall through the cover onto whatever
      // happened to be under it, which the user could not see and had not
      // aimed at.
      child: FadeTransition(
        opacity: _coverIn,
        // Nested rather than combined into one value: the two never overlap —
        // the exit cannot start before the enter has finished — so whichever
        // is idle sits at 1.0, where RenderAnimatedOpacity paints straight
        // through without a layer.
        child: FadeTransition(
          opacity: _coverOut,
          child: Material(
            color: AppColors.background,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ScaleTransition(
                    scale: _markIn,
                    child: ScaleTransition(
                      scale: _markOut,
                      child: SozoMark(size: 76, color: AppColors.primary),
                    ),
                  ),
                  const SizedBox(height: 18),
                  FadeTransition(
                    opacity: _labelIn,
                    child: SlideTransition(
                      position: _labelRise,
                      child: Padding(
                        // Letter spacing is added after the last letter too,
                        // so a tracked-out word sits half a space left of
                        // centre under a mark that is exactly centred.
                        padding: const EdgeInsetsDirectional.only(start: 3.2),
                        child: Text(
                          widget.mode.labelKey.tr().toUpperCase(),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 3.2,
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
}
