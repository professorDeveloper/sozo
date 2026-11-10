// ignore_for_file: invalid_use_of_protected_member
part of 'player_page.dart';

/// Android audio focus, the media session and auto-enter PiP.
const MethodChannel _playerSystemChannel = MethodChannel(
  'soplay/player_system',
);

extension _PlayerSystem on _PlayerPageState {
  void _attachPlayerSystem() {
    if (!isAndroidPlatform) return;
    _playerSystemChannel.setMethodCallHandler(_onPlayerSystemCall);
    unawaited(_systemInvoke('attach'));
  }

  void _detachPlayerSystem() {
    if (!isAndroidPlatform) return;
    _playerSystemChannel.setMethodCallHandler(null);
    unawaited(_systemInvoke('detach'));
    if (_autoPipArmed) {
      _autoPipArmed = false;
      unawaited(_pipInvoke('setAutoPip', {'enabled': false}));
    }
  }

  Future<Object?> _systemInvoke(String method, [Object? args]) async {
    try {
      return await _playerSystemChannel.invokeMethod<Object?>(method, args);
    } catch (_) {
      return null;
    }
  }

  Future<void> _pipInvoke(String method, Object? args) async {
    try {
      await _pipChannel.invokeMethod<Object?>(method, args);
    } catch (_) {}
  }

  /// From the controller listener, on every tick.
  void _syncPlayerSystem() {
    if (!isAndroidPlatform) return;
    final c = _controller;
    if (c == null) return;
    final v = c.value;
    final playing = v.isPlaying;
    if (playing != _systemPlaying) {
      _systemPlaying = playing;
      _audioFocusPolicy.onPlayingChanged(playing);
      if (playing && !c.handlesAudioFocus) unawaited(_requestAudioFocus(c));
      _syncAutoPip();
      if (_isPip || _autoPipArmed) unawaited(_refreshPipActions());
    }
    _syncMediaSession(c);
  }

  Future<void> _requestAudioFocus(PlayerController c) async {
    final granted = await _systemInvoke('requestAudioFocus');
    // Refused during a phone call: playing over it is what this prevents.
    if (granted == false && identical(c, _controller) && c.value.isPlaying) {
      unawaited(c.pause());
    }
  }

