// ignore_for_file: invalid_use_of_protected_member
part of 'player_page.dart';

// Android TV / D-pad operation of the player.
//
// Everything in this file is reached only when isTvPlatform is true, which is
// resolved once at startup and is provably false on phones, iOS and desktop —
// so phone and desktop playback take exactly the code path they take today.
//
// The model is deliberately state-dependent rather than "one key, one action":
//
//  * Controls hidden — the D-pad drives PLAYBACK. Left/right step-seek,
//    up/down reveal the controls, OK toggles play. This is what a viewer
//    expects from a remote when nothing is on screen.
//  * Controls visible — the D-pad drives FOCUS. Arrow keys are handed back to
//    Flutter's directional traversal (which also brings Scrollable.ensureVisible
//    with it for free), OK activates the focused control. The one exception is
//    the seek bar, which claims left/right while it holds focus so scrubbing
//    feels like scrubbing.
//
// The root scope (_PlayerPageState._tvRootFocus) is an ancestor of every
// control, so it sees each key BEFORE the app-level traversal shortcut and can
// make that choice per keystroke.

/// Approximate rendered height of one `_EpisodeRow`, used only to pick an
/// opening scroll offset for the episode panel on TV. Rows are laid out by
/// their content (a one- or two-line label), so this is a heuristic, not a
/// measurement — being a row or two off is corrected by the first D-pad press.
const double _kTvEpisodeRowEstimate = 58;

/// Focus highlight for full-width list rows (settings, options, episodes,
/// qualities, chips). A tinted fill reads better across a room than an outline,
/// and rows are wide enough that a ring would dominate the sheet.
///
/// Null off TV, which is exactly what those `InkWell`s pass today — so phone
/// and desktop keep the theme default and render unchanged.
Color? get _kTvFocusFill =>
    isTvPlatform ? AppColors.primary.withValues(alpha: 0.22) : null;

extension _PlayerTv on _PlayerPageState {
  /// Seconds added per left/right press, growing while the key is held so a
  /// two-hour film is still crossable without the step being useless on a
  /// 20-minute episode.
  int get _tvSeekStepSeconds => _tvSeekRepeats >= 8
      ? 60
      : _tvSeekRepeats >= 4
          ? 30
          : 10;

  bool _isTvDirectional(LogicalKeyboardKey k) =>
      k == LogicalKeyboardKey.arrowLeft ||
      k == LogicalKeyboardKey.arrowRight ||
      k == LogicalKeyboardKey.arrowUp ||
      k == LogicalKeyboardKey.arrowDown;

  bool _isTvSelect(LogicalKeyboardKey k) =>
      k == LogicalKeyboardKey.select ||
      k == LogicalKeyboardKey.enter ||
      k == LogicalKeyboardKey.numpadEnter ||
      k == LogicalKeyboardKey.gameButtonA ||
      k == LogicalKeyboardKey.space;

  // --- focus -----------------------------------------------------------------

