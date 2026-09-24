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

  /// Desktop picture-in-picture: the whole window becomes a small player
  /// above every other window, and back.
  Future<void> _toggleDesktopMini() async {
    if (!isDesktopPlatform) return;
    if (_desktopMini) {
      setState(() {
        _desktopMini = false;
        _isPip = false;
      });
      _miniHover.value = false;
      await DesktopWindow.exitMini();
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

  /// The mini window's own controls, shown while the pointer is over it:
  /// play or pause in the middle, back to the full window and a step either
  /// way at the top, and how far along under it. The rest of the window is a
  /// handle to move it by.
  Widget _buildDesktopMiniOverlay() {
    final c = _controller;
    Widget round(
      IconData icon,
      String tip,
      VoidCallback onTap, {
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
            child: Icon(icon, color: Colors.white, size: size),
          ),
        ),
      ),
    );
    return Positioned.fill(
      child: MouseRegion(
        onEnter: (_) => _miniHover.value = true,
        onHover: (_) => _miniHover.value = true,
        onExit: (_) => _miniHover.value = false,
        child: ValueListenableBuilder<bool>(
          valueListenable: _miniHover,
          builder: (context, hover, _) => AnimatedOpacity(
            opacity: hover ? 1 : 0,
            duration: const Duration(milliseconds: 160),
            child: IgnorePointer(
              ignoring: !hover,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const DragToMoveArea(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0x99000000),
                            Color(0x22000000),
                            Color(0x99000000),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        round(
                          Icons.fast_rewind_rounded,
                          'player.rewind'.tr(),
                          () => _seekRelative(-_seekStep),
                        ),
                        const SizedBox(width: 14),
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
                        const SizedBox(width: 14),
                        round(
                          Icons.fast_forward_rounded,
                          'player.forward'.tr(),
                          () => _seekRelative(_seekStep),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: round(
                      Icons.open_in_full_rounded,
                      'player.mini_restore'.tr(),
                      _toggleDesktopMini,
                    ),
                  ),
                  if (c != null)
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 8,
                      child: ListenableBuilder(
                        listenable: c,
                        builder: (_, _) {
                          final d = c.value.duration.inMilliseconds;
                          final p = c.value.position.inMilliseconds;
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: d > 0 ? (p / d).clamp(0.0, 1.0) : 0,
                              minHeight: 3,
                              backgroundColor: Colors.white24,
                              valueColor: AlwaysStoppedAnimation(
                                AppColors.primary,
                              ),
                            ),
                          );
                        },
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
