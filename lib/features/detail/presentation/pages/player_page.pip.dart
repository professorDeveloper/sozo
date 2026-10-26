// ignore_for_file: invalid_use_of_protected_member
part of 'player_page.dart';

extension _PlayerPip on _PlayerPageState {
  Future<void> _loadSystemControlValues() async {
    try {
      final results = await Future.wait([
        _systemControlsChannel.invokeMethod<double>('getBrightness'),
        _systemControlsChannel.invokeMethod<double>('getVolume'),
      ]);
      _brightness = (results[0] ?? _brightness).clamp(0.0, 1.0).toDouble();
      _volume = (results[1] ?? _volume).clamp(0.0, 1.0).toDouble();
    } catch (_) {}
  }

  Future<void> _onPipMethodCall(MethodCall call) async {
    if (call.method != 'onPipAction') return;
    final action = call.arguments;
    if (action is! String) return;
    switch (action) {
      case 'play_pause':
        if (_partyBlockLocal()) return;
        _togglePlay();
        _refreshPipActions();
      case 'rewind':
        if (_partyBlockLocal()) return;
        _seekRelative(-_seekStep);
      case 'forward':
        if (_partyBlockLocal()) return;
        _seekRelative(_seekStep);
      case 'prev':
        if (_partyBlockEpisodeNav()) return;
        // The SERIES bounds, not the loaded page's: at the top of page two
        // `_episodeIndex - 1` is -1, and _loadEpisode pages back across it.
        if (_hasPrevEpisode) _loadEpisode(_episodeIndex - 1);
      case 'next':
        if (_partyBlockEpisodeNav()) return;
        if (widget.args.isSerial && _hasNextEpisode) {
          _loadEpisode(_episodeIndex + 1);
        }
    }
  }