  /// Reveals the controls (if hidden) and parks focus on a sensible control.
  ///
  /// Focus is only *moved* when the viewer had none to lose — the overlay was
  /// hidden, the root scope holds focus, or the caller [force]s it because the
  /// focused control is being unmounted. Otherwise a transport key pressed
  /// while browsing the bottom row would yank the cursor back to play/pause.
  ///
  /// The request is deferred a frame because the control that should receive
  /// focus may not be mounted yet — it is built by the `setState` this call
  /// schedules.
  void _tvReveal({FocusNode? focus, bool force = false}) {
    final wasHidden = !_controlsVisible;
    if (wasHidden) {
      setState(() => _controlsVisible = true);
      _controlsAnimation.forward();
    }
    if (force || wasHidden || _tvRootFocus.hasPrimaryFocus) {
      final target = focus ?? _tvDefaultFocusNode();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (target.context != null) {
          target.requestFocus();
        } else if (!_tvRootFocus.nextFocus()) {
          // Nothing focusable is on screen yet (still buffering, say). Holding
          // focus at the root keeps key events flowing to _onTvPlayerKey.
          _tvRootFocus.requestFocus();
        }
      });
    }
    _scheduleHide();
  }

  /// Keeps the cursor on the seek bar for the duration of a scrub. Called after
  /// every step so a burst of presses that outruns the deferred focus request
  /// still ends with the bar focused.
  void _tvClaimSeekFocus() {
    if (_tvSeekFocus.hasPrimaryFocus || _tvSeekFocus.context == null) return;
    _tvSeekFocus.requestFocus();
  }

  /// The control focus should land on when the overlay appears: the play/pause
  /// button when it is on screen, otherwise the seek bar.
  FocusNode _tvDefaultFocusNode() =>
      _tvPlayFocus.context != null ? _tvPlayFocus : _tvSeekFocus;

  /// Pulls focus back to the root when the overlay goes away. Without this the
  /// focus would fall to the enclosing route scope, which is *not* an ancestor
  /// of [_tvRootFocus] — key events would stop arriving and the remote would go
  /// dead until the next tap.
  void _tvHandOffFocusToRoot() {
    if (!isTvPlatform) return;
    final current = FocusManager.instance.primaryFocus;
    if (current != null && current != _tvRootFocus) {
      // Disposition.scope hands primary focus to the enclosing scope, which is
      // _tvRootFocus — a plain unfocus() would drop it further out.
      current.unfocus(disposition: UnfocusDisposition.scope);
    }
    if (!_tvRootFocus.hasFocus) _tvRootFocus.requestFocus();
  }

  void _tvHideControls() {
    if (!_controlsVisible) return;
    setState(() => _controlsVisible = false);
    _controlsAnimation.reverse();
    _hideTimer?.cancel();
    _tvHandOffFocusToRoot();
  }

  // --- step seek --------------------------------------------------------------

  /// Moves the *preview* position by one step and arms a commit.
  ///
  /// Reuses [_PlayerPageState._sliderDragValue], the same notifier the touch
  /// slider drives, so the position label and the storyboard thumbnail popup
  /// light up for a remote exactly as they do for a finger — no parallel
  /// preview machinery.
  void _tvStepSeek(int direction) {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _isLive) return;
    if (_partyBlockLocal()) return;
    final durationMs = c.value.duration.inMilliseconds;
    if (durationMs <= 0) return;

    final now = DateTime.now();
    final last = _tvSeekLastStep;
    _tvSeekRepeats =
        last != null && now.difference(last).inMilliseconds < 450
            ? _tvSeekRepeats + 1
            : 0;
    _tvSeekLastStep = now;

    final base = _sliderDragValue.value ??
        c.value.position.inMilliseconds.toDouble();
    _sliderDragValue.value =
        (base + direction * _tvSeekStepSeconds * 1000).clamp(
      0.0,
      durationMs.toDouble(),
    );

    _hideTimer?.cancel();
    _tvSeekCommit?.cancel();
    _tvSeekCommit = Timer(
      const Duration(milliseconds: 650),
      _tvCommitSeek,
    );
  }

  /// Applies a pending step-seek. Safe to call when nothing is pending.
  void _tvCommitSeek() {
    _tvSeekCommit?.cancel();
    _tvSeekCommit = null;
    _tvSeekRepeats = 0;
    _tvSeekLastStep = null;
    final preview = _sliderDragValue.value;
    if (preview == null) {
      _scheduleHide();
      return;
    }
    final target = Duration(milliseconds: preview.toInt());
    _seekTo(target);
    _clearDragAfterSeek(target);
    _scheduleHide();
  }

  // --- BACK -------------------------------------------------------------------

  /// One BACK press unwinds one layer, never more. Mirrors the precedence the
  /// desktop Escape branch already encodes in [_PlayerPageState._onPlayerKey].
  void _onTvBack() {
    if (_locked) {
      setState(() => _locked = false);
      _tvReveal(force: true);
      return;
    }
    if (_panel != _SidePanel.none) {
      // The focused panel row is about to be unmounted, so focus must be moved
      // deliberately rather than left to fall wherever it lands.
      _closePanel();
      _tvReveal(force: true);
      return;
    }
    if (_sliderDragValue.value != null) {
      // Abandon an uncommitted scrub rather than leaving the player.
      _tvSeekCommit?.cancel();
      _tvSeekCommit = null;
      _tvSeekRepeats = 0;
      _sliderDragValue.value = null;
      _scheduleHide();
      return;
    }
    final c = _controller;
    if (_controlsVisible && c != null && c.value.isInitialized) {
      // Only a *playing* overlay is worth a BACK press of its own. While the
      // player is still loading, or sitting on the error view, the overlay is
      // all there is — swallowing BACK there would just feel broken.
      _tvHideControls();
      return;
    }
    _exit();
  }

  // --- keys --------------------------------------------------------------------

  /// Transport keys from the remote. Handled at any time, in any focus state,
  /// because a remote's play button means "play" whatever is on screen.
  bool _handleTvMediaKey(LogicalKeyboardKey k) {
    if (k == LogicalKeyboardKey.mediaPlayPause ||
        k == LogicalKeyboardKey.mediaPlay ||
        k == LogicalKeyboardKey.mediaPause) {
      _togglePlay();
      _tvReveal();
      return true;
    }
    if (k == LogicalKeyboardKey.mediaStop) {
      _controller?.pause();
      _tvReveal();
      return true;
    }
    if (k == LogicalKeyboardKey.mediaFastForward) {
      _seekRelative(const Duration(seconds: 30));
      _showSeekRipple(1);
      _tvReveal();
      return true;
    }
    if (k == LogicalKeyboardKey.mediaRewind) {
      _seekRelative(const Duration(seconds: -30));
      _showSeekRipple(-1);
      _tvReveal();
      return true;
    }
    if (k == LogicalKeyboardKey.mediaTrackNext) {
      if (widget.args.isSerial &&
          _episodeIndex + 1 < _episodes.length) {
        _partyEpisodeNav(_episodeIndex + 1);
      }
      return true;
    }
    if (k == LogicalKeyboardKey.mediaTrackPrevious) {
      if (widget.args.isSerial && _episodeIndex - 1 >= 0) {
        _partyEpisodeNav(_episodeIndex - 1);
      }
      return true;
    }
    return false;
  }

  KeyEventResult _onTvPlayerKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final k = event.logicalKey;

    // Some launchers deliver BACK as a key event rather than a system pop; both
    // routes converge on _onTvBack, and PopScope covers the other one.
    if (k == LogicalKeyboardKey.goBack || k == LogicalKeyboardKey.escape) {
      _onTvBack();
      return KeyEventResult.handled;
    }

    if (_locked) {
      // The lock affordance is not built on TV (see _buildControlsOverlay), so
      // this is only reachable if the state leaks in. Any key unlocks rather
      // than leaving the viewer with an unrecoverable screen.
      setState(() => _locked = false);
      return KeyEventResult.handled;
    }

    // A guest without playback control must not drive playback locally, but the
    // D-pad must still move focus so they can open episodes, subtitles etc.
    final isPlaybackKey = _isTvSelect(k) ||
        k == LogicalKeyboardKey.arrowLeft ||
        k == LogicalKeyboardKey.arrowRight ||
        k == LogicalKeyboardKey.mediaPlayPause;
    if (isPlaybackKey && !_controlsVisible && _partyBlockLocal()) {
      _tvReveal();
      return KeyEventResult.handled;
    }

    if (_handleTvMediaKey(k)) return KeyEventResult.handled;

    // --- controls hidden: the D-pad is a transport control ---------------------
    if (!_controlsVisible) {
      if (k == LogicalKeyboardKey.arrowLeft) {
        _tvReveal(focus: _tvSeekFocus);
        _tvStepSeek(-1);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowRight) {
        _tvReveal(focus: _tvSeekFocus);
        _tvStepSeek(1);
        return KeyEventResult.handled;
      }
      if (_isTvSelect(k)) {
        _togglePlay();
        _tvReveal();
        return KeyEventResult.handled;
      }
      // Every other key — including up/down and the numeric pad — just brings
      // the overlay back, which is the "re-show on any key press" rule.
      _tvReveal();
      return KeyEventResult.handled;
    }

    // --- controls visible: the D-pad moves focus -------------------------------
    _scheduleHide();

    // A pending scrub counts as "on the seek bar" even when the focus request
    // from the reveal has not landed yet — otherwise a fast second press would
    // be read as a focus move and jump the cursor off the bar mid-scrub.
    if (_tvSeekFocus.hasPrimaryFocus || _sliderDragValue.value != null) {
      if (k == LogicalKeyboardKey.arrowLeft) {
        _tvStepSeek(-1);
        _tvClaimSeekFocus();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowRight) {
        _tvStepSeek(1);
        _tvClaimSeekFocus();
        return KeyEventResult.handled;
      }
      if (_isTvSelect(k)) {
        // OK on the bar means "go there now" if a scrub is pending, and
        // play/pause otherwise — so the bar is never a dead landing spot.
        if (_sliderDragValue.value != null) {
          _tvCommitSeek();
        } else {
          _togglePlay();
        }
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.arrowDown) {
        // Leaving the bar commits whatever was previewed, then lets traversal
        // carry the keystroke on.
        if (_sliderDragValue.value != null) _tvCommitSeek();
      }
    }

    // The overlay is up but nothing inside it holds focus (first reveal, or the
    // focused control was just unmounted). Seed focus deterministically rather
    // than asking directional traversal to guess from a full-screen rect.
    if (_tvRootFocus.hasPrimaryFocus && _isTvDirectional(k)) {
      _tvReveal(force: true);
      return KeyEventResult.handled;
    }

    // Hand arrows and OK to Flutter: directional traversal and the focused
    // control's own Activate action already do the right thing.
    return KeyEventResult.ignored;
  }
}