  void _syncMediaSession(PlayerController c) {
    final v = c.value;
    if (!v.isInitialized) return;
    final serial = widget.args.isSerial;
    final metaKey = '$_episodeIndex|${v.duration.inSeconds}';
    if (metaKey != _mediaMetaKey) {
      _mediaMetaKey = metaKey;
      final title = _episodeTitle();
      final prefix = '${widget.args.title} · ';
      unawaited(
        _systemInvoke('setMetadata', {
          'title': widget.args.title,
          'subtitle': serial && title.startsWith(prefix)
              ? title.substring(prefix.length)
              : null,
          'durationMs': _isLive ? 0 : v.duration.inMilliseconds,
          'artworkUrl': widget.args.thumbnail,
        }),
      );
      _mediaGate.reset();
    }
    final send = _mediaGate.shouldSend(
      playing: v.isPlaying,
      positionMs: v.position.inMilliseconds,
      speed: v.playbackSpeed,
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
    if (!send) return;
    unawaited(
      _systemInvoke('setPlaybackState', {
        'playing': v.isPlaying,
        'positionMs': v.position.inMilliseconds,
        'speed': v.playbackSpeed,
        'hasPrev': serial && _hasPrevEpisode,
        'hasNext': serial && _hasNextEpisode,
        'seekable': !_isLive,
      }),
    );
  }

  Future<void> _onPlayerSystemCall(MethodCall call) async {
    if (!mounted) return;
    switch (call.method) {
      case 'audioFocus':
        _onAudioFocusEvent(audioFocusEventFromWire(call.arguments as String?));
      case 'mediaCommand':
        final args = (call.arguments as Map?) ?? const {};
        _onMediaCommand(
          args['action'] as String?,
          (args['positionMs'] as num?)?.toInt(),
        );
    }
  }

  void _onAudioFocusEvent(AudioFocusEvent? event) {
    final c = _controller;
    if (event == null || c == null || !c.value.isInitialized) return;
    // An engine that takes focus itself reacts on its own; ours, if still
    // held from an earlier stream, losing it to that engine is not a reason
    // to pause.
    if (c.handlesAudioFocus && event != AudioFocusEvent.noisy) return;
    final response = _audioFocusPolicy.on(event, playing: c.value.isPlaying);
    _plog('audio focus: ${event.name}');
    if (response.volume != null) unawaited(c.setVolume(response.volume!));
    if (response.pause) {
      _resumeAfterPause = false;
      unawaited(c.pause());
    }
    if (response.resume) unawaited(c.play());
  }

  void _onMediaCommand(String? action, int? positionMs) {
    final c = _controller;
    if (action == null || c == null || !c.value.isInitialized) return;
    switch (action) {
      case 'play':
        if (!c.value.isPlaying) _togglePlay();
      case 'pause':
        if (c.value.isPlaying) _togglePlay();
      case 'seek':
        if (positionMs != null) _seekTo(Duration(milliseconds: positionMs));
      case 'rewind' || 'forward' || 'prev' || 'next':
        unawaited(_onPipMethodCall(MethodCall('onPipAction', action)));
    }
  }

  /// Auto-enter PiP on Home, armed only while a video plays here.
  void _syncAutoPip() {
    if (!isAndroidPlatform || isTvPlatform) return;
    final c = _controller;
    final want =
        _autoPipSetting &&
        c != null &&
        c.value.isInitialized &&
        c.value.isPlaying &&
        !_cast.isCasting &&
        mounted;
    if (!want) {
      if (!_autoPipArmed) return;
      _autoPipArmed = false;
      unawaited(_pipInvoke('setAutoPip', {'enabled': false}));
      return;
    }
    _autoPipArmed = true;
    final video = c.value.size;
    final (num, den) = pipAspect(video);
    final view = View.of(context);
    final rect = pipSourceRect(view.physicalSize, video);
    unawaited(
      _pipInvoke('setAutoPip', {
        'enabled': true,
        'numerator': num,
        'denominator': den,
        if (rect != null)
          'sourceRect': [
            rect.left.round(),
            rect.top.round(),
            rect.right.round(),
            rect.bottom.round(),
          ],
      }),
    );
  }

  /// The activity entered or left PiP — by our button, by Home with
  /// auto-enter, or by the viewer closing the window.
  void _onAndroidPipMode(Map<Object?, Object?> args) {
    final change = _pipTracker.onModeChanged(
      inPip: args['inPip'] == true,
      dismissed: args['dismissed'] == true,
    );
    switch (change) {
      case PipChange.none:
        return;
      case PipChange.entered:
        _hideTimer?.cancel();
        setState(() {
          _isPip = true;
          _controlsVisible = false;
          _panel = _SidePanel.none;
        });
        _controlsAnimation.reverse();
        unawaited(_refreshPipActions());
      case PipChange.restored:
        setState(() => _isPip = false);
      case PipChange.dismissed:
        setState(() => _isPip = false);
        // Closing the window is stopping: no audio left playing behind it.
        _resumeAfterPause = false;
        final c = _controller;
        if (c != null && c.value.isPlaying) unawaited(c.pause());
        _saveHistory();
    }
  }

  void _handBackBrightness() {
    if (isDesktopPlatform || _brightnessHandedBack) return;
    if (!_brightnessKeeper.onBackground()) return;
    _brightnessHandedBack = true;
    unawaited(SystemControls.resetBrightness());
  }

  void _reapplyBrightness() {
    if (isDesktopPlatform) return;
    _brightnessHandedBack = false;
    final level = _brightnessKeeper.onResume();
    if (level != null) unawaited(_setSystemBrightness(level));
  }
}