  Future<void> _refreshPipActions() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final isPlaying = c.value.isPlaying;
    final hasPrev = _hasPrevEpisode;
    final hasNext = _hasNextEpisode;
    if (isPlaying == _lastPipPlaying) {
      try {
        await _pipChannel.invokeMethod('updatePiPActions', {
          'isPlaying': isPlaying,
          'hasPrev': hasPrev,
          'hasNext': hasNext,
        });
      } catch (_) {}
      return;
    }
    _lastPipPlaying = isPlaying;
    try {
      await _pipChannel.invokeMethod('updatePiPActions', {
        'isPlaying': isPlaying,
        'hasPrev': hasPrev,
        'hasNext': hasNext,
      });
    } catch (_) {}
  }

  Future<void> _enterPip() async {
    if (isIosPlatform) return _enterIosPip();
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    try {
      final available = await _floating.isPipAvailable;
      if (!available) return;
      final size = c.value.size;
      Rational ratio = const Rational.landscape();
      if (size.width > 0 && size.height > 0) {
        final w = size.width.round();
        final h = size.height.round();
        if (w > 0 && h > 0) {
          final candidate = Rational(w, h);
          final aspect = candidate.aspectRatio;
          if (aspect >= 1 / 2.39 && aspect <= 2.39) {
            ratio = candidate;
          }
        }
      }
      final result = await _floating.enable(ImmediatePiP(aspectRatio: ratio));
      if (result == PiPStatus.enabled && mounted) {
        setState(() {
          _isPip = true;
          _controlsVisible = false;
          _hideTimer?.cancel();
          _panel = _SidePanel.none;
        });
        _controlsAnimation.reverse();
        _lastPipPlaying = !c.value.isPlaying;
        _refreshPipActions();
      }
    } catch (_) {}
  }

  /// iOS: the episode goes to a native player the system can float — the
  /// in-app one draws through a Flutter texture no PiP controller can take —
  /// at the same second and speed. [_onIosPipCall] picks it back up.
  Future<void> _enterIosPip() async {
    final c = _controller;
    final url = _videoUrl;
    if (c == null || !c.value.isInitialized || url == null || url.isEmpty) {
      return;
    }
    final wasPlaying = c.value.isPlaying;
    final position = c.value.position.inMilliseconds;
    await c.pause();
    if (!mounted) return;
    _hideTimer?.cancel();
    setState(() {
      _isPip = true;
      _controlsVisible = false;
      _panel = _SidePanel.none;
    });
    _controlsAnimation.reverse();
    var ok = false;
    try {
      ok =
          await _iosPipChannel.invokeMethod<bool>('start', {
            'url': url,
            'headers': _headers,
            'positionMs': position,
            'rate': c.value.playbackSpeed,
          }) ??
          false;
    } catch (_) {}
    if (ok || !mounted) return;
    setState(() => _isPip = false);
    if (wasPlaying) unawaited(c.play());
    _toast('player.pip_unavailable'.tr());
  }

  /// The floating window closed — by the viewer returning to the app or
  /// dismissing it: playback carries on here from where it got to.
  Future<void> _onIosPipCall(MethodCall call) async {
    if (call.method != 'stopped' && call.method != 'failed') return;
    final c = _controller;
    if (!mounted || c == null) return;
    setState(() => _isPip = false);
    if (call.method == 'failed') return;
    final args = (call.arguments as Map?) ?? const {};
    final ms = (args['positionMs'] as num?)?.toInt() ?? 0;
    if (ms > 0) await c.seekTo(Duration(milliseconds: ms));
    // Back in the app it plays on if it was playing; closed from the window
    // it stays paused, as the system player left it.
    if (args['playing'] == true && args['restored'] == true) {
      unawaited(c.play());
    }
  }

  /// The PiP button and the I key: the corner player when this page can go
  /// there, the always-on-top window otherwise.
  void _openMiniPlayer() {
    if (_canDock) {
      unawaited(_dockToCorner());
    } else {
      unawaited(_toggleDesktopMini());
    }
  }

  /// Whether this page can move into the corner player: on the desktop, when
  /// it was opened through PlayerRoute (which keys it), and not while a
  /// television is playing — the corner would only show the "playing on"
  /// card.
  bool get _canDock =>
      PlayerDock.supported && widget.key is GlobalKey && !_cast.isCasting;

  /// Desktop picture-in-picture, the long way round: the whole window becomes
  /// a small player above every other window, and back. The corner player
  /// ([_dockToCorner]) cannot float over other apps; this is how to watch
  /// over them.
  Future<void> _toggleDesktopMini() async {
    if (!isDesktopPlatform) return;
    // From the corner the way out is the full player first.
    if (_docked) return;
    if (_desktopMini) {
      setState(() {
        _desktopMini = false;
        _isPip = false;
      });
      _miniHover.value = false;
      await DesktopWindow.exitMini();
      if (_floatedFromDock) {
        _floatedFromDock = false;
        if (mounted) await _dockToCorner();
      }
      return;
    }
    final size = _controller?.value.size ?? Size.zero;
    final aspect = size.width > 0 && size.height > 0
        ? size.width / size.height
        : 16 / 9;
    _hideTimer?.cancel();
    setState(() {
      _desktopMini = true;
      _isPip = true;
      _controlsVisible = false;
      _panel = _SidePanel.none;
      if (_isFullscreen) _isFullscreen = false;
    });
    _controlsAnimation.reverse();
    await DesktopWindow.enterMini(aspect: aspect);
  }

  /// Switching to another app with a video playing floats it above that app,
  /// as Telegram does: the window becomes the small always-on-top player.
  /// It stays there until the viewer leaves it from its own controls, so a
  /// click on it to pause does not throw it back to full size. A paused
  /// video, a television playing it and the floating window itself are left
  /// alone.
  Future<void> _floatWhenLeaving() async {
    if (!isDesktopPlatform || _desktopMini || !mounted) return;
    if (_cast.isCasting) return;
    final c = _controller;
    if (c == null || !c.value.isInitialized || !c.value.isPlaying) return;
    if (_docked) {
      // The floating window shows this page; from the corner it is a box in
      // another screen, so it comes back to its own route first.
      _expandFromDock();
      if (_docked) return;
      _floatedFromDock = true;
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
    }
    await _toggleDesktopMini();
  }

  /// The corner player, Telegram-style. This page leaves the route stack and
  /// carries on, State and all, in a small box over whatever the viewer opens
  /// next. Nothing is handed over or rebuilt: the GlobalKey PlayerRoute gave
  /// this page moves it into PlayerDockHost in the same frame, so history
  /// ticks, auto-advance, subtitles, party sync and retries keep running as
  /// they were.
  Future<void> _dockToCorner() async {
    final key = widget.key;
    if (!_canDock || _docked || key is! GlobalKey) return;
    if (_desktopMini) await _toggleDesktopMini();
    if (!mounted) return;
    if (_isFullscreen) {
      _isFullscreen = false;
      unawaited(DesktopWindow.setFullscreen(false));
    }
    _hideTimer?.cancel();
    setState(() {
      _docked = true;
      _isPip = true;
      _controlsVisible = false;
      _panel = _SidePanel.none;
    });
    _controlsAnimation.reverse();
    _miniHover.value = false;
    _keyFocus.unfocus();
    // A save that notifies, unlike the five-second tick: Continue Watching on
    // the page under the corner should show this title now, not when it is
    // paused.
    _saveHistory();
    PlayerDock.instance.dock(
      key: key,
      args: widget.args,
      videoSize: _controller?.value.size ?? Size.zero,
    );
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/main');
    }
  }

  /// From the corner back to the full player, the same State again.
  void _expandFromDock() {
    if (!_docked || !PlayerDock.instance.expand()) return;
    setState(() {
      _docked = false;
      _isPip = false;
    });
    _miniHover.value = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _keyFocus.requestFocus();
      _revealControlsForHover();
    });
  }

  /// Closes the corner player; dispose saves history and stops the stream.
  void _closeDock() => unawaited(PlayerDock.instance.close());

  /// A new episode or rendition can change the picture's shape, and the
  /// corner box follows it. After the frame: the dock notifies its host,
  /// which must not happen during this page's build.
  void _reportDockAspect() {
    final size = _controller?.value.size;
    if (size == null || size.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _docked) PlayerDock.instance.reportVideoSize(size);
    });
  }

  /// The small player's own controls, shown while the pointer is over it —
  /// in the always-on-top window and in the corner player alike. Play or
  /// pause in the middle with the neighbouring episodes either side, the
  /// title and the way back to the full player along the top (and, in the
  /// corner, closing it), and a timeline to click along the bottom. The rest
  /// is a handle: in the always-on-top window it moves the OS window, in the
  /// corner it moves the corner player.
  Widget _buildDesktopMiniOverlay() {
    final c = _controller;
    final inApp = _docked;
    Widget round(
      IconData icon,
      String tip,
      VoidCallback? onTap, {
      double size = 18,
    }) => Tooltip(
      message: tip,
      child: Material(
        color: Colors.black.withValues(alpha: 0.55),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: Icon(
              icon,
              // Dimmed rather than absent at either end of a season, so the
              // row does not shift under the pointer.
              color: Colors.white.withValues(alpha: onTap == null ? 0.38 : 1),
              size: size,
            ),
          ),
        ),
      ),
    );
    const scrim = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x99000000), Color(0x22000000), Color(0x99000000)],
        ),
      ),
    );
    final dock = PlayerDock.instance;
    final controls = MouseRegion(
      onEnter: (_) => _miniHover.value = true,
      onHover: (_) => _miniHover.value = true,
      onExit: (_) => _miniHover.value = false,
      child: ValueListenableBuilder<bool>(
        valueListenable: _miniHover,
        builder: (context, hover, _) {
          // Loading or failed, the controls stay up: closing or going back to
          // the full player — where Try again and the other sources are — are
          // the useful moves then.
          final show = hover || _initializing || _errorMessage != null;
          return AnimatedOpacity(
            opacity: show ? 1 : 0,
            duration: const Duration(milliseconds: 160),
            child: IgnorePointer(
              ignoring: !show,
              child: LayoutBuilder(
                builder: (context, box) {
                  final roomy = box.maxWidth >= 320;
                  final episodes = _affordances.hasEpisodes;
                  // Neighbouring episodes outrank the ten-second steps when
                  // there is room for only one pair; the arrow keys still step.
                  final steps = !episodes || box.maxWidth >= 360;
                  final gap = SizedBox(width: roomy ? 14 : 8);
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      if (inApp)
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanStart: (_) => dock.dragStart(),
                          onPanUpdate: (d) => dock.dragBy(d.delta),
                          onPanEnd: (d) =>
                              dock.dragEnd(d.velocity.pixelsPerSecond),
                          onPanCancel: () {
                            if (dock.dragging) dock.dragEnd(Offset.zero);
                          },
                          child: scrim,
                        )
                      else
                        const DragToMoveArea(child: scrim),
                      Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (episodes) ...[
                              round(
                                Icons.skip_previous_rounded,
                                'player.previous'.tr(),
                                _hasPrevEpisode
                                    ? () => _partyEpisodeNav(_episodeIndex - 1)
                                    : null,
                              ),
                              gap,
                            ],
                            if (steps) ...[
                              round(
                                Icons.fast_rewind_rounded,
                                'player.rewind'.tr(),
                                () => _seekRelative(-_seekStep),
                              ),
                              gap,
                            ],
                            if (c != null)
                              ListenableBuilder(
                                listenable: c,
                                builder: (_, _) => round(
                                  c.value.isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  c.value.isPlaying
                                      ? 'player.pause'.tr()
                                      : 'player.play'.tr(),
                                  _togglePlay,
                                  size: 30,
                                ),
                              ),
                            if (steps) ...[
                              gap,
                              round(
                                Icons.fast_forward_rounded,
                                'player.forward'.tr(),
                                () => _seekRelative(_seekStep),
                              ),
                            ],
                            if (episodes) ...[
                              gap,
                              round(
                                Icons.skip_next_rounded,
                                'player.next_episode'.tr(),
                                _hasNextEpisode
                                    ? () => _partyEpisodeNav(_episodeIndex + 1)
                                    : null,
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (inApp)
                        Positioned(
                          top: 6,
                          left: 6,
                          child: round(
                            Icons.close_rounded,
                            'general.close'.tr(),
                            _closeDock,
                          ),
                        ),
                      if (roomy)
                        Positioned(
                          left: 48,
                          right: 48,
                          top: 14,
                          child: Text(
                            _episodeTitle(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              shadows: _kControlShadow,
                            ),
                          ),
                        ),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: round(
                          Icons.open_in_full_rounded,
                          'player.mini_restore'.tr(),
                          inApp ? _expandFromDock : _toggleDesktopMini,
                        ),
                      ),
                      if (c != null && !_isLive)
                        Positioned(
                          left: 10,
                          right: 10,
                          bottom: 6,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (roomy)
                                ListenableBuilder(
                                  listenable: c,
                                  builder: (_, _) => Text(
                                    '${_formatDuration(c.value.position)}'
                                    ' / ${_formatDuration(c.value.duration)}',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      fontFeatures: [
                                        FontFeature.tabularFigures(),
                                      ],
                                      shadows: _kControlShadow,
                                    ),
                                  ),
                                ),
                              _MiniSeekBar(controller: c, onSeek: _seekTo),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          );
        },
      ),
    );
    return Positioned.fill(
      // In the corner the page's text is scaled down with the box (see
      // PlayerDockHost); these few labels are the controls' own, and they
      // stay readable at any size.
      child: inApp
          ? MediaQuery.withClampedTextScaling(
              minScaleFactor: 1,
              child: controls,
            )
          : controls,
    );
  }

  Future<void> _startup() async {
    final sw = Stopwatch()..start();
    _plog('startup — entering fullscreen');
    await _enterFullscreen();
    _plog('fullscreen ready in ${sw.elapsedMilliseconds}ms');
    if (!mounted) return;

    // The engine question is asked BEFORE this page is pushed — see
    // confirmPlayerEngine. It used to be asked here, which put a modal over a
    // player showing nothing: a black rectangle with a question on top, which
    // reads as the video having failed rather than as a choice being offered.
    await _bootstrap();
  }

  Future<void> _enterFullscreen() async {
    // No wakelock here. Entering the player is not watching: resolution can
    // take half a minute and the viewer may never press play. _syncWakelock
    // takes the hold when the picture actually starts moving.
    if (isDesktopPlatform) return;
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    try {
      await AppOrientation.set([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } catch (_) {}
  }

  Future<void> _toggleFullscreen() async {
    if (!isDesktopPlatform) return;
    final next = !_isFullscreen;
    if (mounted) setState(() => _isFullscreen = next);
    await DesktopWindow.setFullscreen(next);
  }

  Future<void> _toggleOrientation() async {
    _isPortrait = !_isPortrait;
    try {
      if (_isPortrait) {
        await AppOrientation.set([DeviceOrientation.portraitUp]);
      } else {
        await AppOrientation.set([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      }
    } catch (_) {}
    setState(() {});
  }

  Future<void> _restoreSystemUi() async {
    _isPortrait = false;
    if (isDesktopPlatform) {
      if (_isFullscreen) {
        _isFullscreen = false;
        await DesktopWindow.setFullscreen(false);
      }
      // Only this page's hold: a download on this machine may still need the
      // screen awake after the player closes.
      _wakelockHeld = false;
      await WakelockHolds.release(this);
      return;
    }
    try {
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
      await AppOrientation.set([DeviceOrientation.portraitUp]);
    } catch (_) {}
    _wakelockHeld = false;
    await WakelockHolds.release(this);
  }

  /// A swipe asks for a new level on every touch sample — 120 a second on a
  /// fast panel — and each call was a window relayout or an AudioManager IPC
  /// on the thread that draws the next frame. The first goes at once, then at
  /// most one per 50 ms; the trailing call lands wherever the finger stopped.
  void _pushSystemLevels({bool brightness = false, bool volume = false}) {
    _brightnessDirty |= brightness;
    _volumeDirty |= volume;
    if (_systemLevelTimer?.isActive ?? false) return;
    _flushSystemLevels();
    _systemLevelTimer = Timer(const Duration(milliseconds: 50), () {
      if (mounted) _flushSystemLevels();
    });
  }

  void _flushSystemLevels() {
    if (_brightnessDirty) {
      _brightnessDirty = false;
      unawaited(_setSystemBrightness(_brightness));
    }
    if (_volumeDirty) {
      _volumeDirty = false;
      unawaited(_setSystemVolume(_volume));
    }
  }

  Future<void> _setSystemBrightness(double value) async {
    try {
      await _systemControlsChannel.invokeMethod<double>('setBrightness', {
        'value': value,
      });
    } catch (_) {}
  }

  Future<void> _setSystemVolume(double value) async {
    try {
      await _systemControlsChannel.invokeMethod<double>('setVolume', {
        'value': value,
      });
    } catch (_) {}
  }
}