/// D-pad seek bar. Renders the same information as the touch [Slider] it
/// replaces, but is driven entirely by [_PlayerTv._onTvPlayerKey] — the Material
/// slider binds all four arrow keys itself, which would trap focus on the bar
/// and step by a tenth of the runtime per press.
class _TvSeekBar extends StatefulWidget {
  const _TvSeekBar({
    required this.focusNode,
    required this.positionMs,
    required this.durationMs,
    required this.scrubbing,
  });

  final FocusNode focusNode;
  final double positionMs;
  final double durationMs;

  /// True while a step-seek is pending, i.e. the thumb shows a target rather
  /// than the live position.
  final bool scrubbing;

  @override
  State<_TvSeekBar> createState() => _TvSeekBarState();
}

class _TvSeekBarState extends State<_TvSeekBar> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final fraction = widget.durationMs <= 0
        ? 0.0
        : (widget.positionMs / widget.durationMs).clamp(0.0, 1.0);
    final active = _focused || widget.scrubbing;
    final trackHeight = active ? 5.0 : 3.0;
    final thumbSize = active ? 16.0 : 11.0;

    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (v) {
        if (v != _focused) setState(() => _focused = v);
      },
      child: Padding(
        // Matches the 24px the Material Slider reserves for its overlay, so the
        // scrub-preview thumbnail popup — positioned by geometry computed in
        // _buildBottomBar — still lines up with the thumb.
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: SizedBox(
          height: thumbSize,
          child: LayoutBuilder(
            builder: (context, box) {
              final width = box.maxWidth;
              return Stack(
                alignment: AlignmentDirectional.centerStart,
                clipBehavior: Clip.none,
                children: [
                  Container(
                    height: trackHeight,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: fraction,
                    child: Container(
                      height: trackHeight,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  Positioned(
                    left: (fraction * width - thumbSize / 2).clamp(
                      0.0,
                      (width - thumbSize).clamp(0.0, double.infinity),
                    ),
                    child: Container(
                      width: thumbSize,
                      height: thumbSize,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: active
                            ? Border.all(color: AppColors.primary, width: 2.5)
                            : null,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// D-pad replacement for a Material [Slider] inside a sheet.
///
/// A focused Material slider binds *all four* arrow keys to value adjustment,
/// so on a remote it swallows up/down and focus can never leave it — the viewer
/// is stuck on the control until they press BACK and lose the whole sheet. Two
/// buttons and a readout give the same control with no trap.
class _TvStepper extends StatelessWidget {
  const _TvStepper({
    required this.display,
    required this.onDecrease,
    required this.onIncrease,
  });

  final String display;

  /// Null at the end of the range; the button stays focusable so traversal
  /// still passes through it, it just does nothing.
  final VoidCallback? onDecrease;
  final VoidCallback? onIncrease;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _IconButton(
          icon: Icons.remove_rounded,
          onTap: onDecrease ?? () {},
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            display,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        _IconButton(
          icon: Icons.add_rounded,
          onTap: onIncrease ?? () {},
        ),
      ],
    );
  }
}

/// Paints a brand-accent ring over whichever control currently holds D-pad
/// focus. Built only on TV; on phone and desktop the wrapped widget is returned
/// untouched, so nothing about their rendering changes.
///
/// The node is [Focus.canRequestFocus] `false` and skipped by traversal — it is
/// an observer of its descendants, not a focus target of its own.
class _TvFocusRing extends StatefulWidget {
  const _TvFocusRing({
    required this.child,
    this.circle = false,
    this.radius = 8,
  });

  final Widget child;
  final bool circle;
  final double radius;

  @override
  State<_TvFocusRing> createState() => _TvFocusRingState();
}

class _TvFocusRingState extends State<_TvFocusRing> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (v) {
        if (v != _focused) setState(() => _focused = v);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        // foregroundDecoration paints over the child instead of insetting it,
        // so focus never nudges the layout.
        foregroundDecoration: BoxDecoration(
          shape: widget.circle ? BoxShape.circle : BoxShape.rectangle,
          borderRadius:
              widget.circle ? null : BorderRadius.circular(widget.radius),
          border: Border.all(
            color: _focused ? AppColors.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: widget.child,
      ),
    );
  }
}

/// Wraps [child] in a focus ring on TV and returns it verbatim everywhere else.
Widget _tvRing(Widget child, {bool circle = false, double radius = 8}) {
  if (!isTvPlatform) return child;
  return _TvFocusRing(circle: circle, radius: radius, child: child);
}
