// ignore_for_file: invalid_use_of_protected_member
part of 'player_page.dart';

/// The native pull-down menus of the iOS 26 controls: a flat choice opens
/// as the phone's own menu on the button, where the Flutter sheet held
/// nothing more. Built only on that path ([_nativeBars]); the Flutter
/// buttons keep their sheets.
extension _PlayerMenus on _PlayerPageState {
  PlayerMenu get _speedMenu => choiceMenu<double>(
    values: _PlayerPanels._speedPresets,
    isCurrent: (s) => (s - _playbackSpeed).abs() < 0.01,
    label: _speedLabel,
    onPick: _setSpeed,
  );

  PlayerMenu get _fitMenu => choiceMenu<_PlayerFit>(
    values: _PlayerFit.values,
    isCurrent: (f) => f == _fit,
    label: _fitLabel,
    symbol: _PlayerControls._fitSymbol,
    onPick: _setFit,
  );

  /// Everything the sleep sheet offers.
  PlayerMenu get _sleepMenu {
    String label(Duration d) => d.inMinutes < 60
        ? 'player.sleep_minutes'.tr(args: ['${d.inMinutes}'])
        : 'player.sleep_hours'.tr(args: ['${d.inHours}']);
    return PlayerMenu([
      if (_sleepArmed)
        [
          PlayerMenuOption(
            key: 'off',
            title: 'general.off'.tr(),
            onPick: _cancelSleepTimer,
          ),
        ],
      [
        for (final d in _PlayerSleepTimer._presets)
          PlayerMenuOption(
            key: d,
            title: label(d),
            onPick: () => _armSleepDuration(d),
          ),
      ],
      if (widget.args.isSerial)
        [
          PlayerMenuOption(
            key: 'episode',
            title: 'player.sleep_episode_end'.tr(),
            checked: _sleepAtEpisodeEnd,
            onPick: _armSleepAtEpisodeEnd,
          ),
        ],
    ]);
  }

  /// Sub or dub; null with one to choose from.
  PlayerMenu? get _langMenu {
    final langs = _availableLangsForCurrentEpisode();
    if (langs.length < 2) return null;
    return choiceMenu<String>(
      values: langs,
      isCurrent: (l) => l == _currentLang,
      label: _langLabel,
      onPick: _switchLang,
    );
  }

  /// The hosts, each with the heights it offers; null with one host.
  PlayerMenu? get _serverMenu {
    final servers = _sourceServers;
    if (servers.length < 2) return null;
    final labels = _sourceLabels;
    return choiceMenu<String>(
      values: servers,
      isCurrent: (s) => s == _currentServer,
      label: (s) => s,
      subtitle: (s) {
        final q = VideoOptionGroups.qualitiesFor(labels, s).join(' · ');
        return q.isEmpty ? null : q;
      },
      onPick: _switchServer,
    );
  }

  /// The rows the quality panel lists, the panel's own choice of them.
  PlayerMenu? get _qualityMenu {
    final tracks = _engineVideoTracks;
    final active = _controller?.activeVideoTrackId;
    QualityMenuEntry file(int i, {required bool selected}) {
      final src = _videoSources[i];
      final worst = StreamWarning.worst(src);
      return QualityMenuEntry(
        key: ('file', i),
        label: _qualityLabel(src.quality),
        detail:
            worst?.message ??
            (src.isDefault ? 'player.recommended'.tr() : null),
        blocking: worst?.risk == StreamRisk.blocking,
        selected: selected,
        onPick: () => _switchQuality(src),
      );
    }

    if (tracks.isNotEmpty) {
      return qualityMenu(
        renditions: [
          for (final t in tracks)
            QualityMenuEntry(
              key: ('track', t.id),
              label: t.isAuto ? 'player.auto'.tr() : t.label,
              detail: t.isAuto ? 'player.auto_quality_desc_mpv'.tr() : t.detail,
              selected: t.id == active,
              onPick: () => _switchVideoTrack(t),
            ),
        ],
        files: [for (final i in _otherServerSources) file(i, selected: false)],
      );
    }
    return qualityMenu(
      renditions: [
        for (final i in _currentServerSources)
          file(i, selected: i == _currentSourceIndex),
      ],
      files: const [],
    );
  }

  /// The tracks, Off, and the full sheet last.
  PlayerMenu? get _subtitleMenu {
    final c = _controller;
    final embedded = c?.subtitleTracks ?? const <PlayerSubtitleTrack>[];
    return subtitleMenu(
      offLabel: 'player.off'.tr(),
      offSelected:
          _activeSubtitleIndex == -1 && c?.activeSubtitleTrackId == null,
      onOff: _disableSubtitle,
      tracks: [
        for (final t in embedded)
          SubtitleMenuTrack(
            key: ('embedded', t.id),
            label: t.hasMetadata
                ? t.label
                : 'player.subtitle_n'.tr(args: ['${t.ordinal}']),
            subtitle: 'player.subtitle_in_video'.tr(),
            selected:
                _activeSubtitleIndex == -1 && c?.activeSubtitleTrackId == t.id,
            onPick: () => _selectEmbeddedSubtitle(t),
          ),
        for (var i = 0; i < _subtitles.length; i++)
          SubtitleMenuTrack(
            key: ('file', i),
            label: _subtitles[i].label,
            subtitle: i == _secondarySubtitleIndex
                ? 'player.second_track'.tr()
                : null,
            selected: i == _activeSubtitleIndex,
            onPick: () => _loadSubtitle(i),
          ),
      ],
      moreLabel: 'detail.more_options'.tr(),
      onMore: _openSubtitleSheet,
    );
  }
}
