// ignore_for_file: invalid_use_of_protected_member
part of 'player_page.dart';

extension _PlayerPanels on _PlayerPageState {
  /// Opens the info-row picker over the player.
  ///
  /// The overlay is switched on as it opens: a checklist whose effect is
  /// invisible is a checklist people tick at random. `onChanged` then re-renders
  /// behind the sheet, so each tap shows its own result.
  void _openInfoFieldsPicker() {
    if (!_showPlayerInfo) setState(() => _showPlayerInfo = true);
    PlayerInfoFieldsSheet.show(
      context,
      onChanged: (next) {
        if (!mounted) return;
        setState(() => _infoFields = next);
      },
    );
  }

  /// Opens the bar editor. The layout is re-read on return rather than pushed
  /// back through a result, because the page saves on every edit and a viewer
  /// who backs out has still made those edits.
  Future<void> _openControlsLayoutPage() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const PlayerControlsPage()),
    );
    if (!mounted) return;
    setState(() {
      _layout = PlayerControlsLayout.fromStored(_hive.getPlayerControlsLayout());
    });
  }

  String _langLabel(String lang) {
    switch (lang.toLowerCase()) {
      case _kSubLang:
        return 'player.lang_sub'.tr();
      case _kDubLang:
        return 'player.lang_dub'.tr();
      case 'softsub':
        return 'player.lang_softsub'.tr();
      default:
        return lang.toUpperCase();
    }
  }

  void _openLangSheet() {
    final langs = _availableLangsForCurrentEpisode();
    if (langs.isEmpty) return;
    showAdaptiveModal<void>(
      context: context,
      backgroundColor: const Color(0xFF111111),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.translate_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'player.audio_language'.tr(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white12, height: 1),
              for (final l in langs)
                _OptionTile(
                  label: _langLabel(l),
                  selected: l == _currentLang,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _switchLang(l);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  List<String> get _sourceLabels => [for (final s in _videoSources) s.quality];

  List<String> get _sourceServers => VideoOptionGroups.servers(_sourceLabels);

  /// The host currently playing, or null before the first source resolves.
  ///
  /// Nullable on purpose: serverOf('') answers with the "Default" placeholder,
  /// which the bar and the settings sheet were painting as if it were a real
  /// host name.
  String? get _currentServer {
    final quality = _currentQuality;
    if (quality == null) return null;
    return VideoOptionGroups.serverOf(quality);
  }

  /// Positions in [_videoSources] the current server offers.
  /// What applies right now, derived once and read by both the overlay and the
  /// settings sheet. See [PlayerAffordances] for what the two copies of this
  /// used to disagree about.
  PlayerAffordances get _affordances => PlayerAffordances(
        isSerial: widget.args.isSerial,
        episodeCount: _episodes.length,
        serverCount: _sourceServers.length,
        serverSourceCount: _currentServerSources.length,
        engineTrackCount: _engineVideoTracks.length,
        langCount: _availableLangsForCurrentEpisode().length,
        showDownloadAction: widget.args.showDownloadAction,
        provider: widget.args.provider,
        hasResolvedUrl: _videoUrl != null,
      );

  /// The qualities of the host currently playing.
  ///
  /// Empty while nothing has resolved, and that is the fix rather than the
  /// gap. This used to fall back to EVERY source across every host on the
  /// grounds that offering everything beat offering nothing. It did not: the
  /// Quality panel renders each row with the server half of its label stripped,
  /// so a cross-host list came out as "DoodStream", "Voe", "Voe MP4" — pressing
  /// Quality showed servers. There is no quality to choose before there is a
  /// stream, and no button is better than a mislabelled one.
  ///
  /// The remaining fallback is narrow and deliberate: a server that matches no
  /// label at all is a bug elsewhere, and hiding every quality would be a
  /// worse failure than listing them.
  /// The renditions inside the stream that is playing, when the engine can
  /// enumerate them.
  ///
  /// This is what "quality" means in every other player: switching between
  /// renditions of ONE stream, which mpv does without a reload. The provider's
  /// mirror list is a different thing — separate URLs on separate hosts, each
  /// switch a teardown and a fresh start — and it is what the panel falls back
  /// to when the engine has nothing to offer, which is always on the platform
  /// player.
  List<PlayerVideoTrack> get _engineVideoTracks {
    final c = _controller;
    if (c == null || !c.supportsVideoTracks) return const [];
    return c.videoTracks;
  }

  Future<void> _switchVideoTrack(PlayerVideoTrack track) async {
    setState(() => _panel = _SidePanel.none);
    await _controller?.setVideoTrack(track.id);
    if (mounted) setState(() {});
  }

  List<int> get _currentServerSources {
    final server = _currentServer;
    if (server == null) return const [];
    final labels = _sourceLabels;
    final indices = VideoOptionGroups.indicesFor(labels, server);
    return indices.isEmpty
        ? [for (var i = 0; i < labels.length; i++) i]
        : indices;
  }

  String _qualityLabel(String label) {
    final quality = VideoOptionGroups.qualityOf(label);
    return quality.isEmpty ? label : quality;
  }

  /// [_QualityRow] paints the label verbatim, and every label in a one-server
  /// list starts with that server's name — so hand it a display-only copy.
  VideoSourceEntity _resolutionOnly(VideoSourceEntity source) =>
      VideoSourceEntity(
        quality: _qualityLabel(source.quality),
        videoUrl: source.videoUrl,
        isDefault: source.isDefault,
        accessible: source.accessible,
      );

  void _openServerSheet() {
    final labels = _sourceLabels;
    final servers = _sourceServers;
    if (servers.length < 2) return;
    showAdaptiveModal<void>(
      context: context,
      backgroundColor: const Color(0xFF111111),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.dns_outlined,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'player.server'.tr(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white12, height: 1),
              for (final server in servers)
                _ServerTile(
                  label: server,
                  qualities: VideoOptionGroups.qualitiesFor(labels, server)
                      .join(' · '),
                  selected: server == _currentServer,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _switchServer(server);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _switchServer(String server) async {
    final labels = _sourceLabels;
    final current =
        _currentQuality == null ? -1 : labels.indexOf(_currentQuality!);
    final target = VideoOptionGroups.switchTo(labels, current, server);
    if (target < 0 || target >= _videoSources.length) return;

    // Recorded before the switch, because _switchQuality tears the old
    // controller down and by the time the overlay builds there is nothing
    // left to ask where we came from.
    _serverSwitch = ServerSwitch(from: _currentServer, to: server);
    try {
      await _switchQuality(_videoSources[target]);
    } finally {
      if (mounted) setState(() => _serverSwitch = null);
    }
  }

  void _openSettingsSheet() {
    final a = _affordances;
    final hasLangs = a.hasLangs;
    showAdaptiveModal<void>(
      context: context,
      backgroundColor: const Color(0xFF111111),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.settings_outlined,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'general.settings'.tr(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white12, height: 1),
              // Switching provider without losing your place.
              //
              // The app carries the same title on several ecosystems at once,
              // and until now the only way to leave a struggling source was to
              // back out and start the episode again somewhere else. Offered
              // here rather than only on the error screen, because a source
              // that is buffering badly has not failed yet — that is exactly
              // when someone wants out, and exactly when they have a position
              // worth keeping.
              //
              // Not for live: a channel is one stream, and there is no other
              // provider carrying the same minute of it.
              if (!_isLive)
                _SettingsTile(
                  icon: Icons.swap_horiz_rounded,
                  label: 'player.change_source'.tr(),
                  value: widget.args.provider,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _openAlternateSources(keepPosition: true);
                  },
                ),
              // Speed, server, quality and subtitles used to sit here as well
              // as on the bar, calling the very same functions. A settings list
              // is where things go when they have nowhere else; those all have
              // a button one tap away, so the copies were padding a list that
              // was already nineteen rows long. Removed, not moved.
              //
              // Download is the exception and stays: the bar button for it is
              // in the PHONE branch only, so on desktop this sheet is the only
              // way to start one. Removing it took the feature off Windows,
              // macOS and Linux entirely.
              if (isDesktopPlatform && a.canDownload)
                _SettingsTile(
                  icon: Icons.download_rounded,
                  label: 'movie.download'.tr(),
                  value: '',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _startDownload();
                  },
                ),
              _SettingsTile(
                icon: Icons.aspect_ratio_rounded,
                label: 'player.aspect'.tr(),
                value: _fitLabel(_fit),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _openFitSheet();
                },
              ),
              // Absent on the platform player, which has no runtime picture
              // control at all. Offering a menu that silently does nothing
              // teaches people the app is broken rather than that the feature
              // is unavailable here.
              if (_controller?.supportsColorProfile ?? false)
                _SettingsTile(
                  icon: Icons.tune_rounded,
                  label: 'player.color_profile'.tr(),
                  value: _colorProfile.labelKey.tr(),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _openColorSheet();
                  },
                ),
              // Only on libmpv, which is the one backend that can read a frame
              // back. The platform player and the DRM one keep their pixels in
              // a texture the Dart side never sees, so the row is absent there
              // rather than present and producing nothing.
              //
              // Live has no frame worth sharing and no title to attach it to.
              if (!_isLive && (_controller?.supportsShaders ?? false))
                _SettingsTile(
                  icon: Icons.photo_camera_outlined,
                  label: 'player.share_frame'.tr(),
                  value: '',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _shareCurrentFrame();
                  },
                ),
              // Sharing and keeping are different intentions, and routing
              // "keep" through the share sheet made it a three-tap detour via
              // whichever app the system decided could save a file. The frame
              // people wanted was also the one the system screenshot key could
              // not give them: that one carries the controls, the seek bar and
              // the status bar burnt into it, at the screen's resolution
              // rather than the video's.
              if (!_isLive && (_controller?.supportsShaders ?? false))
                _SettingsTile(
                  icon: Icons.save_alt_rounded,
                  label: 'player.save_frame'.tr(),
                  value: '',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _saveCurrentFrame();
                  },
                ),
              // Always listed, disabled where it cannot run.
              //
              // It used to disappear entirely on the platform player, which is
              // the default on most devices — so Anime4K, sharpen, deblur and
              // denoise were invisible to the people most likely to want them,
              // with nothing on screen to say the feature existed or why it was
              // absent. A row that explains itself beats a row that is not
              // there.
              if (_controller?.supportsShaders ?? false)
                _SettingsTile(
                  icon: Icons.auto_awesome_rounded,
                  label: 'player.shaders'.tr(),
                  value: _shaderPreset.isOff
                      ? 'general.off'.tr()
                      : _shaderPreset.labelKey.tr(),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _openShaderSheet();
                  },
                )
              else
                _SettingsTile(
                  icon: Icons.auto_awesome_rounded,
                  label: 'player.shaders'.tr(),
                  value: 'player.needs_media_kit'.tr(),
                  onTap: null,
                ),
              // Shown here, and not only in Settings, so a mode that suppresses
              // history cannot sit on unnoticed for weeks: the sheet is the one
              // surface a viewer opens mid-episode, and this is where they will
              // wonder why nothing is in Continue Watching.
              if (_hive.isIncognito)
                _SettingsTile(
                  icon: Icons.visibility_off_outlined,
                  label: 'profile.incognito'.tr(),
                  value: 'general.on'.tr(),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _hive.setIncognito(false);
                    if (!mounted) return;
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('profile.incognito_off'.tr()),
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              // Hidden rather than disabled when the stream cannot be cast — a
              // torrent handle or a downloaded file has no address a device on
              // the network could fetch, and a greyed-out row invites a tap
              // that can only ever explain itself.
              if (_canCast)
                _SettingsTile(
                  icon: _cast.isCasting
                      ? Icons.cast_connected_rounded
                      : Icons.cast_rounded,
                  label: 'player.cast'.tr(),
                  value: _cast.device?.name ?? '—',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    if (_cast.isCasting) {
                      _stopCasting();
                    } else {
                      _openCastSheet();
                    }
                  },
                ),
              // Not offered for live TV: a broadcast has no end to stop at, and
              // a countdown that pauses a channel is just a mute button with
              // extra steps.
              if (!_isLive)
                _SettingsTile(
                  icon: Icons.bedtime_outlined,
                  label: 'player.sleep_timer'.tr(),
                  value: _sleepValueLabel,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _openSleepSheet();
                  },
                ),
              if (hasLangs)
                _SettingsTile(
                  icon: Icons.translate_rounded,
                  label: 'player.audio_language'.tr(),
                  value: _currentLang == null ? '—' : _langLabel(_currentLang!),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _openLangSheet();
                  },
                ),
              if (_subtitles.isNotEmpty)
                _SettingsTile(
                  icon: Icons.text_fields_rounded,
                  label: 'player.subtitle_style'.tr(),
                  value: '${_subtitleStyle.fontSize.round()}px',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _openSubtitleAppearanceSheet();
                  },
                ),
              // Audio tracks are a media_kit capability: video_player exposes no
              // track-selection API at all. Under the default engine the tile
              // stays disabled and says why, rather than opening an empty sheet.
              if (!hasLangs)
                Builder(
                  builder: (_) {
                    final c = _controller;
                    final supported = c?.supportsAudioTracks ?? false;
                    final tracks = c?.audioTracks ?? const <PlayerAudioTrack>[];
                    if (!supported) {
                      return _SettingsTile(
                        icon: Icons.audiotrack_outlined,
                        label: 'player.audio_track'.tr(),
                        value: 'player.audio_track_engine_only'.tr(),
                        onTap: null,
                      );
                    }
                    return _SettingsTile(
                      icon: Icons.audiotrack_outlined,
                      label: 'player.audio_track'.tr(),
                      value: tracks.length < 2
                          ? 'player.audio_track_single'.tr()
                          : _activeAudioTrackLabel(),
                      onTap: tracks.length < 2
                          ? null
                          : () {
                              Navigator.of(sheetContext).pop();
                              _openAudioTrackSheet();
                            },
                    );
                  },
                ),
              if (ExternalPlayer.isSupported && _videoUrl != null)
                _SettingsTile(
                  icon: Icons.open_in_new_rounded,
                  label: 'player.external_player'.tr(),
                  value: '',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _handOffToExternalPlayer();
                  },
                ),
              // Was `showDownloadAction && provider != 'uzmovi'` — the url
              // Beside the diagnostics log, which answers the same question
              // for whoever wrote the player. This one answers it for whoever
              // is watching — and is small enough to screenshot into a report.
              _SettingsTile(
                icon: Icons.info_outline_rounded,
                label: 'player.info_title'.tr(),
                value: _showPlayerInfo ? 'player.on'.tr() : 'player.off'.tr(),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  setState(() => _showPlayerInfo = !_showPlayerInfo);
                },
              ),
              _SettingsTile(
                icon: Icons.tune_rounded,
                label: 'player.info_fields_title'.tr(),
                value: '',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _openInfoFieldsPicker();
                },
              ),
              _SettingsTile(
                icon: Icons.dashboard_customize_outlined,
                label: 'player.layout_title'.tr(),
                value: '',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _openControlsLayoutPage();
                },
              ),
              _SettingsTile(
                icon: Icons.bug_report_outlined,
                label: 'player.diagnostics_logs'.tr(),
                value: '',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  LogViewerSheet.show(context);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// [PlayerAudioTrack.label] already resolves language codes to native names,
  /// but it cannot translate its own positional fallback — core has no
  /// business reaching for the locale. So do that one case here.
  String _audioTrackLabel(PlayerAudioTrack t) {
    if (t.hasMetadata) return t.label;
    return 'player.audio_track_numbered'
        .tr(args: <String>[t.ordinal.toString()]);
  }

  String _activeAudioTrackLabel() {
    final c = _controller;
    if (c == null) return '—';
    final active = c.activeAudioTrackId;
    for (final t in c.audioTracks) {
      if (t.id == active) return _audioTrackLabel(t);
    }
    return '—';
  }

  /// Audio-track picker. media_kit only — the caller already guarantees
  /// [PlayerController.supportsAudioTracks], so there is no empty state here.
  void _openAudioTrackSheet() {
    final c = _controller;
    if (c == null || !c.supportsAudioTracks) return;
    final tracks = c.audioTracks;
    if (tracks.length < 2) return;
    showAdaptiveModal<void>(
      context: context,
      backgroundColor: const Color(0xFF111111),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.audiotrack_outlined,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'player.audio_track'.tr(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white12, height: 1),
              for (final t in tracks)
                _OptionTile(
                  label: _audioTrackLabel(t),
                  selected: t.id == c.activeAudioTrackId,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _switchAudioTrack(t.id);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _switchAudioTrack(String id) async {
    final c = _controller;
    if (c == null) return;
    await c.setAudioTrack(id);
    if (mounted) setState(() {});
  }

  /// Hands the current stream to VLC / MX Player.
  ///
  /// Warns first when the stream is header-gated: an intent carries no
  /// Referer/Origin, so those sources 403 in the external app and present as a
  /// black screen. Better to say so than to launch into one.
  Future<void> _handOffToExternalPlayer() async {
    final url = _videoUrl;
    if (url == null || url.isEmpty) return;
    final headers = _headers;
    if (!ExternalPlayer.canHandOff(url, headers)) {
      final proceed = await showAdaptiveDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: Text(
            'player.external_player'.tr(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: Text(
            'player.external_player_gated'.tr(),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text('general.cancel'.tr()),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text('player.external_player_try'.tr()),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }
    await _controller?.pause();
    final ok = await ExternalPlayer.open(
      url: url,
      title: widget.args.title,
      headers: headers,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('player.external_player_none'.tr())),
      );
    }
  }

  void _openSpeedSheet() {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    showAdaptiveModal<void>(
      context: context,
      backgroundColor: const Color(0xFF111111),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(
                  children: [
                    const Icon(Icons.speed_rounded,
                        color: Colors.white, size: 18),
                    const SizedBox(width: 10),
                    Text(
                      'player.speed'.tr(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white12, height: 1),
              for (final s in speeds)
                _OptionTile(
                  label:
                      '${s.toStringAsFixed(s == s.roundToDouble() ? 0 : 2)}x',
                  selected: s == _playbackSpeed,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _setSpeed(s);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _openFitSheet() {
    showAdaptiveModal<void>(
      context: context,
      backgroundColor: const Color(0xFF111111),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.aspect_ratio_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'player.aspect_ratio'.tr(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white12, height: 1),
              for (final fit in _PlayerFit.values)
                _OptionTile(
                  label: _fitLabel(fit),
                  selected: fit == _fit,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _setFit(fit);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// The picture menu.
  ///
  /// Applied on tap rather than behind an Apply button: the whole judgement is
  /// "does this look better", and that cannot be made from a name. Every entry
  /// is reversible in one tap, and Natural is the untouched picture rather than
  /// an approximation of it, so there is no way to get stuck somewhere worse
  /// than where you started.
  void _openColorSheet() {
    showAdaptiveModal<void>(
      context: context,
      backgroundColor: const Color(0xFF111111),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: StatefulBuilder(
            builder: (context, setSheetState) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.tune_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'player.color_profile'.tr(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(color: Colors.white12, height: 1),
                for (final profile in ColorProfile.all)
                  _OptionTile(
                    label: profile.labelKey.tr(),
                    selected: profile.id == _colorProfile.id,
                    // The sheet stays open. Comparing two looks means switching
                    // back and forth, and a menu that closes on every tap makes
                    // that four gestures instead of one.
                    onTap: () {
                      _setColorProfile(profile);
                      setSheetState(() {});
                    },
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _setColorProfile(ColorProfile profile) async {
    setState(() => _colorProfile = profile);
    await _hive.setColorProfile(profile.id);
    await _controller?.setColorProfile(profile);
  }

  /// The Anime4K menu.
  ///
  /// The tier sits under the presets rather than in Settings because it is
  /// part of the same judgement — "is this better, and does it still run
  /// smoothly" — and that can only be made while something is playing.
  void _openShaderSheet() {
    showAdaptiveModal<void>(
      context: context,
      backgroundColor: const Color(0xFF111111),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: StatefulBuilder(
            builder: (context, setSheetState) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.auto_awesome_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'player.shaders'.tr(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: Text(
                    'player.shaders_note'.tr(),
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 11.5,
                      height: 1.4,
                    ),
                  ),
                ),
                const Divider(color: Colors.white12, height: 1),
                for (final preset in ShaderPreset.all)
                  _OptionTile(
                    label: preset.labelKey.tr(),
                    subtitle: preset.descriptionKey.tr(),
                    selected: preset.id == _shaderPreset.id,
                    onTap: () {
                      _setShaderPreset(preset);
                      setSheetState(() {});
                    },
                  ),
                // Hidden while off, because a GPU budget for a chain that is
                // not running is a setting with no effect to observe.
                if (!_shaderPreset.isOff) ...[
                  const Divider(color: Colors.white12, height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                    child: Text(
                      'player.shader_tier'.tr(),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  for (final tier in ShaderTier.values)
                    _OptionTile(
                      label: tier.labelKey.tr(),
                      subtitle: tier.descriptionKey.tr(),
                      selected: tier.id == _shaderTier.id,
                      onTap: () {
                        _setShaderTier(tier);
                        setSheetState(() {});
                      },
                    ),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _setShaderPreset(ShaderPreset preset) async {
    setState(() => _shaderPreset = preset);
    await _hive.setShaderPreset(preset.id);
    final controller = _controller;
    if (controller != null) await _applyShaders(controller);
  }

  Future<void> _setShaderTier(ShaderTier tier) async {
    setState(() => _shaderTier = tier);
    await _hive.setShaderTier(tier.id);
    final controller = _controller;
    if (controller != null) await _applyShaders(controller);
  }

  /// Shares the frame on screen.
  ///
  /// Paused first, and deliberately: a share sheet takes a second to appear and
  /// the video would otherwise be somewhere else by the time it does, so the
  /// picture people send would not be the picture they were looking at.
  ///
  /// The position is not restored afterwards — nothing moved, it was only
  /// paused, and resuming for somebody who wanted the video stopped to look at
  /// a frame would be the app arguing with them.
  Future<void> _shareCurrentFrame() async {
    final controller = _controller;
    if (controller == null) return;
    await controller.pause();

    final bytes = await controller.grabFrame();
    if (!mounted) return;
    if (bytes == null || bytes.isEmpty) {
      _PlayerSubtitles(this)._toast('player.share_frame_failed'.tr());
      return;
    }

    try {
      // Written to a temp file rather than shared as bytes: several targets
      // accept only a file, and the ones that accept bytes accept a file too.
      final dir = await getTemporaryDirectory();
      final safeTitle = widget.args.title
          .replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '')
          .trim();
      final file = File(
        '${dir.path}/${safeTitle.isEmpty ? 'sozo' : safeTitle}'
        '-${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles([XFile(file.path)], text: widget.args.title);
    } catch (e) {
      _plog('share frame failed: $e', level: LogLevel.warn);
      if (mounted) _PlayerSubtitles(this)._toast('player.share_frame_failed'.tr());
    }
  }

  /// Saves the frame on screen to the device gallery.
  ///
  /// Paused first for the same reason sharing is: the write and the permission
  /// prompt both take a moment, and the frame that lands in the gallery has to
  /// be the frame that was being looked at.
  ///
  /// A file is written and handed to `gal` rather than the bytes being passed
  /// directly, because the file is what carries a NAME. A gallery full of
  /// `image_1725186000.jpg` is a gallery nobody can search; `Sozo - <title> -
  /// 00-42-17.jpg` says which film, and where in it, months later.
  Future<void> _saveCurrentFrame() async {
    final controller = _controller;
    if (controller == null) return;
    await controller.pause();

    final bytes = await controller.grabFrame();
    if (!mounted) return;
    if (bytes == null || bytes.isEmpty) {
      _PlayerSubtitles(this)._toast('player.save_frame_failed'.tr());
      return;
    }

    try {
      // Android 10+ and iOS both want the app to ask before writing to the
      // shared photo library. `gal` asks on the platforms that require it and
      // returns true where no prompt exists, so there is nothing to branch on.
      if (!await Gal.hasAccess(toAlbum: true)) {
        if (!await Gal.requestAccess(toAlbum: true)) {
          if (mounted) {
            _PlayerSubtitles(this)._toast('player.save_frame_denied'.tr());
          }
          return;
        }
      }

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${_frameFileName()}');
      await file.writeAsBytes(bytes, flush: true);

      // Into an album of its own, so screenshots taken over months are one
      // scroll rather than scattered through the camera roll by date.
      await Gal.putImage(file.path, album: 'Sozo');

      // The temp copy has served its purpose the moment the gallery has one.
      unawaited(file.delete().catchError((_) => file));

      if (mounted) _PlayerSubtitles(this)._toast('player.save_frame_done'.tr());
    } on GalException catch (e) {
      _plog('save frame failed: ${e.type}', level: LogLevel.warn);
      if (mounted) {
        _PlayerSubtitles(this)._toast(
          e.type == GalExceptionType.accessDenied
              ? 'player.save_frame_denied'.tr()
              : 'player.save_frame_failed'.tr(),
        );
      }
    } catch (e) {
      _plog('save frame failed: $e', level: LogLevel.warn);
      if (mounted) {
        _PlayerSubtitles(this)._toast('player.save_frame_failed'.tr());
      }
    }
  }

  /// `Sozo - <title> - <hh-mm-ss>.jpg`, with everything a filesystem might
  /// object to removed. The timestamp is the position in the video rather than
  /// the wall clock: it is the half of the name that is actually useful when
  /// the file turns up again later.
  String _frameFileName() {
    final safeTitle = widget.args.title
        .replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '')
        .trim();
    final pos = _controller?.value.position ?? Duration.zero;
    final stamp = pos
        .toString()
        .split('.')
        .first
        .padLeft(8, '0')
        .replaceAll(':', '-');
    return 'Sozo - ${safeTitle.isEmpty ? 'frame' : safeTitle} - $stamp.jpg';
  }

  Widget _buildSidePanel() {
    final isQuality = _panel == _SidePanel.quality;
    final sources = _currentServerSources;

    // Portrait phone: a full-height drawer over four quality rows covered the
    // video and matched nothing else in the player, where every other list —
    // speed, subtitles, servers, settings — arrives from the bottom. Landscape
    // and TV keep the drawer: there the height is the usable dimension.
    final asSheet = !isTvPlatform && !isDesktopPlatform && _isPortrait;

    final tracks = _engineVideoTracks;
    final list = isQuality
        ? (tracks.isNotEmpty
            // Renditions of the stream that is playing. Preferred over the
            // mirror list because switching between them is instant and keeps
            // the position, where switching mirror is a reload.
            ? ListView.separated(
                controller: _tvPanelScroll,
                shrinkWrap: asSheet,
                padding: EdgeInsets.zero,
                itemCount: tracks.length,
                separatorBuilder: (_, _) => Divider(
                  color: Colors.white.withValues(alpha: 0.06),
                  height: 1,
                ),
                itemBuilder: (_, i) => _VideoTrackRow(
                  track: tracks[i],
                  isActive: tracks[i].id == (_controller?.activeVideoTrackId),
                  onTap: () => _switchVideoTrack(tracks[i]),
                ),
              )
            : ListView.separated(
            controller: _tvPanelScroll,
            shrinkWrap: asSheet,
            padding: EdgeInsets.zero,
            itemCount: sources.length,
            separatorBuilder: (_, _) => Divider(
              color: Colors.white.withValues(alpha: 0.06),
              height: 1,
            ),
            itemBuilder: (_, i) {
              final src = _videoSources[sources[i]];
              return _QualityRow(
                source: _resolutionOnly(src),
                isActive: src.quality == _currentQuality,
                onTap: () => _switchQuality(src),
              );
            },
          ))
        : ListView.separated(
            // Non-null only on TV (see _openPanel), where it opens
            // the list near the episode being watched.
            controller: _tvPanelScroll,
            shrinkWrap: asSheet,
            padding: EdgeInsets.zero,
            itemCount: _episodes.length,
            separatorBuilder: (_, _) => Divider(
              color: Colors.white.withValues(alpha: 0.06),
              height: 1,
            ),
            itemBuilder: (_, i) => _EpisodeRow(
              episode: _episodes[i],
              isActive: i == _episodeIndex,
              onTap: () => _partyEpisodeNav(i),
            ),
          );

    final body = Column(
      mainAxisSize: asSheet ? MainAxisSize.min : MainAxisSize.max,
      children: [
        if (asSheet)
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 10),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 8, 8),
          child: Row(
            children: [
              Text(
                isQuality ? 'player.quality'.tr() : 'player.episodes'.tr(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: _closePanel,
                focusColor: _kTvFocusFill,
                icon: const Icon(Icons.close_rounded, color: Colors.white70),
              ),
            ],
          ),
        ),
        if (asSheet) Flexible(child: list) else Expanded(child: list),
      ],
    );

    final surface = Material(
      color: Colors.black.withValues(alpha: 0.92),
      shape: asSheet
          ? const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            )
          : null,
      child: SafeArea(
        // The panel hugs the right edge, so the left cutout inset is not its
        // to pay — honouring it just narrowed every row by ~44dp.
        left: false,
        top: !asSheet,
        // Its own focus scope so _openPanel can hand the remote over and
        // _closePanel can hand it back — see [_tvPanelFocus].
        child: FocusScope(node: _tvPanelFocus, child: body),
      ),
    );

    if (asSheet) {
      return Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.55,
          ),
          child: surface,
        ),
      );
    }

    return Positioned(
      top: 0,
      bottom: 0,
      right: 0,
      // Wider on TV: 320dp is a phone drawer, and at 10 feet the episode
      // labels in it truncate to uselessness.
      width: isTvPlatform ? 420 : 320,
      child: surface,
    );
  }
}

class _ServerTile extends StatelessWidget {
  const _ServerTile({
    required this.label,
    required this.qualities,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String qualities;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      autofocus: isTvPlatform && selected,
      focusColor: _kTvFocusFill,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // A coloured mark instead of a radio dot. Six rows reading
            // "Server 1" … "Server 6" are indistinguishable at a glance, and
            // the one that works is found by trial — so what is worth
            // remembering is which one it WAS, and a name differing by one
            // digit is not something anybody remembers.
            ServerBadge(name: label, selected: selected),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? Colors.white : Colors.white70,
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                  if (qualities.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      qualities,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // The tick sits at the trailing edge now: a radio dot beside a
            // coloured square read as two competing selection indicators.
            if (selected)
              const Icon(Icons.check_rounded, color: Colors.white, size: 20),
          ],
        ),
      ),
    );
  }
}
