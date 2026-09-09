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
    // The value the bar is currently pinned to. It is NOT
    // target.inMilliseconds: Slider has no divisions, so onChanged hands back
    // lerpDouble(0, maxMs, t) — a fractional double like 1234567.89 — while
    // target was built with v.toInt(). Comparing the two below never matched,
    // so the one-second fallback almost never fired and a seek that did not
    // land within its listener's 500ms window left the thumb pinned for the
    // rest of the episode.
    final latched = _sliderDragValue.value;
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
      // Nothing is watching the position any more, so leaving the bar pinned
      // has no way back. Cleared unless a NEW drag has started since — that
      // one owns the value now and will schedule its own clear.
      if (_sliderDragValue.value == latched) {
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
      // Never on a torrent. Scrub previews work by opening a SECOND reader on
      // the same URL and seeking it around to grab frames — which is exactly
      // the access pattern a torrent stream cannot serve. The torrent server
      // hands out one sequential reader with a read-ahead buffer in front of
      // it; a second one seeking backwards and forwards thrashes that buffer,
      // starves the player, and on a real device took the whole process down
      // mid-episode.
      TorrentStreamUrl.parse(_videoUrl) == null &&
      (!_isHls || Platform.isIOS);

  Widget _buildVideoLayer() {
    if (_initializing) {
      return ColoredBox(
        color: Colors.black,
        child: _LoadingOverlay(
          stage: _stage,
          title: _episodeTitle(),
          serverSwitch: _serverSwitch,
        ),
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
                // Offered on every playback failure, not only on the ones we
                // can name. A source that has moved domain, minted a token the
                // CDN now refuses, or simply lost the episode fails in a dozen
                // different ways, and from the viewer's chair they are one
                // problem: this show will not play here. The answer is the same
                // in all of them.
                if (!_isLive && !(_inParty && !_isPartyHost)) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _openAlternateSources,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                    ),
                    icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                    label: Text('player.alt_sources'.tr()),
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
        // Clipped, so a zoomed frame stays inside the video box and never
        // paints under the controls or the subtitles. At 1.0 Transform.scale is
        // an identity and costs nothing, so there is no branch for it.
        child: ClipRect(
          child: Transform.scale(
            scale: _videoZoom,
            filterQuality: FilterQuality.medium,
            child: _FittedVideo(controller: c, fit: _fit),
          ),
        ),
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
        // Zoom is a scale factor over the whole picture, so it belongs in the
        // middle as a number — not on an edge as a 0-1 bar like the two
        // level controls.
        if (indicator.type == _SwipeType.zoom) {
          return Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.zoom_out_map_rounded,
                          color: Colors.white, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        '${(indicator.value * 100).round()}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
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
    final a = _affordances;
    final hasEpisodes = a.hasEpisodes;
    final hasServers = a.hasServers;
    final hasQualities = a.hasQualities;
    final hasLangSwitcher = a.hasLangs;
    final canDownload = a.canDownload;
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
                      const SizedBox(width: 3),
                      Expanded(
                        flex: 2,
                        // Text takes the hit but has no gesture, so a tap on
                        // the title did nothing while the same tap anywhere
                        // else on the dimmed video hides the controls.
                        child: IgnorePointer(
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
                                const SizedBox(width: 5),
                              ],
                              // CloudStream (cs:) sources are excluded from Watch2Gether
                              // for now (they need an on-device plugin per peer).
                              //
                              if ((isTvPlatform || isDesktopPlatform) &&
                                  (_inParty ||
                                      !widget.args.provider.startsWith('cs:'))) ...[
                                _IconButton(
                                  icon: _inParty
                                      ? Icons.groups_rounded
                                      : Icons.groups_2_outlined,
                                  color: _inParty ? AppColors.primary : null,
                                  onTap: _openWatchParty,
                                ),
                                const SizedBox(width: 2),
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
                                const SizedBox(width: 2),
                                if (canDownload) ...[
                                  _IconButton(
                                    icon: Icons.download_rounded,
                                    onTap: _startDownload,
                                  ),
                                  const SizedBox(width: 2),
                                ],
                                _IconButton(
                                  icon: Icons.settings_outlined,
                                  onTap: _openSettingsSheet,
                                ),
                                if (hasServers) ...[
                                  const SizedBox(width: 2),
                                  _IconButton(
                                    icon: Icons.dns_outlined,
                                    onTap: _openServerSheet,
                                  ),
                                ],
                                if (hasQualities) ...[
                                  const SizedBox(width: 2),
                                  _IconButton(
                                    icon: Icons.high_quality_rounded,
                                    onTap: () => _openPanel(_SidePanel.quality),
                                  ),
                                ],
                                if (hasEpisodes) ...[
                                  const SizedBox(width: 2),
                                  _IconButton(
                                    icon: Icons.video_library_rounded,
                                    onTap: () => _openPanel(_SidePanel.episodes),
                                  ),
                                ],
                              ] else if (!isDesktopPlatform) ...[
                                // Phone: the viewer's arrangement, in their
                                // order. Every control stays ON a bar — a
                                // previous pass filed six of them behind a ⋯
                                // sheet to buy room and had to undo it, because
                                // a control one tap away is a control people
                                // use and one two taps away is a control they
                                // stop reaching for. What changed is only that
                                // WHICH controls sit here is now a preference
                                // instead of an argument about a Row.
                                //
                                // The capacity that PlayerControlsLayout
                                // enforces is this bar's: the group is wrapped
                                // in a FittedBox, so an extra button does not
                                // wrap or scroll, it shrinks all of them.
                                ..._controlsFor(
                                  PlayerControlSlot.topBar,
                                  topBar: true,
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
                    if (_hasNextEpisode) {
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
  /// Stops the page-wide gestures firing on a touch that starts on a control.
  ///
  /// The whole player sits under one GestureDetector, so a press on the seek
  /// bar also reached the 2x speed boost: scrubbing quietly doubled playback
  /// speed. For the same gesture type the INNERMOST recogniser wins the arena,
  /// so declaring an empty long-press here keeps the outer one out of it.
  ///
  /// Measured rather than assumed: hold-then-drag on the thumb delivers
  /// longPresses=1 seeks=1 without this and longPresses=0 seeks=1 with it — the
  /// drag was never the casualty, the speed boost was the intruder.
  ///
  /// deferToChild, so the slider keeps its own hit area exactly.
  Widget _absorbAncestorGestures(Widget child) => GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onLongPressStart: (_) {},
        onLongPressEnd: (_) {},
        child: child,
      );

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
        : _absorbAncestorGestures(SliderTheme(
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
          ));

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

  /// Portrait phones render the bottom row icon-only.
  ///
  /// Landscape and desktop have the width for labels, and the value-carrying
  /// ones — speed, server, quality — are worth reading there. Portrait does
  /// not: with labels the row wants roughly 426pt against roughly 361pt of bar,
  /// so its tail sat past the right edge of a scroll view with no scrollbar.
  /// Dropping the labels is what lets the rarely-used icons live down here
  /// instead of crowding the title out of the top bar.
  bool get _compactBottomBar =>
      _isPortrait && !isTvPlatform && !isDesktopPlatform;

  // ── the bars, built from the viewer's arrangement ──────────────────────────
  //
  // Phone only. A television's top bar is where the D-pad lands first and a
  // desktop window has its own row, so both keep the arrangement they were
  // built with — an editor shaped like a phone must not govern them.
  //
  // Layout answers WHERE a control goes. It does not answer whether the control
  // can exist: a film has no episodes, a device without shader support has no
  // Anime4K, a `cs:` provider cannot join a party. Those are affordances, they
  // are checked here, and a control that fails one renders nothing rather than
  // an inert button. See PlayerControlsLayout's own note on the distinction.

  /// Whether the viewer's arrangement drives the bars on this platform.
  bool get _layoutDrivesBars => !isTvPlatform && !isDesktopPlatform;

  /// One control as it appears on the TOP bar: a bare icon, no label.
  Widget? _topBarControl(String id) {
    final a = _affordances;
    switch (id) {
      case 'language':
        if (!a.hasLangs) return null;
        // Its own gap: every other control on this bar is an _IconButton, whose
        // 44pt tap target already carries 3pt of transparent padding a side.
        // The pill has none, so without this it sits flush against its
        // neighbour.
        return Padding(
          padding: const EdgeInsets.only(right: 5),
          child: _LangPill(
            label: (_currentLang ?? _kSubLang).toUpperCase(),
            onTap: _openLangSheet,
          ),
        );
      case 'subtitles':
        return _IconButton(
          icon: Icons.subtitles_outlined,
          onTap: _openSubtitleSheet,
        );
      case 'settings':
        return _IconButton(
          icon: Icons.settings_outlined,
          onTap: _openSettingsSheet,
        );
      case 'orientation':
        return _IconButton(
          icon: _isPortrait
              ? Icons.screen_lock_landscape_rounded
              : Icons.screen_lock_portrait_rounded,
          onTap: _toggleOrientation,
        );
      case 'lock':
        // Portrait only ever had one way out of the lock overlay and it is a
        // tap target the D-pad cannot reach; the button is landscape-only for
        // that reason, not for room.
        if (_isPortrait) return null;
        return _IconButton(
          icon: Icons.lock_outline_rounded,
          onTap: () => setState(() {
            _locked = true;
            _controlsVisible = false;
            _controlsAnimation.reverse();
            _hideTimer?.cancel();
          }),
        );
      case 'stats':
        return _IconButton(
          icon: Icons.info_outline_rounded,
          color: _showPlayerInfo ? AppColors.primary : null,
          onTap: () => setState(() => _showPlayerInfo = !_showPlayerInfo),
        );
      case 'speed':
        return _IconButton(icon: Icons.speed_rounded, onTap: _openSpeedSheet);
      case 'server':
        if (!a.hasServers) return null;
        return _IconButton(icon: Icons.dns_outlined, onTap: _openServerSheet);
      case 'quality':
        if (!a.hasQualities) return null;
        return _IconButton(
          icon: Icons.high_quality_rounded,
          onTap: () => _openPanel(_SidePanel.quality),
        );
      case 'episodes':
        if (!a.hasEpisodes) return null;
        return _IconButton(
          icon: Icons.video_library_rounded,
          onTap: () => _openPanel(_SidePanel.episodes),
        );
      case 'previous':
        if (!a.hasEpisodes) return null;
        return _IconButton(
          icon: Icons.skip_previous_rounded,
          enabled: _hasPrevEpisode,
          onTap: () => _partyEpisodeNav(_episodeIndex - 1),
        );
      case 'next':
        if (!a.hasEpisodes) return null;
        return _IconButton(
          icon: Icons.skip_next_rounded,
          enabled: _hasNextEpisode,
          onTap: () => _partyEpisodeNav(_episodeIndex + 1),
        );
      case 'shader':
        if (!(_controller?.supportsShaders ?? false)) return null;
        return _IconButton(
          icon: Icons.auto_awesome_rounded,
          color: _shaderPreset.isOff ? null : AppColors.primary,
          onTap: _openShaderSheet,
        );
      case 'fit':
        return _IconButton(
          icon: Icons.aspect_ratio_rounded,
          onTap: _openFitSheet,
        );
      case 'sleep':
        if (_isLive) return null;
        return _IconButton(icon: Icons.bedtime_outlined, onTap: _openSleepSheet);
      case 'cast':
        if (!_canCast) return null;
        return _IconButton(
          icon: Icons.cast_rounded,
          color: _cast.isCasting ? AppColors.primary : null,
          onTap: _openCastSheet,
        );
      case 'party':
        // CloudStream sources need an on-device plugin per peer, so they are
        // out of Watch2Gether until every peer can resolve them.
        if (!_inParty && widget.args.provider.startsWith('cs:')) return null;
        return _IconButton(
          icon: _inParty ? Icons.groups_rounded : Icons.groups_2_outlined,
          color: _inParty ? AppColors.primary : null,
          onTap: _openWatchParty,
        );
      case 'pip':
        // `floating: ^6.0.0` ships an Android plugin and nothing else, and
        // _enterPip swallows the MissingPluginException, so on iOS this was a
        // tap that did nothing.
        if (!isAndroidPlatform) return null;
        return _IconButton(
          icon: Icons.picture_in_picture_alt_rounded,
          onTap: _enterPip,
        );
      case 'download':
        if (!a.canDownload) return null;
        return _IconButton(
          icon: Icons.download_rounded,
          onTap: _startDownload,
        );
    }
    return null;
  }

  /// One control as it appears on the BOTTOM row.
  ///
  /// Labelled where the label carries live state the icon cannot — the current
  /// server, the resolved quality, the speed, the sleep countdown. Everything
  /// else falls back to the same icon the top bar uses, so a control keeps its
  /// identity wherever the viewer puts it.
  Widget? _bottomControl(String id) {
    final a = _affordances;
    final compact = _compactBottomBar;
    switch (id) {
      case 'previous':
        if (!a.hasEpisodes) return null;
        return _BottomTextButton(
          icon: Icons.skip_previous_rounded,
          label: 'player.previous'.tr(),
          compact: compact,
          enabled: _hasPrevEpisode,
          onTap: () => _partyEpisodeNav(_episodeIndex - 1),
        );
      case 'next':
        if (!a.hasEpisodes) return null;
        return _BottomTextButton(
          icon: Icons.skip_next_rounded,
          label: 'general.next'.tr(),
          compact: compact,
          enabled: _hasNextEpisode,
          onTap: () => _partyEpisodeNav(_episodeIndex + 1),
        );
      case 'speed':
        return _BottomTextButton(
          icon: Icons.speed_rounded,
          label:
              '${_playbackSpeed.toStringAsFixed(_playbackSpeed == _playbackSpeed.roundToDouble() ? 0 : 2)}x',
          compact: compact,
          enabled: true,
          onTap: _openSpeedSheet,
        );
      case 'server':
        if (isTvPlatform || !a.hasServers) return null;
        return _BottomTextButton(
          icon: Icons.dns_outlined,
          label: _currentServer ?? '—',
          compact: compact,
          enabled: true,
          onTap: _openServerSheet,
        );
      case 'quality':
        if (isTvPlatform || !a.hasQualities) return null;
        return _BottomTextButton(
          icon: Icons.high_quality_rounded,
          label: _currentQuality == null
              ? 'player.quality'.tr()
              : _qualityLabel(_currentQuality!),
          compact: compact,
          enabled: true,
          onTap: () => _openPanel(_SidePanel.quality),
        );
      case 'episodes':
        if (isTvPlatform || !a.hasEpisodes) return null;
        return _BottomTextButton(
          icon: Icons.list_rounded,
          label: 'player.episodes'.tr(),
          compact: compact,
          enabled: true,
          onTap: () => _openPanel(_SidePanel.episodes),
        );
      case 'shader':
        if (!_roomForExtras) return null;
        if (!(_controller?.supportsShaders ?? false)) return null;
        return _BottomTextButton(
          icon: Icons.auto_awesome_rounded,
          label: _shaderPreset.isOff
              ? 'general.off'.tr()
              : _shaderPreset.labelKey.tr(),
          enabled: true,
          onTap: _openShaderSheet,
        );
      case 'fit':
        if (!_roomForExtras) return null;
        return _BottomTextButton(
          icon: Icons.aspect_ratio_rounded,
          label: _fitLabel(_fit),
          enabled: true,
          onTap: _openFitSheet,
        );
      case 'sleep':
        if (!_roomForExtras || _isLive) return null;
        return _BottomTextButton(
          icon: Icons.bedtime_outlined,
          label: _sleepValueLabel,
          enabled: true,
          onTap: _openSleepSheet,
        );
      case 'party':
      case 'pip':
      case 'download':
        // Phone only in this row: a television reaches all three from its own
        // top bar, and rendering them here as well is the duplication the
        // `&& !isTvPlatform` guards used to prevent.
        if (isTvPlatform || isDesktopPlatform) return null;
        return _topBarControl(id);
      default:
        // No live value to print, so the icon form is the honest one and the
        // top bar already builds it.
        return _topBarControl(id);
    }
  }

  /// The controls for [slot], in the viewer's order, minus the ones that cannot
  /// exist right now.
  List<Widget> _controlsFor(
    PlayerControlSlot slot, {
    required bool topBar,
  }) {
    // A television's top bar is where the D-pad lands first and a desktop
    // window has its own row; the editor is a phone screen and must not govern
    // either. They render the shipped arrangement instead — which is also why
    // the defaults are worth keeping correct rather than treating as a seed.
    final layout =
        _layoutDrivesBars ? _layout : PlayerControlsLayout.defaults();
    final out = <Widget>[];
    for (final id in layout.of(slot)) {
      final w = topBar ? _topBarControl(id) : _bottomControl(id);
      if (w != null) out.add(w);
    }
    return out;
  }

  /// A landscape phone has room the portrait one does not, so it shows more.
  ///
  /// Aspect, sleep timer and cast are playback-time decisions — you make them
  /// while watching, not before — but they lived only in the settings sheet,
  /// two taps deep, on the surface with the most spare width in the app. In
  /// portrait they stay in the sheet, where the row has no room for them.
  bool get _roomForExtras =>
      !isTvPlatform && !isDesktopPlatform && !_isPortrait;

  /// The live readout, or nothing when it is switched off.
  ///
  /// Rebuilt from the controller's own notifier so the buffer and position
  /// rows move; everything else on the panel is steady between loads.
  Widget _buildPlayerInfoOverlay() {
    if (!_showPlayerInfo) return const SizedBox.shrink();
    final c = _controller;
    if (c == null) return const SizedBox.shrink();
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: c,
      builder: (_, value, _) {
        final source =
            _currentSourceIndex >= 0 && _currentSourceIndex < _videoSources.length
                ? _videoSources[_currentSourceIndex]
                : null;
        final buffered = value.buffered.isEmpty
            ? Duration.zero
            : value.buffered.last.end;
        return _PlayerInfoOverlay(
          rows: PlaybackReadout.rows(
            videoWidth: value.size.width.round(),
            videoHeight: value.size.height.round(),
            position: value.position,
            duration: value.duration,
            bufferedTo: buffered,
            playbackSpeed: value.playbackSpeed,
            isLive: _isLive,
            isBuffering: value.isBuffering,
            engineId: resolvePlayerEngine().id,
            providerId: widget.args.provider,
            serverLabel: _currentServer,
            mediaType: _mediaType,
            source: source,
            streamUrl: _videoUrl,
            fields: _infoFields,
          ),
          onClose: () => setState(() => _showPlayerInfo = false),
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
        hasEpisodes && _hasNextEpisode;
    final hasPrev = hasEpisodes && _hasPrevEpisode;

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
                          IgnorePointer(
                            child: Text(
                              _positionLabel(displayPos, duration),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                shadows: _kControlShadow,
                              ),
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
                          IgnorePointer(
                            child: Text(
                              _formatDuration(duration),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                shadows: _kControlShadow,
                              ),
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
              // Transport left, everything else right — the split
              // _buildDesktopControlRow has always had. This row used to be a
              // bare Row in a horizontal scroll view, so on a 844pt landscape
              // phone six buttons sat in the leftmost 540pt and the remaining
              // third of the bar was empty; on a 1280pt television three
              // buttons used a fifth of it. The ConstrainedBox is what makes
              // the split possible without giving up the scroll: it floors the
              // row at the viewport width so spaceBetween has slack to
              // distribute, while maxWidth stays unbounded so a narrow screen
              // with long labels still scrolls instead of overflowing. Spacer
              // and Expanded cannot be used here for exactly that reason —
              // they throw against an unbounded main axis.
              Builder(builder: (context) {
                final left = _controlsFor(
                  PlayerControlSlot.bottomLeft,
                  topBar: false,
                );
                final right = _controlsFor(
                  PlayerControlSlot.bottomRight,
                  topBar: false,
                );
                return LayoutBuilder(
                  builder: (context, box) => SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: box.maxWidth),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      // spaceBetween only makes sense with something on BOTH
                      // sides. The left group is the transport pair and it
                      // exists only on a serial, so on a film it was empty and
                      // every remaining control ended up pinned to the right
                      // edge with the whole width blank beside it. Emptiness is
                      // now read off the built widgets rather than guessed from
                      // hasEpisodes: the viewer can move Previous and Next out
                      // of that group entirely, and can move other controls in.
                      mainAxisAlignment: left.isEmpty
                          ? MainAxisAlignment.start
                          : MainAxisAlignment.spaceBetween,
                      children: [
                        Row(mainAxisSize: MainAxisSize.min, children: left),
                        Row(mainAxisSize: MainAxisSize.min, children: right),
                      ],
                    ),
                  ),
                  ),
                );
              }),
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
          // Only when the channel is identified — a live stream reached any
          // other way has no guide to ask for.
          if ((widget.args.liveChannelId ?? '').isNotEmpty) ...[
            _BottomTextButton(
              icon: Icons.calendar_month_rounded,
              label: 'player.guide'.tr(),
              enabled: true,
              onTap: () => LiveGuideSheet.show(
                context,
                channelId: widget.args.liveChannelId!,
                channelName: widget.args.title,
              ),
            ),
            const SizedBox(width: 6),
          ],
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
