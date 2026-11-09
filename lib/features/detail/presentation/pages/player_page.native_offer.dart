// ignore_for_file: invalid_use_of_protected_member
part of 'player_page.dart';

/// The one-time "Try the new player?" offer, and applying a yes in place.
extension _PlayerNativeOffer on _PlayerPageState {
  /// Asked when the controls show and when playback changes state; shows the
  /// offer once the picture is up, the controls are, and no finger is busy.
  void _maybeOfferNativeControls() {
    if (!_nativeOfferPending || _nativeOfferOpen || !mounted) return;
    final c = _controller;
    if (c == null) return;
    final v = c.value;
    if (!v.isInitialized || v.hasError || v.isBuffering) return;
    if (_initializing || _errorMessage != null || _isCodecError) return;
    if (_serverSwitch != null || _autoRetrying) return;
    // Paused, or within the first moments of playing.
    if (v.isPlaying && _playbackWatch.elapsed > const Duration(seconds: 20)) {
      return;
    }
    if (!_controlsVisible || _locked || _compact || _isPip) return;
    if (_panel != _SidePanel.none || _cast.isCasting) return;
    if (_speedBoost.value ||
        _seekBarDragging.value ||
        _sliderDragValue.value != null ||
        _swipeIndicator.value != null ||
        _dragSwipeType != null) {
      return;
    }
    final offer = NativeControls.shouldOffer(
      context,
      stored: _hive.storedPlayerControlsStyle,
      alreadyOffered: _hive.nativeControlsOffered,
    );
    if (!offer) {
      _nativeOfferPending = false;
      return;
    }
    _nativeOfferOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _nativeOfferPending = false;
      final style = await presentNativeControlsOffer(context, _hive);
      _nativeOfferOpen = false;
      if (mounted) _applyControlsStyle(style);
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  /// Swaps the controls in this player without reopening it.
  void _applyControlsStyle(PlayerControlsStyle style) {
    if (style == _controlsStyle) return;
    setState(() {
      _controlsStyle = style;
      _nativeControls = NativeControls.decide(context, chosen: style);
    });
  }
}
