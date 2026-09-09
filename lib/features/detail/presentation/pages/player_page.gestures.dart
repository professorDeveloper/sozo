// ignore_for_file: invalid_use_of_protected_member
part of 'player_page.dart';

extension _PlayerGestures on _PlayerPageState {
  void _onDoubleTapDown(TapDownDetails details, BoxConstraints constraints) {
    final dx = details.localPosition.dx;
    final width = constraints.maxWidth;
    final leftEdge = width * 0.3;
    final rightEdge = width * 0.7;
    final step = _seekStep;
    if (dx < leftEdge) {
      _seekRelative(-step);
      _showSeekRipple(-1);
    } else if (dx > rightEdge) {
      _seekRelative(step);
      _showSeekRipple(1);
    }
  }

  void _onHDragStart(DragStartDetails _) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    _hideTimer?.cancel();
    if (!_controlsVisible) {
      // setState, not a bare assignment. The overlay is painted by a
      // FadeTransition, which rebuilds only itself, while `_controlsVisible` is
      // also read by the `IgnorePointer` inside _buildControlsOverlay. Flipping
      // the flag without a rebuild faded the controls in over the video and
      // left every one of them inert: play/pause, the seek bar, every button.
      // Measured — a swipe then a tap on the play button gave opacity=1.0 with
      // zero taps delivered. And since _scheduleHide only fires while the video
      // is PLAYING, pausing in that state left the dead overlay up for good.
      setState(() => _controlsVisible = true);
      _controlsAnimation.forward();
    }
    _scrub.value = _ScrubState(
      baseline: c.value.position,
      duration: c.value.duration,
      deltaPx: 0,
      span: 1,
    );
  }

  void _onHDragUpdate(DragUpdateDetails details, BoxConstraints constraints) {
    final state = _scrub.value;
    if (state == null) return;
    _scrub.value = state.copyWith(
      deltaPx: state.deltaPx + details.delta.dx,
      span: constraints.maxWidth,
    );
  }

  void _onHDragEnd(DragEndDetails _) {
    final state = _scrub.value;
    final c = _controller;
    _scrub.value = null;
    if (state == null || c == null || !c.value.isInitialized) {
      _scheduleHide();
      return;
    }
    final target = state.previewPosition(_scrubSecondsPerFullSwipe);
    // Route through _seekTo so the swipe-scrub honours the party control gate
    // and broadcasts the seek, like every other seek surface.
    _seekTo(target);
    _scheduleHide();
  }

  void _onHDragCancel() {
    _scrub.value = null;
    _scheduleHide();
  }

  void _onLongPressStart(LongPressStartDetails _) {
    if (_controlsVisible) return;
    final c = _controller;
    if (c == null || !c.value.isInitialized || !c.value.isPlaying) return;
    // A guest without control must not boost; and when we do boost, share the
    // rate so peers speed up together instead of the host's heartbeat leaking a
    // 2x-advanced position that jerks guests forward.
    if (_partyBlockLocal()) return;
    _speedBeforeBoost = _playbackSpeed;
    _speedBoost.value = true;
    c.setPlaybackSpeed(_longPressBoost);
    _partyEmit('rate', rate: _longPressBoost);
  }

  void _onLongPressEnd(LongPressEndDetails _) {
    if (!_speedBoost.value) return;
    _speedBoost.value = false;
    final c = _controller;
    final restore = _speedBeforeBoost ?? 1.0;
    _speedBeforeBoost = null;
    if (c != null && c.value.isInitialized) {
      c.setPlaybackSpeed(restore);
    }
    _partyEmit('rate', rate: restore);
  }

  void _showSeekRipple(int direction) {
    if (_seekRippleDirection != direction) {
      _seekRippleSeconds = _seekSeconds;
    } else {
      _seekRippleSeconds += _seekSeconds;
    }
    setState(() => _seekRippleDirection = direction);
    _seekRippleController.forward(from: 0);
    _seekRippleTimer?.cancel();
    _seekRippleTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      setState(() {
        _seekRippleDirection = 0;
        _seekRippleSeconds = 0;
      });
    });
  }

  // ── scale: the one recogniser that covers both hands ──────────────────────
  //
  // Flutter refuses a pan recogniser and a scale recogniser on the same
  // detector — scale is a superset of pan, and having both asserts. So the
  // player now registers only onScale*, and one finger is routed straight back
  // into the pan logic below, unchanged. ScaleUpdateDetails carries everything
  // DragUpdateDetails did: focalPointDelta is delta, localFocalPoint is
  // localPosition.
  //
  // pointerCount is checked on every update rather than once at the start,
  // because a second finger often lands a frame or two after the first.

  void _onScaleStart(ScaleStartDetails d, BoxConstraints constraints) {
    _zoomAtPinchStart = _videoZoom;
    _onPanStart(
      DragStartDetails(
        globalPosition: d.focalPoint,
        localPosition: d.localFocalPoint,
      ),
      constraints,
    );
  }

  void _onScaleUpdate(ScaleUpdateDetails d, BoxConstraints constraints) {
    if (d.pointerCount >= 2) {
      // A pinch cancels whatever the single-finger path had begun, so a
      // brightness slide does not keep running under the zoom.
      if (_dragStart != null) _onPanCancel();
      final next =
          (_zoomAtPinchStart * d.scale).clamp(_kMinZoom, _kMaxZoom).toDouble();
      if (next != _videoZoom) {
        setState(() => _videoZoom = next);
        _swipeIndicator.value = _SwipeIndicator(_SwipeType.zoom, next);
      }
      return;
    }
    _onPanUpdate(
      DragUpdateDetails(
        globalPosition: d.focalPoint,
        localPosition: d.localFocalPoint,
        delta: d.focalPointDelta,
      ),
      constraints,
    );
  }

  void _onScaleEnd(ScaleEndDetails d) {
    if (d.pointerCount >= 1 || _dragStart == null) {
      // Fingers lifting out of a pinch, or a pinch that never became a drag.
      _hideZoomBadgeSoon();
      _dragStart = null;
      _dragIsHorizontal = null;
      _dragSwipeType = null;
      return;
    }
    _onPanEnd(DragEndDetails(velocity: d.velocity));
  }

  /// Clears the zoom badge a moment after the fingers leave, the same way the
  /// brightness and volume badges clear.
  void _hideZoomBadgeSoon() {
    if (_swipeIndicator.value?.type != _SwipeType.zoom) return;
    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      if (_swipeIndicator.value?.type == _SwipeType.zoom) {
        _swipeIndicator.value = null;
      }
    });
  }

  /// Back to untouched. Called when a new episode loads, since a crop tuned for
  /// one aspect ratio is wrong for the next.
  void _resetZoom() {
    if (_videoZoom == _kMinZoom) return;
    setState(() => _videoZoom = _kMinZoom);
  }

  void _onPanStart(DragStartDetails d, BoxConstraints constraints) {
    _dragStart = d.localPosition;
    _dragIsHorizontal = null;
    _dragSwipeType = null;
  }

  void _onPanUpdate(DragUpdateDetails d, BoxConstraints constraints) {
    final start = _dragStart;
    if (start == null) return;

    if (_dragIsHorizontal == null) {
      final dx = (d.localPosition.dx - start.dx).abs();
      final dy = (d.localPosition.dy - start.dy).abs();
      if (dx < 8 && dy < 8) return;
      _dragIsHorizontal = dx > dy;

      if (_dragIsHorizontal!) {
        _onHDragStart(
          DragStartDetails(
            globalPosition: d.globalPosition,
            localPosition: d.localPosition,
          ),
        );
      } else {
        final isLeft = start.dx < constraints.maxWidth * 0.5;
        _dragSwipeType = isLeft ? _SwipeType.brightness : _SwipeType.volume;
      }
    }

    if (_dragIsHorizontal!) {
      _onHDragUpdate(d, constraints);
    } else if (!isDesktopPlatform) {
      // A disabled side is inert rather than reassigned: silently turning a
      // left-edge swipe into a volume change would be more surprising than
      // nothing happening, which is what the user asked for.
      final enabled = _dragSwipeType == _SwipeType.brightness
          ? _brightnessGestureEnabled
          : _volumeGestureEnabled;
      if (!enabled) return;
      final delta = -(d.delta.dy) / (constraints.maxHeight * 0.7);
      if (_dragSwipeType == _SwipeType.brightness) {
        _brightness = (_brightness + delta).clamp(0.0, 1.0).toDouble();
        unawaited(_setSystemBrightness(_brightness));
        _swipeIndicator.value = _SwipeIndicator(
          _SwipeType.brightness,
          _brightness,
        );
      } else {
        _volume = (_volume + delta).clamp(0.0, 1.0).toDouble();
        unawaited(_setSystemVolume(_volume));
        _swipeIndicator.value = _SwipeIndicator(_SwipeType.volume, _volume);
      }
    }
  }

  void _onPanEnd(DragEndDetails d) {
    if (_dragIsHorizontal == true) {
      _onHDragEnd(d);
    } else if (_dragSwipeType != null) {
      final type = _dragSwipeType;
      Future.delayed(const Duration(milliseconds: 600), () {
        // Popping the player within this window disposes _swipeIndicator.
        if (!mounted) return;
        if (_swipeIndicator.value?.type == type) {
          _swipeIndicator.value = null;
        }
      });
    }
    _dragStart = null;
    _dragIsHorizontal = null;
    _dragSwipeType = null;
  }

  void _onPanCancel() {
    if (_dragIsHorizontal == true) _onHDragCancel();
    _swipeIndicator.value = null;
    _dragStart = null;
    _dragIsHorizontal = null;
    _dragSwipeType = null;
  }
}
