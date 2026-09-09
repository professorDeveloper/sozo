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
        if (widget.args.isSerial && _episodeIndex - 1 >= 0) {
          _loadEpisode(_episodeIndex - 1);
        }
      case 'next':
        if (_partyBlockEpisodeNav()) return;
        if (widget.args.isSerial &&
            _hasNextEpisode) {
          _loadEpisode(_episodeIndex + 1);
        }
    }
  }

  Future<void> _refreshPipActions() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final isPlaying = c.value.isPlaying;
    final hasPrev = widget.args.isSerial && _episodeIndex > 0;
    final hasNext =
        _hasNextEpisode;
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
    if (isDesktopPlatform) {
      if (_hive.keepScreenOn) await WakelockPlus.enable();
      return;
    }
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    try {
      await AppOrientation.set([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } catch (_) {}
    if (_hive.keepScreenOn) await WakelockPlus.enable();
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
        await AppOrientation.set([
          DeviceOrientation.portraitUp,
        ]);
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
      try {
        await WakelockPlus.disable();
      } catch (_) {}
      return;
    }
    try {
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
      await AppOrientation.set([
        DeviceOrientation.portraitUp,
      ]);
    } catch (_) {}
    await WakelockPlus.disable();
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
