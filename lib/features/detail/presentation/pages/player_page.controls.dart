// ignore_for_file: invalid_use_of_protected_member
part of 'player_page.dart';

extension _PlayerControls on _PlayerPageState {
  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) {
      _controlsAnimation.forward();
      _scheduleHide();
    } else {
      _controlsAnimation.reverse();
      _hideTimer?.cancel();
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    // A remote takes longer to aim than a finger, so TV gets a longer grace
    // period before the overlay disappears out from under the cursor.
    _hideTimer = Timer(Duration(seconds: isTvPlatform ? 7 : 4), () {
      if (!mounted) return;
      final c = _controller;
      if (c != null && c.value.isPlaying && _panel == _SidePanel.none) {
        // Never hide the overlay while a D-pad scrub is still pending — the
        // thumb the viewer is aiming with would vanish.
        if (isTvPlatform && _sliderDragValue.value != null) {
          _scheduleHide();
          return;
        }
        setState(() => _controlsVisible = false);
        _controlsAnimation.reverse();
        // ExcludeFocus is about to drop whatever was focused; take focus back
        // to the root so key events keep reaching _onTvPlayerKey.
        _tvHandOffFocusToRoot();
      }
    });
  }

  void _togglePlay() {
    if (_partyBlockLocal()) return;
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final wasPlaying = c.value.isPlaying;
    if (wasPlaying) {
      c.pause();
    } else {
      c.play();
      _scheduleHide();
    }
    _partyEmit(
      wasPlaying ? 'pause' : 'play',
      positionSec: c.value.position.inMilliseconds / 1000.0,
    );
  }

  void _setPlayerVolume(double v) {
    final clamped = v.clamp(0.0, 1.0);
    setState(() => _volume = clamped);
    if (isDesktopPlatform) {
      _controller?.setVolume(clamped);
    } else {
      unawaited(_setSystemVolume(clamped));
    }
    _scheduleHide();
  }

  void _toggleMute() {
    if (_volume > 0.001) {
      _volumeBeforeMute = _volume;
      _setPlayerVolume(0);
    } else {
      _setPlayerVolume(_volumeBeforeMute <= 0.001 ? 1.0 : _volumeBeforeMute);
    }
  }

  void _seekRelative(Duration delta) {
    if (_partyBlockLocal()) return;
    // There is nothing to skip forward into on a broadcast, and skipping back
    // lands outside the DVR window on most channels — the stream stalls and the
    // viewer's only way out is to leave and come back. The double-tap gesture
    // reaches here too, which is how a stray tap used to kill a channel.
    if (_isLive) return;
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final next = c.value.position + delta;
    final clamped = next < Duration.zero
        ? Duration.zero
        : next > c.value.duration
        ? c.value.duration
        : next;
    c.seekTo(clamped);
    _scheduleHide();
    if (!_isLive) {
      _partyEmit('seek', positionSec: clamped.inMilliseconds / 1000.0);
    }
  }

  void _seekTo(Duration position) {
    if (_partyBlockLocal()) return;
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    // `Go live` is the one seek a broadcast accepts, and it asks for the very
    // end; anything else is a scrub bar that should not have been reachable.
    if (_isLive && position < c.value.duration) return;
    c.seekTo(position);
    _scheduleHide();
    if (!_isLive) {
      _partyEmit('seek', positionSec: position.inMilliseconds / 1000.0);
    }
  }

  void _clearDragAfterSeek(Duration target) {
    void listener() {
      final c = _controller;
      if (c == null) {
        _sliderDragValue.value = null;
        return;
      }
      final diff = (c.value.position - target).inMilliseconds.abs();
      if (diff < 500) {
        c.removeListener(listener);
        _sliderDragValue.value = null;
      }
    }
    _controller?.addListener(listener);
    Future.delayed(const Duration(seconds: 1), () {
      // The user can pop the player within this second — _sliderDragValue is
      // disposed by then, so touching it would throw.
      if (!mounted) return;
      _controller?.removeListener(listener);
      if (_sliderDragValue.value != null &&
          _sliderDragValue.value == target.inMilliseconds.toDouble()) {
        _sliderDragValue.value = null;
      }
    });
  }

  void _exit() {
    if (isTvPlatform && !_tvPopAllowed) {
      // The TV PopScope blocks pops so BACK can be interpreted; unlatch it for
      // one frame so this deliberate exit gets through. Routing every existing
      // caller (back button, error overlay, Escape) through here means none of
      // them need to know about the guard.
      setState(() => _tvPopAllowed = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _exit();
      });
      return;
    }
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/main');
    }
  }

  void _openPanel(_SidePanel panel) {
    if (isTvPlatform) {
      // Start a long episode list near the episode being watched. The rows are
      // built lazily, so autofocus alone cannot reach item 80 of 120 — the
      // offset is an estimate that puts the active row on screen, and D-pad
      // traversal (with Flutter's built-in ensureVisible) corrects from there.
      final previous = _tvPanelScroll;
      _tvPanelScroll = ScrollController(
        initialScrollOffset: panel == _SidePanel.episodes
            ? (_episodeIndex - 2).clamp(0, 1 << 20) * _kTvEpisodeRowEstimate
            : 0,
      );
      if (previous != null) {
        // Switching panels rebuilds the list this frame; the old controller is
        // still attached until then.
        WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
      }
    }
    setState(() {
      _panel = panel;
      _controlsVisible = true;
    });
    _controlsAnimation.forward();
    _hideTimer?.cancel();
    if (isTvPlatform) {
      // Post-frame: the panel's rows do not exist yet during this build, so
      // there is nothing to focus until it has been laid out. An `autofocus`
      // row (the active quality/episode) claims focus first and this becomes a
      // no-op — which is the order we want.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _panel == _SidePanel.none) return;
        if (_tvPanelFocus.focusedChild == null) _tvPanelFocus.nextFocus();
      });
    }
  }

  void _closePanel() {
    setState(() => _panel = _SidePanel.none);
    // Give the remote back to the player controls; otherwise focus dies with
    // the unmounted panel and the next D-pad press has nowhere to go.
    if (isTvPlatform) _tvRootFocus.requestFocus();
    _scheduleHide();
  }

  Future<void> _setSpeed(double speed) async {
    if (_partyBlockLocal()) return;
    setState(() => _playbackSpeed = speed);
    await _controller?.setPlaybackSpeed(speed);
    _partyEmit('rate', rate: speed);
  }

  void _setFit(_PlayerFit fit) {
    setState(() => _fit = fit);
  }

  String _fitLabel(_PlayerFit fit) {
    switch (fit) {
      case _PlayerFit.contain:
        return 'player.fit_original'.tr();
      case _PlayerFit.cover:
        return 'player.fit_fill'.tr();
      case _PlayerFit.fill:
        return 'player.fit_stretch'.tr();
    }
  }

  bool get _canGeneratePreview =>
      FramePreviewService.isSupported &&
      _isNetworkVideo &&
      _videoUrl != null &&
      (!_isHls || Platform.isIOS);

  Widget _buildVideoLayer() {
    if (_initializing) {
      return ColoredBox(
        color: Colors.black,
        child: _LoadingOverlay(stage: _stage, title: _episodeTitle()),
      );
    }
    final pluginCap = _pluginRequired;
    if (pluginCap != null) {
      // A party:content identity this device cannot resolve (missing on-device
      // plugin). Show the actionable install view — not a generic error — and
      // let the guest back out to the lobby to retry after installing.
      return ColoredBox(
        color: Colors.black,
        child: PartyPluginRequiredView(
          provider: _partyState.room?.content?.provider ?? widget.args.provider,
          installTarget: pluginCap.installTarget,
          onBack: () => Navigator.of(context).maybePop(),
        ),
      );
    }
    if (_errorMessage != null) {
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  color: Colors.white70,
                  size: 48,
                ),
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _retry,
                  // Without this the error screen opens with nothing focused,
                  // so the remote has no landing spot and reads as frozen.
                  autofocus: isTvPlatform,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text('general.try_again'.tr()),
                ),
                if (_isCodecError && _videoUrl != null) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () {
                      launchUrl(
                        Uri.parse(_videoUrl!),
                        mode: LaunchMode.externalApplication,
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                    ),
                    icon: const Icon(Icons.open_in_browser_rounded, size: 18),
                    label: Text('player.play_in_browser'.tr()),
                  ),
                ],
                if (isCloudflareError(_errorMessage)) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final ok = await requestCloudflareSolve(
                        context,
                        widget.args.provider,
                      );
                      if (ok && mounted) _retry();
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                    ),
                    icon: const Icon(Icons.shield_outlined, size: 18),
                    label: Text('cloudflare.solve'.tr()),
                  ),
                ],
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: () => LogViewerSheet.show(context),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white60,
                  ),
                  icon: const Icon(Icons.bug_report_outlined, size: 18),
                  label: Text('player.view_logs'.tr()),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return const ColoredBox(color: Colors.black);
    }
    return RepaintBoundary(
      child: ColoredBox(
        color: Colors.black,
        child: _FittedVideo(controller: c, fit: _fit),
      ),
    );
  }

  Widget _buildSpeedBoostBadge() {
    // Clears the status bar / cutout: in portrait the badge landed under it.
    final topInset = MediaQuery.paddingOf(context).top;
    return ValueListenableBuilder<bool>(
      valueListenable: _speedBoost,
      builder: (_, active, _) {
        return AnimatedPositioned(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          top: active ? topInset + 24 : -80,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: active ? 1 : 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.fast_forward_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'player.speed_2x'.tr(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildScrubOverlay() {
    return ValueListenableBuilder<_ScrubState?>(
      valueListenable: _scrub,
      builder: (_, state, _) {
        if (state == null) return const SizedBox.shrink();
        final preview = state.previewPosition(_scrubSecondsPerFullSwipe);
        final deltaSeconds = (preview - state.baseline).inSeconds;
        final isForward = deltaSeconds >= 0;
        final thumb = _thumbnailAt(preview);
        return IgnorePointer(
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (thumb != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: _buildThumbnailImage(thumb),
                      ),
                    )
                  else if (_canGeneratePreview)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: _GeneratedFramePreview(
                          url: _videoUrl!,
                          headers: _headers,
                          positionMs: preview.inMilliseconds,
                        ),
                      ),
                    ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isForward
                            ? Icons.fast_forward_rounded
                            : Icons.fast_rewind_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${isForward ? '+' : '−'}${deltaSeconds.abs()}s',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_formatDuration(preview)} / ${_formatDuration(state.duration)}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildThumbnailImage(_VttThumbnail thumb) {
    const double displayWidth = 160;
    const double displayHeight = 90;

    if (thumb.hasSprite) {
      final sx = displayWidth / thumb.w;
      final sy = displayHeight / thumb.h;
      return SizedBox(
        width: displayWidth,
        height: displayHeight,
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            child: Transform(
              transform: Matrix4.diagonal3Values(sx, sy, 1.0)
                ..setTranslationRaw(
                    -thumb.x * sx, -thumb.y * sy, 0.0),
              child: Image.network(
                thumb.imageUrl,
                filterQuality: FilterQuality.low,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => SizedBox(
                  width: displayWidth,
                  height: displayHeight,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Image.network(
      thumb.imageUrl,
      width: displayWidth,
      height: displayHeight,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.low,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => const SizedBox(
        width: displayWidth,
        height: displayHeight,
      ),
    );
  }

  Widget _buildSeekRipple() {
    if (_seekRippleDirection == 0) return const SizedBox.shrink();
    return IgnorePointer(
      child: Align(
        alignment: _seekRippleDirection < 0
            ? Alignment.centerLeft
            : Alignment.centerRight,
        child: AnimatedBuilder(
          animation: _seekRippleController,
          builder: (_, _) {
            final t = _seekRippleController.value;
            return Opacity(
              opacity: 1 - (t * 0.3),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _seekRippleDirection < 0
                          ? Icons.fast_rewind_rounded
                          : Icons.fast_forward_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_seekRippleSeconds}s',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSwipeIndicator() {
    // In landscape the display cutout is on one of these two edges.
    final insets = MediaQuery.paddingOf(context);
    return ValueListenableBuilder<_SwipeIndicator?>(
      valueListenable: _swipeIndicator,
      builder: (_, indicator, _) {
        if (indicator == null) return const SizedBox.shrink();
        final isBrightness = indicator.type == _SwipeType.brightness;
        return Positioned(
          top: 0,
          bottom: 0,
          left: isBrightness ? 48 + insets.left : null,
          right: isBrightness ? null : 48 + insets.right,
          child: Center(
            child: Container(
              width: 40,
              height: 140,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  Icon(
                    isBrightness
                        ? Icons.brightness_6_rounded
                        : indicator.value > 0
                        ? Icons.volume_up_rounded
                        : Icons.volume_off_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: RotatedBox(
                      quarterTurns: -1,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: indicator.value,
                          minHeight: 4,
                          backgroundColor: Colors.white24,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${(indicator.value * 100).round()}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLockOverlay() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Center(
            child: GestureDetector(
              onTap: () => setState(() => _locked = false),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.15),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_rounded,
                        color: Colors.white, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'player.tap_to_unlock'.tr(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
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

  Widget _buildControlsOverlay() {
    if (_isPip) return const SizedBox.shrink();
    final c = _controller;
    final initialized = c != null && c.value.isInitialized;
    final hasEpisodes = widget.args.isSerial && widget.args.episodes.isNotEmpty;
    final hasServers = _sourceServers.length > 1;
    final hasQualities = _currentServerSources.length > 1;
    final hasLangSwitcher = _availableLangsForCurrentEpisode().length > 1;
    // Same gate the settings-sheet entry uses (player_page.panels.dart): the
    // top bar only promotes the action, it does not widen who can download.
    // `_videoUrl` must already be resolved — a download needs the real stream,
    // not the pending/placeholder state the bar renders during load.
    final canDownload = widget.args.showDownloadAction &&
        widget.args.provider != 'uzmovi' &&
        _videoUrl != null;
    final isBuffering = c != null && c.value.isBuffering;

    final overlay = FadeTransition(
      opacity: _controlsAnimation,
      child: IgnorePointer(
        ignoring: !_controlsVisible,
        child: Stack(
          children: [
            const Positioned.fill(child: _ControlsScrim()),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      _IconButton(
                        icon: Icons.arrow_back_ios_new_rounded,
                        onTap: _exit,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        flex: 2,
                        child: Text(
                          _episodeTitle(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            shadows: _kControlShadow,
                          ),
                        ),
                      ),
                      // The action set outgrows a portrait phone. It used to
                      // take half the bar and scroll the surplus off the left,
                      // where nobody found it — orientation and Watch Party were
                      // simply invisible. Now the actions get the larger share
                      // and scale a few percent if they still do not fit, so
                      // every one of them is on screen.
                      Expanded(
                        flex: 5,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (hasLangSwitcher) ...[
                                _LangPill(
                                  label: (_currentLang ?? _kSubLang).toUpperCase(),
                                  onTap: _openLangSheet,
                                ),
                                const SizedBox(width: 8),
                              ],
                              // CloudStream (cs:) sources are excluded from Watch2Gether
                              // for now (they need an on-device plugin per peer).
                              if (_inParty || !widget.args.provider.startsWith('cs:')) ...[
                                _IconButton(
                                  icon: _inParty
                                      ? Icons.groups_rounded
                                      : Icons.groups_2_outlined,
                                  color: _inParty ? AppColors.primary : null,
                                  onTap: _openWatchParty,
                                ),
                                const SizedBox(width: 8),
                              ],
                              // TV drops three phone-only affordances outright rather
                              // than adapting them: orientation lock is meaningless on
                              // a fixed landscape panel, PiP semantics differ on
                              // leanback, and the touch lock swaps in an overlay whose
                              // only escape is a non-focusable tap target — on a remote
                              // that is an unrecoverable state.
                              if (isTvPlatform) ...[
                                _IconButton(
                                  icon: Icons.subtitles_outlined,
                                  onTap: _openSubtitleSheet,
                                ),
                                const SizedBox(width: 8),
                                if (canDownload) ...[
                                  _IconButton(
                                    icon: Icons.download_rounded,
                                    onTap: _startDownload,
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                _IconButton(
                                  icon: Icons.settings_outlined,
                                  onTap: _openSettingsSheet,
                                ),
                                if (hasServers) ...[
                                  const SizedBox(width: 8),
                                  _IconButton(
                                    icon: Icons.dns_outlined,
                                    onTap: _openServerSheet,
                                  ),
                                ],
                                if (hasQualities) ...[
                                  const SizedBox(width: 8),
                                  _IconButton(
                                    icon: Icons.high_quality_rounded,
                                    onTap: () => _openPanel(_SidePanel.quality),
                                  ),
                                ],
                                if (hasEpisodes) ...[
                                  const SizedBox(width: 8),
                                  _IconButton(
                                    icon: Icons.video_library_rounded,
                                    onTap: () => _openPanel(_SidePanel.episodes),
                                  ),
                                ],
                              ] else if (!isDesktopPlatform) ...[
                                _IconButton(
                                  icon: _isPortrait
                                      ? Icons.screen_lock_landscape_rounded
                                      : Icons.screen_lock_portrait_rounded,
                                  onTap: _toggleOrientation,
                                ),
                                const SizedBox(width: 6),
                                if (!_isPortrait) ...[
                                  _IconButton(
                                    icon: Icons.lock_outline_rounded,
                                    onTap: () => setState(() {
                                      _locked = true;
                                      _controlsVisible = false;
                                      _controlsAnimation.reverse();
                                      _hideTimer?.cancel();
                                    }),
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                _IconButton(
                                  icon: Icons.picture_in_picture_alt_rounded,
                                  onTap: _enterPip,
                                ),
                                const SizedBox(width: 6),
                                if (canDownload) ...[
                                  _IconButton(
                                    icon: Icons.download_rounded,
                                    onTap: _startDownload,
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                _IconButton(
                                  icon: Icons.settings_outlined,
                                  onTap: _openSettingsSheet,
                                ),
                                const SizedBox(width: 6),
                                // Quality and episodes used to share one slot,
                                // so on a serial the quality panel was
                                // unreachable, and with neither available the
                                // HQ icon opened Settings — a button that says
                                // one thing and does another.
                                if (hasQualities) ...[
                                  _IconButton(
                                    icon: Icons.high_quality_rounded,
                                    onTap: () => _openPanel(_SidePanel.quality),
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                if (hasEpisodes)
                                  _IconButton(
                                    icon: Icons.video_library_rounded,
                                    onTap: () => _openPanel(_SidePanel.episodes),
                                  ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      if (isDesktopPlatform)
                        ValueListenableBuilder<bool>(
                          valueListenable: DesktopWindow.immersive,
                          builder: (_, imm, _) => imm
                              ? const WindowButtons()
                              : const SizedBox.shrink(),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (initialized && !isDesktopPlatform) _buildCenterPlayCluster(c),
            if (initialized)
              _buildBottomBar(c, hasEpisodes, hasServers, hasQualities),
          ],
        ),
      ),
    );

    // IgnorePointer stops taps but leaves every button focusable, so on a
    // D-pad an invisible control would still take focus and fire on OK.
    final gated = isTvPlatform
        ? ExcludeFocus(excluding: !_controlsVisible, child: overlay)
        : overlay;

    if (!isBuffering) return gated;
    // A stall while the controls are hidden used to show nothing at all — the
    // spinner lived inside the overlay and faded out with it. This one sits
    // outside the fade and cross-fades against it, so exactly one buffering
    // indicator is on screen: this, or the ring on the play button.
    Widget spinner = const IgnorePointer(
      child: Center(
        child: SizedBox(
          width: 44,
          height: 44,
          child: CircularProgressIndicator(
            color: Colors.white,
            strokeWidth: 2.8,
          ),
        ),
      ),
    );
    if (!isDesktopPlatform) {
      spinner = FadeTransition(
        opacity: ReverseAnimation(_controlsAnimation),
        child: spinner,
      );
    }
    return Stack(fit: StackFit.expand, children: [gated, spinner]);
  }

  Widget _buildCenterPlayCluster(PlayerController c) {
    final step = _seekSeconds;
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CenterIconButton(
            icon: _rewindIconFor(step),
            onTap: () {
              _seekRelative(Duration(seconds: -step));
              _showSeekRipple(-1);
            },
          ),
          const SizedBox(width: 28),
          ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: c,
            builder: (_, value, _) => _CenterIconButton(
              icon: value.isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              onTap: _togglePlay,
              large: true,
              busy: value.isBuffering,
              // Named so the remote can be parked here whenever the overlay
              // reappears; null off TV, i.e. the node is never even created.
              focusNode: isTvPlatform ? _tvPlayFocus : null,
            ),
          ),
          const SizedBox(width: 28),
          _CenterIconButton(
            icon: _forwardIconFor(step),
            onTap: () {
              _seekRelative(Duration(seconds: step));
              _showSeekRipple(1);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopControlRow(
    PlayerController c,
    bool hasEpisodes,
    bool hasServers,
    bool hasQualities,
    bool hasPrev,
    bool hasNext,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: _DesktopVolumeControl(
                volume: _volume,
                onChanged: _setPlayerVolume,
                onToggleMute: _toggleMute,
              ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasEpisodes) ...[
                _IconButton(
                  icon: Icons.skip_previous_rounded,
                  onTap: () {
                    if (_episodeIndex - 1 >= 0) {
                      _partyEpisodeNav(_episodeIndex - 1);
                    }
                  },
                ),
                const SizedBox(width: 4),
              ],
              _IconButton(
                icon: _rewindIconFor(_seekSeconds),
                onTap: () {
                  _seekRelative(-_seekStep);
                  _showSeekRipple(-1);
                },
              ),
              const SizedBox(width: 6),
              ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: c,
                builder: (_, value, _) => _IconButton(
                  icon: value.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  onTap: _togglePlay,
                ),
              ),
              const SizedBox(width: 6),
              _IconButton(
                icon: _forwardIconFor(_seekSeconds),
                onTap: () {
                  _seekRelative(_seekStep);
                  _showSeekRipple(1);
                },
              ),
              if (hasEpisodes) ...[
                const SizedBox(width: 4),
                _IconButton(
                  icon: Icons.skip_next_rounded,
                  onTap: () {
                    if (_episodeIndex + 1 < widget.args.episodes.length) {
                      _partyEpisodeNav(_episodeIndex + 1);
                    }
                  },
                ),
              ],
            ],
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _BottomTextButton(
                      icon: Icons.speed_rounded,
                      label:
                          '${_playbackSpeed.toStringAsFixed(_playbackSpeed == _playbackSpeed.roundToDouble() ? 0 : 2)}x',
                      enabled: true,
                      onTap: _openSpeedSheet,
                    ),
                    _IconButton(
                      icon: Icons.subtitles_outlined,
                      onTap: _openSubtitleSheet,
                    ),
                    const SizedBox(width: 4),
                    _IconButton(
                      icon: Icons.settings_outlined,
                      onTap: _openSettingsSheet,
                    ),
                    if (hasServers) ...[
                      const SizedBox(width: 4),
                      _IconButton(
                        icon: Icons.dns_outlined,
                        onTap: _openServerSheet,
                      ),
                    ],
                    if (hasQualities) ...[
                      const SizedBox(width: 4),
                      _IconButton(
                        icon: Icons.high_quality_rounded,
                        onTap: () => _openPanel(_SidePanel.quality),
                      ),
                    ],
                    if (hasEpisodes) ...[
                      const SizedBox(width: 4),
                      _IconButton(
                        icon: Icons.video_library_rounded,
                        onTap: () => _openPanel(_SidePanel.episodes),
                      ),
                    ],
                    const SizedBox(width: 4),
                    _IconButton(
                      icon: _isFullscreen
                          ? Icons.fullscreen_exit_rounded
                          : Icons.fullscreen_rounded,
                      onTap: _toggleFullscreen,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Keeps the elapsed label as wide as the total one, so the bar does not jump
  /// sideways the moment playback crosses an hour.
  String _positionLabel(Duration position, Duration total) =>
      total.inHours > 0 && position.inHours == 0
          ? '00:${_formatDuration(position)}'
          : _formatDuration(position);

  /// End of the buffered range covering the playhead, or null when the engine
  /// reports no ranges (media_kit does not publish them).
  double? _bufferedMs(VideoPlayerValue value, double maxMs) {
    final position = value.position.inMilliseconds;
    var end = -1;
    for (final range in value.buffered) {
      if (range.start.inMilliseconds <= position &&
          range.end.inMilliseconds > end) {
        end = range.end.inMilliseconds;
      }
    }
    return end < 0 ? null : end.toDouble().clamp(0.0, maxMs);
  }

  Widget? _buildScrubPreviewCard(Duration position) {
    final thumb = _thumbnailAt(position);
    final Widget? image = thumb != null
        ? _buildThumbnailImage(thumb)
        : _canGeneratePreview
            ? _GeneratedFramePreview(
                url: _videoUrl!,
                headers: _headers,
                positionMs: position.inMilliseconds,
              )
            : null;
    if (image == null) return null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(borderRadius: BorderRadius.circular(6), child: image),
        const SizedBox(height: 4),
        Text(
          _formatDuration(position),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            shadows: _kControlShadow,
          ),
        ),
      ],
    );
  }

  /// The seek bar, with the scrub preview floating above it.
  ///
  /// The preview is positioned out of the bar's own box instead of being a
  /// sibling in the column: as a sibling it grew the bottom bar and shoved the
  /// whole thing upward the instant a drag began — out from under the finger
  /// holding the thumb. Measuring inside the bar's box also lines the popup up
  /// with the thumb, which the previous guess at the label widths did not.
  Widget _buildSeekBar({
    required VideoPlayerValue value,
    required double sliderVal,
    required double maxMs,
    required bool scrubbing,
    required Duration previewPosition,
  }) {
    final Widget bar = isTvPlatform
        ? _TvSeekBar(
            focusNode: _tvSeekFocus,
            positionMs: sliderVal,
            durationMs: maxMs,
            scrubbing: scrubbing,
          )
        : SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              activeTrackColor: AppColors.primary,
              inactiveTrackColor: Colors.white24,
              secondaryActiveTrackColor: Colors.white38,
              thumbColor: Colors.white,
              overlayColor: AppColors.primary.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: sliderVal,
              min: 0,
              max: maxMs,
              secondaryTrackValue: _bufferedMs(value, maxMs),
              onChangeStart: (v) {
                _sliderDragValue.value = v;
                _hideTimer?.cancel();
              },
              onChanged: (v) {
                _sliderDragValue.value = v;
                _hideTimer?.cancel();
              },
              onChangeEnd: (v) {
                final target = Duration(milliseconds: v.toInt());
                _seekTo(target);
                _clearDragAfterSeek(target);
              },
            ),
          );

    final preview = scrubbing && (_hasThumbnails || _canGeneratePreview)
        ? _buildScrubPreviewCard(previewPosition)
        : null;

    // The wrapper is unconditional: swapping it in when the preview appears
    // would rebuild the slider mid-drag and drop the gesture.
    return LayoutBuilder(
      builder: (context, box) {
        const previewWidth = 160.0;
        // Each bar insets its track by its own overlay allowance.
        final inset = isTvPlatform ? 24.0 : 16.0;
        final track = (box.maxWidth - inset * 2).clamp(0.0, double.infinity);
        final fraction = maxMs > 0 ? (sliderVal / maxMs).clamp(0.0, 1.0) : 0.0;
        final left = (inset + fraction * track - previewWidth / 2).clamp(
          0.0,
          (box.maxWidth - previewWidth).clamp(0.0, double.infinity),
        );
        return Stack(
          clipBehavior: Clip.none,
          children: [
            bar,
            if (preview != null)
              Positioned(left: left, bottom: 46, child: preview),
          ],
        );
      },
    );
  }

  Widget _buildBottomBar(
    PlayerController c,
    bool hasEpisodes,
    bool hasServers,
    bool hasQualities,
  ) {
    final hasNext =
        hasEpisodes && _episodeIndex + 1 < widget.args.episodes.length;
    final hasPrev = hasEpisodes && _episodeIndex - 1 >= 0;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<double?>(
                valueListenable: _sliderDragValue,
                builder: (_, dragVal, _) {
                  return ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: c,
                    builder: (_, value, _) {
                      if (_isLive) return _buildLiveBar();
                      final duration = value.duration.inMilliseconds == 0
                          ? Duration.zero
                          : value.duration;
                      final maxMs = duration.inMilliseconds
                          .toDouble()
                          .clamp(1.0, double.infinity);
                      final sliderVal = dragVal ??
                          (duration.inMilliseconds == 0
                              ? 0.0
                              : value.position.inMilliseconds
                                    .clamp(0, duration.inMilliseconds)
                                    .toDouble());
                      final displayPos = dragVal != null
                          ? Duration(milliseconds: dragVal.toInt())
                          : value.position;

                      return Row(
                        children: [
                          Text(
                            _positionLabel(displayPos, duration),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              shadows: _kControlShadow,
                            ),
                          ),
                          Expanded(
                            child: _buildSeekBar(
                              value: value,
                              sliderVal: sliderVal.clamp(0.0, maxMs),
                              maxMs: maxMs,
                              scrubbing: dragVal != null,
                              previewPosition: displayPos,
                            ),
                          ),
                          Text(
                            _formatDuration(duration),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              shadows: _kControlShadow,
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 4),
              if (isDesktopPlatform)
                _buildDesktopControlRow(
                    c, hasEpisodes, hasServers, hasQualities, hasPrev, hasNext)
              else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    if (hasEpisodes)
                      _BottomTextButton(
                        icon: Icons.skip_previous_rounded,
                        label: 'player.previous'.tr(),
                        enabled: hasPrev,
                        onTap: () => _partyEpisodeNav(_episodeIndex - 1),
                      ),
                    if (hasEpisodes)
                      _BottomTextButton(
                        icon: Icons.skip_next_rounded,
                        label: 'general.next'.tr(),
                        enabled: hasNext,
                        onTap: () => _partyEpisodeNav(_episodeIndex + 1),
                      ),
                    _BottomTextButton(
                      icon: Icons.speed_rounded,
                      label:
                          '${_playbackSpeed.toStringAsFixed(_playbackSpeed == _playbackSpeed.roundToDouble() ? 0 : 2)}x',
                      enabled: true,
                      onTap: _openSpeedSheet,
                    ),
                    if (hasServers)
                      _BottomTextButton(
                        icon: Icons.dns_outlined,
                        label: _currentServer ?? '—',
                        enabled: true,
                        onTap: _openServerSheet,
                      ),
                    if (hasQualities)
                      _BottomTextButton(
                        icon: Icons.high_quality_rounded,
                        label: _currentQuality == null
                            ? 'player.quality'.tr()
                            : _qualityLabel(_currentQuality!),
                        enabled: true,
                        onTap: () => _openPanel(_SidePanel.quality),
                      ),
                    if (hasEpisodes)
                      _BottomTextButton(
                        icon: Icons.list_rounded,
                        label: 'player.episodes'.tr(),
                        enabled: true,
                        onTap: () => _openPanel(_SidePanel.episodes),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLiveBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const _LiveDot(),
          const SizedBox(width: 7),
          Text(
            'player.live'.tr(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
            ),
          ),
          const Spacer(),
          _BottomTextButton(
            icon: Icons.fiber_manual_record_rounded,
            label: 'player.go_live'.tr(),
            enabled: true,
            onTap: () {
              final c = _controller;
              if (c == null || !c.value.isInitialized) return;
              final end = c.value.duration;
              if (end > Duration.zero) _seekTo(end);
              c.play();
            },
          ),
        ],
      ),
    );
  }
}
